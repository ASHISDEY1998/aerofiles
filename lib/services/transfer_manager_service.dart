import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/vfs_node.dart';
import 'file_operation_service.dart';
import 'log_service.dart';
import 'recycle_bin_service.dart';
import 'vfs/local_vfs.dart';
import 'vfs/sftp_vfs.dart';
import 'vfs/smb_vfs.dart';
import 'vfs/vfs_provider.dart';
import 'vfs/webdav_vfs.dart';

enum TransferStatus {
  pending,
  transferring,
  completed,
  failed,
  canceled,
}

class TransferTask {
  final String id;
  final String name;
  final String sourcePath;
  final String destPath;
  final int totalBytes;
  int transferredBytes;
  TransferStatus status;
  final bool isMove;
  final bool isDirectory;
  String? errorMessage;
  double speedBytesPerSec;

  TransferTask({
    required this.id,
    required this.name,
    required this.sourcePath,
    required this.destPath,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.status = TransferStatus.pending,
    required this.isMove,
    this.isDirectory = false,
    this.errorMessage,
    this.speedBytesPerSec = 0,
  });

  double get progress {
    if (status == TransferStatus.completed) return 1.0;
    if (totalBytes <= 0) return 0.0;
    return (transferredBytes / totalBytes).clamp(0.0, 1.0);
  }

  String get formattedTotalSize => _formatBytes(totalBytes);
  String get formattedTransferred => _formatBytes(transferredBytes);

  String get formattedSpeed {
    if (status != TransferStatus.transferring || speedBytesPerSec <= 0) {
      return '';
    }
    return '${_formatBytes(speedBytesPerSec.toInt())}/s';
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(count >= 10 ? 1 : 2)} ${suffixes[i]}';
  }
}

class TransferManagerService {
  static final TransferManagerService instance = TransferManagerService._();
  TransferManagerService._();

  final ValueNotifier<bool> isTransferring = ValueNotifier<bool>(false);
  final ValueNotifier<List<TransferTask>> tasks = ValueNotifier<List<TransferTask>>([]);
  final ValueNotifier<double> overallProgress = ValueNotifier<double>(0.0);
  final ValueNotifier<String> overallSpeed = ValueNotifier<String>('');
  final ValueNotifier<String> overallSummary = ValueNotifier<String>('');

  // Event stream to notify when any batch transfer completes
  final StreamController<void> _onTransferFinished = StreamController<void>.broadcast();
  Stream<void> get onTransferFinished => _onTransferFinished.stream;

  bool _isProcessing = false;
  bool _cancelCurrentBatch = false;

  int _lastBytesSnapshot = 0;
  DateTime _lastSnapshotTime = DateTime.now();

  Future<void> startTransfer({
    required List<VfsNode> items,
    required String targetDirPath,
    required VfsProvider targetVfs,
    required VfsProvider sourceVfs,
    required bool isMove,
  }) async {
    if (items.isEmpty) return;

    LogService.instance.info(
      'TRANSFER_MGR',
      'Enqueuing transfer of ${items.length} items to ${targetVfs.displayName} ($targetDirPath), isMove=$isMove',
    );

    _cancelCurrentBatch = false;

    // Expand directories to individual file tasks for granular progress
    final List<TransferTask> newTasks = [];
    for (final node in items) {
      if (node.isDirectory && sourceVfs is LocalVfs) {
        final dir = Directory(node.path);
        if (await dir.exists()) {
          await _expandLocalDirectory(dir, node.name, targetDirPath, isMove, newTasks);
        }
      } else {
        final destPath = p.join(targetDirPath, node.name);
        newTasks.add(
          TransferTask(
            id: '${DateTime.now().microsecondsSinceEpoch}_${newTasks.length}',
            name: node.name,
            sourcePath: node.path,
            destPath: destPath,
            totalBytes: node.size,
            isMove: isMove,
            isDirectory: node.isDirectory,
          ),
        );
      }
    }

    if (newTasks.isEmpty) return;

    // Append to existing active task list
    final updatedList = List<TransferTask>.from(tasks.value)..addAll(newTasks);
    tasks.value = updatedList;
    isTransferring.value = true;
    _updateProgressMetrics();

    if (!_isProcessing) {
      _processQueue(sourceVfs: sourceVfs, targetVfs: targetVfs);
    }
  }

  Future<void> _expandLocalDirectory(
    Directory dir,
    String rootFolderRel,
    String targetBaseDir,
    bool isMove,
    List<TransferTask> outTasks,
  ) async {
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final relPath = p.relative(entity.path, from: p.dirname(dir.path));
          final destPath = p.join(targetBaseDir, relPath);
          final size = await entity.length();
          outTasks.add(
            TransferTask(
              id: '${DateTime.now().microsecondsSinceEpoch}_${outTasks.length}',
              name: p.basename(entity.path),
              sourcePath: entity.path,
              destPath: destPath,
              totalBytes: size,
              isMove: isMove,
              isDirectory: false,
            ),
          );
        }
      }
    } catch (e) {
      LogService.instance.error('TRANSFER_MGR', 'Error expanding directory ${dir.path}: $e');
    }
  }

  Future<void> _processQueue({
    required VfsProvider sourceVfs,
    required VfsProvider targetVfs,
  }) async {
    _isProcessing = true;
    _lastSnapshotTime = DateTime.now();
    _lastBytesSnapshot = 0;

    try {
      while (true) {
        // Find next pending task
        TransferTask? current;
        for (final t in tasks.value) {
          if (t.status == TransferStatus.pending) {
            current = t;
            break;
          }
        }

        if (current == null || _cancelCurrentBatch) {
          break;
        }

        current.status = TransferStatus.transferring;
        tasks.value = List.from(tasks.value);
        _updateProgressMetrics();

        final success = await _executeTransfer(
          task: current,
          sourceVfs: sourceVfs,
          targetVfs: targetVfs,
        );

        if (_cancelCurrentBatch || current.status == TransferStatus.canceled) {
          current.status = TransferStatus.canceled;
        } else if (success) {
          current.status = TransferStatus.completed;
          current.transferredBytes = current.totalBytes;

          // Safe Move: ONLY delete source file after remote upload verified!
          if (current.isMove) {
            try {
              await sourceVfs.delete(current.sourcePath, moveToTrash: false);
              if (sourceVfs is LocalVfs) {
                await RecycleBinService.notifyMediaScanner(current.sourcePath);
              }
              LogService.instance.info('TRANSFER_MGR', 'Moved: safely deleted local source ${current.sourcePath}');
            } catch (e) {
              LogService.instance.warn('TRANSFER_MGR', 'Could not delete source after copy: $e');
            }
          }
        } else {
          current.status = TransferStatus.failed;
          current.errorMessage ??= 'Transfer failed';
        }

        tasks.value = List.from(tasks.value);
        _updateProgressMetrics();
      }
    } catch (e, st) {
      LogService.instance.error('TRANSFER_MGR', 'Unexpected queue processing error: $e', e, st);
    } finally {
      _isProcessing = false;
      await FileOperationService.stopNotification();
      _onTransferFinished.add(null);

      // Keep bubble alive for 2 seconds so user sees 100% checkmark, then dismiss
      Future.delayed(const Duration(milliseconds: 2200), () {
        final anyActive = tasks.value.any(
          (t) => t.status == TransferStatus.pending || t.status == TransferStatus.transferring,
        );
        if (!anyActive) {
          isTransferring.value = false;
        }
      });
    }
  }

  Future<bool> _executeTransfer({
    required TransferTask task,
    required VfsProvider sourceVfs,
    required VfsProvider targetVfs,
  }) async {
    LogService.instance.info(
      'TRANSFER_MGR',
      'Transferring "${task.name}" (${task.formattedTotalSize}) -> ${task.destPath}',
    );

    try {
      // 1. Local -> SMB
      if (sourceVfs is LocalVfs && targetVfs is SmbVfs) {
        final localFile = File(task.sourcePath);
        if (!await localFile.exists()) {
          task.errorMessage = 'Local source file not found';
          return false;
        }
        return await targetVfs.writeLocalFile(
          task.destPath,
          localFile,
          onProgress: (sent, total) => _onChunkTransferred(task, sent, total),
          isCanceled: () => _cancelCurrentBatch || task.status == TransferStatus.canceled,
        );
      }

      // 2. Local -> SFTP
      if (sourceVfs is LocalVfs && targetVfs is SftpVfs) {
        final localFile = File(task.sourcePath);
        if (!await localFile.exists()) {
          task.errorMessage = 'Local source file not found';
          return false;
        }
        return await targetVfs.writeLocalFile(
          task.destPath,
          localFile,
          onProgress: (sent, total) => _onChunkTransferred(task, sent, total),
          isCanceled: () => _cancelCurrentBatch || task.status == TransferStatus.canceled,
        );
      }

      // 3. Local -> WebDAV
      if (sourceVfs is LocalVfs && targetVfs is WebDavVfs) {
        final localFile = File(task.sourcePath);
        if (!await localFile.exists()) {
          task.errorMessage = 'Local source file not found';
          return false;
        }
        return await targetVfs.writeLocalFile(
          task.destPath,
          localFile,
          onProgress: (sent, total) => _onChunkTransferred(task, sent, total),
          isCanceled: () => _cancelCurrentBatch || task.status == TransferStatus.canceled,
        );
      }

      // 4. SMB -> Local
      if (sourceVfs is SmbVfs && targetVfs is LocalVfs) {
        final localFile = File(task.destPath);
        return await sourceVfs.readToLocalFile(
          task.sourcePath,
          localFile,
          onProgress: (sent, total) => _onChunkTransferred(task, sent, total),
          isCanceled: () => _cancelCurrentBatch || task.status == TransferStatus.canceled,
        );
      }

      // 5. SFTP -> Local
      if (sourceVfs is SftpVfs && targetVfs is LocalVfs) {
        final localFile = File(task.destPath);
        return await sourceVfs.readToLocalFile(
          task.sourcePath,
          localFile,
          onProgress: (sent, total) => _onChunkTransferred(task, sent, total),
          isCanceled: () => _cancelCurrentBatch || task.status == TransferStatus.canceled,
        );
      }

      // 6. WebDAV -> Local
      if (sourceVfs is WebDavVfs && targetVfs is LocalVfs) {
        final localFile = File(task.destPath);
        return await sourceVfs.readToLocalFile(
          task.sourcePath,
          localFile,
          onProgress: (sent, total) => _onChunkTransferred(task, sent, total),
          isCanceled: () => _cancelCurrentBatch || task.status == TransferStatus.canceled,
        );
      }

      // 7. Local -> Local
      if (sourceVfs is LocalVfs && targetVfs is LocalVfs) {
        final ok = await targetVfs.copy(
          task.sourcePath,
          task.destPath,
          onProgress: (pct) {
            final sent = (pct * task.totalBytes).toInt();
            _onChunkTransferred(task, sent, task.totalBytes);
          },
        );
        return ok;
      }

      // Fallback
      task.errorMessage = 'Unsupported VFS transfer pair';
      return false;
    } catch (e, st) {
      LogService.instance.error('TRANSFER_MGR', 'Transfer error on ${task.name}: $e', e, st);
      task.errorMessage = e.toString();
      return false;
    }
  }

  void _onChunkTransferred(TransferTask task, int sent, int total) {
    task.transferredBytes = sent;

    // Calculate rolling speed every 250ms
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastSnapshotTime).inMilliseconds;
    if (elapsedMs >= 250) {
      final bytesDiff = sent - _lastBytesSnapshot;
      if (bytesDiff > 0 && elapsedMs > 0) {
        task.speedBytesPerSec = (bytesDiff / (elapsedMs / 1000.0));
      }
      _lastBytesSnapshot = sent;
      _lastSnapshotTime = now;
      _updateProgressMetrics(activeTask: task);
    }
  }

  void _updateProgressMetrics({TransferTask? activeTask}) {
    final list = tasks.value;
    if (list.isEmpty) {
      overallProgress.value = 0.0;
      overallSpeed.value = '';
      overallSummary.value = '';
      return;
    }

    int totalBytes = 0;
    int transferredBytes = 0;
    int completedCount = 0;

    for (final t in list) {
      totalBytes += t.totalBytes;
      transferredBytes += t.transferredBytes;
      if (t.status == TransferStatus.completed) {
        completedCount++;
      }
    }

    final overall = totalBytes > 0 ? (transferredBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
    overallProgress.value = overall;

    final speedStr = activeTask != null ? activeTask.formattedSpeed : '';
    overallSpeed.value = speedStr;

    final summaryStr = '$completedCount of ${list.length} transferred';
    overallSummary.value = summaryStr;

    // Android foreground notification
    final pctInt = (overall * 100).toInt();
    final currentName = activeTask?.name ?? 'Processing...';
    FileOperationService.updateNotification(
      title: 'Transferring ${list.length} file${list.length == 1 ? '' : 's'} ($pctInt%)',
      content: speedStr.isNotEmpty ? '$speedStr • $currentName' : currentName,
      progress: pctInt,
      max: 100,
    );
  }

  void cancelTask(String id) {
    for (final t in tasks.value) {
      if (t.id == id) {
        t.status = TransferStatus.canceled;
        break;
      }
    }
    tasks.value = List.from(tasks.value);
    _updateProgressMetrics();
  }

  void cancelAll() {
    _cancelCurrentBatch = true;
    for (final t in tasks.value) {
      if (t.status == TransferStatus.pending || t.status == TransferStatus.transferring) {
        t.status = TransferStatus.canceled;
      }
    }
    tasks.value = List.from(tasks.value);
    _updateProgressMetrics();
    FileOperationService.stopNotification();
    isTransferring.value = false;
  }

  void clearFinished() {
    tasks.value = tasks.value
        .where((t) => t.status == TransferStatus.pending || t.status == TransferStatus.transferring)
        .toList();
    _updateProgressMetrics();
    if (tasks.value.isEmpty) {
      isTransferring.value = false;
    }
  }
}
