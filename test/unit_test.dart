import 'package:flutter_test/flutter_test.dart';
import 'package:aerofiles/models/vfs_node.dart';
import 'package:aerofiles/services/settings_service.dart';
import 'package:aerofiles/services/app_update_service.dart';

void main() {
  group('AppUpdateService Versioning Tests', () {
    test('Detects newer remote version v2.2.3 > v2.2.2', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.3',
        localVersion: '2.2.2',
        localBuildNumber: '26',
        remotePublishedAt: DateTime.now(),
      );
      expect(hasUpdate, isTrue);
    });

    test('Detects identical versions with same build as no update', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.3',
        localVersion: '2.2.3',
        localBuildNumber: '27',
        remotePublishedAt: DateTime.now(),
        releaseTitle: 'AeroFiles v2.2.3 (Build 27)',
      );
      expect(hasUpdate, isFalse);
    });

    test('Detects newer build number when version string matches', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.3+28',
        localVersion: '2.2.3',
        localBuildNumber: '27',
        remotePublishedAt: DateTime.now(),
      );
      expect(hasUpdate, isTrue);
    });
  });

  group('DeleteBehavior Enum Tests', () {
    test('Supports all three Apple-standard deletion behaviors', () {
      expect(DeleteBehavior.values.length, 3);
      expect(DeleteBehavior.values.contains(DeleteBehavior.ask), isTrue);
      expect(DeleteBehavior.values.contains(DeleteBehavior.recycleBin), isTrue);
      expect(DeleteBehavior.values.contains(DeleteBehavior.permanent), isTrue);
    });
  });

  group('VfsNode Image Classification Tests', () {
    test('Correctly identifies standard image extensions', () {
      final jpgNode = VfsNode(
        path: '/storage/emulated/0/DCIM/Camera/IMG_20261125_001.jpg',
        name: 'IMG_20261125_001.jpg',
        size: 2048000,
        modified: DateTime.now(),
        isDirectory: false,
      );
      expect(jpgNode.isImage, isTrue);
      expect(jpgNode.isVideo, isFalse);

      final pngNode = VfsNode(
        path: '/storage/emulated/0/Pictures/screenshot.png',
        name: 'screenshot.png',
        size: 1024000,
        modified: DateTime.now(),
        isDirectory: false,
      );
      expect(pngNode.isImage, isTrue);

      final webpNode = VfsNode(
        path: '/storage/emulated/0/Download/image.webp',
        name: 'image.webp',
        size: 512000,
        modified: DateTime.now(),
        isDirectory: false,
      );
      expect(webpNode.isImage, isTrue);
    });

    test('Correctly differentiates video from image', () {
      final mp4Node = VfsNode(
        path: '/storage/emulated/0/Movies/sample.mp4',
        name: 'sample.mp4',
        size: 15000000,
        modified: DateTime.now(),
        isDirectory: false,
      );
      expect(mp4Node.isImage, isFalse);
      expect(mp4Node.isVideo, isTrue);
    });
  });
}
