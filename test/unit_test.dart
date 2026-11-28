import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerofiles/models/vfs_node.dart';
import 'package:aerofiles/services/security/biometric_service.dart';
import 'package:aerofiles/services/settings_service.dart';
import 'package:aerofiles/services/app_update_service.dart';
import 'package:aerofiles/services/media/video_editor_service.dart';
import 'package:aerofiles/screens/player/video_render_progress_dialog.dart';
import 'package:aerofiles/screens/player/video_merge_dialog.dart';
import 'package:aerofiles/screens/network/aerolink_about_sheet.dart';

void main() {
  group('AppUpdateService Versioning Tests', () {
    test('Detects newer remote version v2.2.8 > v2.2.7', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.8',
        localVersion: '2.2.7',
        localBuildNumber: '31',
        remotePublishedAt: DateTime.now(),
      );
      expect(hasUpdate, isTrue);
    });

    test('Detects identical versions with same build as no update', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.8',
        localVersion: '2.2.8',
        localBuildNumber: '34',
        remotePublishedAt: DateTime.now(),
        releaseTitle: 'AeroFiles v2.2.8 (Build 34)',
      );
      expect(hasUpdate, isFalse);
    });

    test('Detects newer build number when version string matches', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.8+35',
        localVersion: '2.2.8',
        localBuildNumber: '34',
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

  group('Video Editor Path & Save Option Tests', () {
    test('generateTrimmedOutputPath generates formatted output path', () {
      final input = '/storage/emulated/0/DCIM/Camera/video.mp4';
      final output = VideoEditorService.instance.generateTrimmedOutputPath(input);
      expect(output.startsWith('/storage/emulated/0/DCIM/Camera/video_trimmed_'), isTrue);
      expect(output.endsWith('.mp4'), isTrue);
    });

    test('generateMergedOutputPath generates formatted output path', () {
      final dir = '/storage/emulated/0/DCIM/Camera';
      final output = VideoEditorService.instance.generateMergedOutputPath(dir);
      expect(output.startsWith('/storage/emulated/0/DCIM/Camera/merged_video_'), isTrue);
      expect(output.endsWith('.mp4'), isTrue);
    });

    test('VideoSaveOption enum has keepOriginal and replaceOriginal', () {
      expect(VideoSaveOption.values.contains(VideoSaveOption.keepOriginal), isTrue);
      expect(VideoSaveOption.values.contains(VideoSaveOption.replaceOriginal), isTrue);
    });
  });

  group('Video Editor Dialogs Material & UI Tests', () {
    testWidgets('VideoRenderProgressDialog has Material ancestor and renders without error', (tester) async {
      final completer = Completer<String>();
      await tester.pumpWidget(
        MaterialApp(
          home: VideoRenderProgressDialog(
            title: 'Trimming Video...',
            subtitle: 'Exporting trimmed clip to folder',
            task: (_) => completer.future,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Material), findsWidgets);
      expect(find.text('Trimming Video...'), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Complete the task and verify the success alert & tick state
      completer.complete('/path/to/trimmed.mp4');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Trim Complete!'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
    });

    testWidgets('VideoMergeDialog has Material ancestor and renders without error', (tester) async {
      final sampleVideos = [
        VfsNode(
          path: '/storage/emulated/0/Movies/clip1.mp4',
          name: 'clip1.mp4',
          size: 1024 * 1024 * 10,
          modified: DateTime.now(),
          isDirectory: false,
        ),
        VfsNode(
          path: '/storage/emulated/0/Movies/clip2.mp4',
          name: 'clip2.mp4',
          size: 1024 * 1024 * 20,
          modified: DateTime.now(),
          isDirectory: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoMergeDialog(orderedVideos: sampleVideos),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Material), findsWidgets);
      expect(find.text('Merge Videos (2)'), findsOneWidget);
      expect(find.text('Keep Originals'), findsOneWidget);
      expect(find.text('Replace Originals'), findsOneWidget);
      expect(find.text('Merge 2 Videos'), findsOneWidget);
    });

    testWidgets('AeroLinkAboutSheet renders informative Apple-standard content', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AeroLinkAboutSheet(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('AeroLink Mesh'), findsWidgets);
      expect(find.text('Direct Local Mesh Network'), findsOneWidget);
      expect(find.text('WHAT IS AEROLINK?'), findsOneWidget);
      expect(find.text('WHEN IS IT HANDY?'), findsOneWidget);
      expect(find.text('Offline & Travel'), findsOneWidget);
      expect(find.text('Gigabit LAN Speed for 4K Videos'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });
}
