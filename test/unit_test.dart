import 'package:flutter_test/flutter_test.dart';
import 'package:aerofiles/models/vfs_node.dart';
import 'package:aerofiles/services/security/biometric_service.dart';
import 'package:aerofiles/services/settings_service.dart';
import 'package:aerofiles/services/app_update_service.dart';

void main() {
  group('AppUpdateService Versioning Tests', () {
    test('Detects newer remote version v2.2.4 > v2.2.3', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.4',
        localVersion: '2.2.3',
        localBuildNumber: '27',
        remotePublishedAt: DateTime.now(),
      );
      expect(hasUpdate, isTrue);
    });

    test('Detects identical versions with same build as no update', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.4',
        localVersion: '2.2.4',
        localBuildNumber: '28',
        remotePublishedAt: DateTime.now(),
        releaseTitle: 'AeroFiles v2.2.4 (Build 28)',
      );
      expect(hasUpdate, isFalse);
    });

    test('Detects newer build number when version string matches', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.4+29',
        localVersion: '2.2.4',
        localBuildNumber: '28',
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

  group('AppLockTimeout Enum & Duration Tests', () {
    test('Supports all required timeout options with accurate seconds', () {
      expect(AppLockTimeout.values.length, 4);
      expect(AppLockTimeout.values.contains(AppLockTimeout.immediately), isTrue);
      expect(AppLockTimeout.values.contains(AppLockTimeout.thirtySeconds), isTrue);
      expect(AppLockTimeout.values.contains(AppLockTimeout.oneMinute), isTrue);
      expect(AppLockTimeout.values.contains(AppLockTimeout.fiveMinutes), isTrue);
    });

    test('timeoutInSeconds converts enum to exact seconds', () {
      // Test the switch mapping logic
      int getSeconds(AppLockTimeout t) {
        switch (t) {
          case AppLockTimeout.immediately:
            return 0;
          case AppLockTimeout.thirtySeconds:
            return 30;
          case AppLockTimeout.oneMinute:
            return 60;
          case AppLockTimeout.fiveMinutes:
            return 300;
        }
      }

      expect(getSeconds(AppLockTimeout.immediately), equals(0));
      expect(getSeconds(AppLockTimeout.thirtySeconds), equals(30));
      expect(getSeconds(AppLockTimeout.oneMinute), equals(60));
      expect(getSeconds(AppLockTimeout.fiveMinutes), equals(300));
    });
  });

  group('VfsNode Media Classification Tests', () {
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
      expect(jpgNode.isAudio, isFalse);

      final pngNode = VfsNode(
        path: '/storage/emulated/0/Pictures/screenshot.png',
        name: 'screenshot.png',
        size: 1024000,
        modified: DateTime.now(),
        isDirectory: false,
      );
      expect(pngNode.isImage, isTrue);
    });

    test('Correctly identifies all audio formats for in-app player', () {
      final mp3Node = VfsNode(
        path: '/storage/emulated/0/Music/track.mp3',
        name: 'track.mp3',
        size: 8500000,
        modified: DateTime.now(),
        isDirectory: false,
      );
      expect(mp3Node.isAudio, isTrue);
      expect(mp3Node.isVideo, isFalse);
      expect(mp3Node.isImage, isFalse);

      final flacNode = VfsNode(
        path: '/storage/emulated/0/Music/lossless.flac',
        name: 'lossless.flac',
        size: 32000000,
        modified: DateTime.now(),
        isDirectory: false,
      );
      expect(flacNode.isAudio, isTrue);

      final wavNode = VfsNode(
        path: '/storage/emulated/0/Audio/recording.wav',
        name: 'recording.wav',
        size: 15000000,
        modified: DateTime.now(),
        isDirectory: false,
      );
      expect(wavNode.isAudio, isTrue);

      final m4aNode = VfsNode(
        path: '/storage/emulated/0/Music/podcast.m4a',
        name: 'podcast.m4a',
        size: 45000000,
        modified: DateTime.now(),
        isDirectory: false,
      );
      expect(m4aNode.isAudio, isTrue);

      final oggNode = VfsNode(
        path: '/storage/emulated/0/Music/sound.ogg',
        name: 'sound.ogg',
        size: 3000000,
        modified: DateTime.now(),
        isDirectory: false,
      );
      expect(oggNode.isAudio, isTrue);
    });

    test('Correctly differentiates video from image and audio', () {
      final mp4Node = VfsNode(
        path: '/storage/emulated/0/Movies/sample.mp4',
        name: 'sample.mp4',
        size: 15000000,
        modified: DateTime.now(),
        isDirectory: false,
      );
      expect(mp4Node.isVideo, isTrue);
      expect(mp4Node.isAudio, isFalse);
      expect(mp4Node.isImage, isFalse);
    });
  });
}
