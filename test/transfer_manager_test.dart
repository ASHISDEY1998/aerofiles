import 'package:aerofiles/models/network_connection.dart';
import 'package:aerofiles/services/transfer_manager_service.dart';
import 'package:aerofiles/services/vfs/smb_vfs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransferTask Model Tests', () {
    test('Calculates progress and formats sizes accurately', () {
      final task = TransferTask(
        id: '1',
        name: 'test_video.mp4',
        sourcePath: '/local/test_video.mp4',
        destPath: 'share/Movies/test_video.mp4',
        totalBytes: 104857600, // 100 MB
        transferredBytes: 52428800, // 50 MB
        isMove: true,
        status: TransferStatus.transferring,
        speedBytesPerSec: 10485760, // 10 MB/s
      );

      expect(task.progress, closeTo(0.5, 0.001));
      expect(task.formattedTotalSize, '100.0 MB');
      expect(task.formattedTransferred, '50.0 MB');
      expect(task.formattedSpeed, '10.0 MB/s');
    });

    test('Completed task reports progress 1.0', () {
      final task = TransferTask(
        id: '2',
        name: 'doc.pdf',
        sourcePath: '/local/doc.pdf',
        destPath: 'share/doc.pdf',
        totalBytes: 500,
        transferredBytes: 500,
        isMove: false,
        status: TransferStatus.completed,
      );

      expect(task.progress, 1.0);
      expect(task.formattedTotalSize, '500 B');
    });

    test('Zero byte file handled gracefully without division by zero', () {
      final task = TransferTask(
        id: '3',
        name: 'empty.txt',
        sourcePath: '/local/empty.txt',
        destPath: 'share/empty.txt',
        totalBytes: 0,
        isMove: false,
      );

      expect(task.progress, 0.0);
      expect(task.formattedTotalSize, '0 B');
    });
  });

  group('TransferManagerService Queue and Cancellation Tests', () {
    test('CancelAll cancels all pending tasks', () {
      final mgr = TransferManagerService.instance;
      final t1 = TransferTask(
        id: 't1',
        name: 'file1.mp4',
        sourcePath: '/a/file1.mp4',
        destPath: 'b/file1.mp4',
        totalBytes: 1000,
        isMove: true,
        status: TransferStatus.pending,
      );
      final t2 = TransferTask(
        id: 't2',
        name: 'file2.mp4',
        sourcePath: '/a/file2.mp4',
        destPath: 'b/file2.mp4',
        totalBytes: 2000,
        isMove: true,
        status: TransferStatus.pending,
      );

      mgr.tasks.value = [t1, t2];
      mgr.isTransferring.value = true;

      mgr.cancelAll();

      expect(mgr.tasks.value.every((t) => t.status == TransferStatus.canceled), isTrue);
      expect(mgr.isTransferring.value, isFalse);
    });

    test('ClearFinished removes non-active tasks', () {
      final mgr = TransferManagerService.instance;
      final t1 = TransferTask(
        id: 'c1',
        name: 'done.mp4',
        sourcePath: '/a/done.mp4',
        destPath: 'b/done.mp4',
        totalBytes: 1000,
        isMove: false,
        status: TransferStatus.completed,
      );
      final t2 = TransferTask(
        id: 'c2',
        name: 'active.mp4',
        sourcePath: '/a/active.mp4',
        destPath: 'b/active.mp4',
        totalBytes: 2000,
        isMove: false,
        status: TransferStatus.transferring,
      );

      mgr.tasks.value = [t1, t2];
      mgr.clearFinished();

      expect(mgr.tasks.value.length, 1);
      expect(mgr.tasks.value.first.id, 'c2');
    });
  });

  group('SmbVfs Path Resolution Tests', () {
    test('Resolves share and subpath without duplicating default share', () {
      final conn = NetworkConnection(
        id: 'nas_1',
        name: 'Home NAS',
        protocol: ProtocolType.smb,
        host: '192.168.1.50',
        port: 445,
        path: '/public',
        lastConnected: DateTime.now(),
      );

      final smb = SmbVfs(conn);

      // When browsing inside 'public/Movies/video.mp4'
      final (share1, sub1) = smb.resolveShareAndSub('public/Movies/video.mp4');
      expect(share1, 'public');
      expect(sub1, 'Movies/video.mp4');

      // When browsing with leading slash '/public/Movies/video.mp4'
      final (share2, sub2) = smb.resolveShareAndSub('/public/Movies/video.mp4');
      expect(share2, 'public');
      expect(sub2, 'Movies/video.mp4');

      // When path is just 'Movies/video.mp4'
      final (share3, sub3) = smb.resolveShareAndSub('Movies/video.mp4');
      expect(share3, 'public');
      expect(sub3, 'Movies/video.mp4');
    });

    test('Resolves share and subpath when connection has no default share', () {
      final conn = NetworkConnection(
        id: 'nas_2',
        name: 'Root NAS',
        protocol: ProtocolType.smb,
        host: '192.168.1.50',
        port: 445,
        path: '',
        lastConnected: DateTime.now(),
      );

      final smb = SmbVfs(conn);

      final (share, sub) = smb.resolveShareAndSub('shared/Videos/clip.mp4');
      expect(share, 'shared');
      expect(sub, 'Videos/clip.mp4');
    });
  });
}
