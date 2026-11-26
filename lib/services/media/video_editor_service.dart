import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../log_service.dart';
import '../recycle_bin_service.dart';
import '../settings_service.dart';

class VideoMetadata {
  final Duration duration;
  final int width;
  final int height;
  final int rotation;
  final int sizeBytes;

  const VideoMetadata({
    required this.duration,
    required this.width,
    required this.height,
    required this.rotation,
    required this.sizeBytes,
  });

  bool get isPortrait => rotation == 90 || rotation == 270 || height > width;

  double get aspectRatio {
    if (width == 0 || height == 0) return 16 / 9;
    if (rotation == 90 || rotation == 270) {
      return height / width;
    }
    return width / height;
  }
}

enum VideoSaveOption {
  keepOriginal,
  replaceOriginal,
}

class VideoEditorService {
  static final VideoEditorService instance = VideoEditorService._();
  VideoEditorService._();

  bool _channelInitialized = false;
  void _ensureChannelInitialized() {
    if (_channelInitialized) return;
    try {
      _channel.setMethodCallHandler(_handleNativeCall);
      _channelInitialized = true;
    } catch (_) {}
  }

  static const MethodChannel _channel = MethodChannel('com.aerofiles.app/video_editor');
  static const MethodChannel _storageChannel = MethodChannel('com.aerofiles.app/storage');

  final StreamController<int> _progressController = StreamController<int>.broadcast();
  Stream<int> get onProgress => _progressController.stream;

  void Function(int progress)? _activeProgressCallback;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onVideoProcessProgress') {
      final args = call.arguments as Map?;
      final progress = args?['progress'] as int? ?? 0;
      _progressController.add(progress);
      _activeProgressCallback?.call(progress);
    }
  }

  Future<VideoMetadata?> getVideoMetadata(String path) async {
    _ensureChannelInitialized();
    try {
      final result = await _channel.invokeMethod<Map>('getVideoMetadata', {'path': path});
      if (result == null) return null;

      final durationMs = (result['durationMs'] as num?)?.toInt() ?? 0;
      final width = (result['width'] as num?)?.toInt() ?? 0;
      final height = (result['height'] as num?)?.toInt() ?? 0;
      final rotation = (result['rotation'] as num?)?.toInt() ?? 0;
      final sizeBytes = (result['sizeBytes'] as num?)?.toInt() ?? 0;

      return VideoMetadata(
        duration: Duration(milliseconds: durationMs),
        width: width,
        height: height,
        rotation: rotation,
        sizeBytes: sizeBytes,
      );
    } catch (e) {
      LogService.instance.error('VIDEO_EDITOR', 'Failed to get video metadata for $path: $e');
      return null;
    }
  }

  String generateTrimmedOutputPath(String originalPath) {
    final dir = p.dirname(originalPath);
    final baseName = p.basenameWithoutExtension(originalPath);
    final ext = p.extension(originalPath);
    final dateSuffix = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return p.join(dir, '${baseName}_trimmed_$dateSuffix$ext');
  }

  String generateMergedOutputPath(String directoryPath, {String prefix = 'merged_video'}) {
    final dateSuffix = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return p.join(directoryPath, '${prefix}_$dateSuffix.mp4');
  }

  Future<String> trimVideo({
    required String inputPath,
    required Duration startTime,
    required Duration endTime,
    required VideoSaveOption saveOption,
    void Function(int progress)? onProgressUpdated,
  }) async {
    _ensureChannelInitialized();
    _activeProgressCallback = onProgressUpdated;
    try {
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        throw Exception('Source video file does not exist');
      }

      final startMs = startTime.inMilliseconds;
      final endMs = endTime.inMilliseconds;
      if (endMs <= startMs) {
        throw Exception('End time must be greater than start time');
      }

      String targetOutputPath;
      String renderingOutputPath;
      final isReplacing = saveOption == VideoSaveOption.replaceOriginal;

      if (isReplacing) {
        final parentDir = p.dirname(inputPath);
        final dateSuffix = DateFormat('yyyyMMdd_HHmmss_SSS').format(DateTime.now());
        renderingOutputPath = p.join(parentDir, '.aerofiles_trim_tmp_$dateSuffix.mp4');
        targetOutputPath = inputPath;
      } else {
        targetOutputPath = generateTrimmedOutputPath(inputPath);
        renderingOutputPath = targetOutputPath;
      }

      LogService.instance.info(
        'VIDEO_EDITOR',
        'Starting trim on $inputPath from $startMs ms to $endMs ms -> $renderingOutputPath',
      );

      final renderedPath = await _channel.invokeMethod<String>('trimVideo', {
        'inputPath': inputPath,
        'outputPath': renderingOutputPath,
        'startMs': startMs,
        'endMs': endMs,
      });

      if (renderedPath == null) {
        throw Exception('Native trim failed to produce an output file');
      }

      if (isReplacing) {
        final tempRenderedFile = File(renderedPath);
        if (await tempRenderedFile.exists()) {
          final originalFile = File(targetOutputPath);
          if (await originalFile.exists()) {
            await originalFile.delete();
          }
          try {
            await tempRenderedFile.rename(targetOutputPath);
          } catch (_) {
            await tempRenderedFile.copy(targetOutputPath);
            try {
              await tempRenderedFile.delete();
            } catch (_) {}
          }
        }
      }

      // Always update Android MediaStore so folders, gallery and media library update immediately
      try {
        await _storageChannel.invokeMethod('scanFile', {'path': targetOutputPath});
      } catch (_) {}

      LogService.instance.info('VIDEO_EDITOR', 'Trim successfully completed: $targetOutputPath');
      return targetOutputPath;
    } catch (e) {
      LogService.instance.error('VIDEO_EDITOR', 'Trim failed: $e');
      rethrow;
    } finally {
      _activeProgressCallback = null;
    }
  }

  Future<String> mergeVideos({
    required List<String> inputPaths,
    required VideoSaveOption saveOption,
    String? outputDirectory,
    void Function(int progress)? onProgressUpdated,
  }) async {
    _ensureChannelInitialized();
    _activeProgressCallback = onProgressUpdated;
    try {
      if (inputPaths.length < 2) {
        throw Exception('At least 2 videos are required to merge');
      }

      for (final path in inputPaths) {
        if (!await File(path).exists()) {
          throw Exception('Source video file does not exist: $path');
        }
      }

      final targetDir = outputDirectory ?? p.dirname(inputPaths.first);
      final isReplacing = saveOption == VideoSaveOption.replaceOriginal;

      String renderingOutputPath;
      String finalOutputPath;

      if (isReplacing) {
        final dateSuffix = DateFormat('yyyyMMdd_HHmmss_SSS').format(DateTime.now());
        renderingOutputPath = p.join(targetDir, '.aerofiles_merge_tmp_$dateSuffix.mp4');
        finalOutputPath = inputPaths.first;
      } else {
        finalOutputPath = generateMergedOutputPath(targetDir);
        renderingOutputPath = finalOutputPath;
      }

      LogService.instance.info(
        'VIDEO_EDITOR',
        'Starting merge of ${inputPaths.length} videos in exact order -> $renderingOutputPath',
      );

      final renderedPath = await _channel.invokeMethod<String>('mergeVideos', {
        'inputPaths': inputPaths,
        'outputPath': renderingOutputPath,
      });

      if (renderedPath == null) {
        throw Exception('Native merge failed to produce an output file');
      }

      if (isReplacing) {
        final tempRenderedFile = File(renderedPath);
        if (await tempRenderedFile.exists()) {
          // Replace first file with merged result
          final firstFile = File(finalOutputPath);
          if (await firstFile.exists()) {
            await firstFile.delete();
          }
          try {
            await tempRenderedFile.rename(finalOutputPath);
          } catch (_) {
            await tempRenderedFile.copy(finalOutputPath);
            try {
              await tempRenderedFile.delete();
            } catch (_) {}
          }

          // Remove subsequent merged source files according to recycle bin settings
          final settings = SettingsService.instance;
          final useRecycleBin = settings.deleteBehavior == DeleteBehavior.recycleBin;

          for (int i = 1; i < inputPaths.length; i++) {
            final subsequentPath = inputPaths[i];
            try {
              final subFile = File(subsequentPath);
              if (await subFile.exists()) {
                if (useRecycleBin) {
                  await RecycleBinService.instance.moveToTrash(subsequentPath);
                } else {
                  await subFile.delete();
                }
                await _storageChannel.invokeMethod('scanFile', {'path': subsequentPath});
              }
            } catch (e) {
              LogService.instance.warn('VIDEO_EDITOR', 'Failed to remove source file $subsequentPath: $e');
            }
          }

        }
      }

      // Always update Android MediaStore so folders, gallery and media library update immediately
      try {
        await _storageChannel.invokeMethod('scanFile', {'path': finalOutputPath});
      } catch (_) {}

      LogService.instance.info('VIDEO_EDITOR', 'Merge successfully completed: $finalOutputPath');
      return finalOutputPath;
    } catch (e) {
      LogService.instance.error('VIDEO_EDITOR', 'Merge failed: $e');
      rethrow;
    } finally {
      _activeProgressCallback = null;
    }
  }

  Future<void> cancel() async {
    _ensureChannelInitialized();
    try {
      await _channel.invokeMethod('cancelVideoProcess');
      LogService.instance.info('VIDEO_EDITOR', 'Cancelled video operation');
    } catch (e) {
      LogService.instance.error('VIDEO_EDITOR', 'Error cancelling video operation: $e');
    }
  }

  static String formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
