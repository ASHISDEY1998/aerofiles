import 'package:aerofiles/models/vfs_node.dart';
import 'package:aerofiles/services/media/video_editor_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoEditorService Unit Tests', () {
    test('formatDuration formats hours, minutes, seconds correctly', () {
      expect(VideoEditorService.formatDuration(const Duration(seconds: 45)), '00:45');
      expect(VideoEditorService.formatDuration(const Duration(minutes: 3, seconds: 12)), '03:12');
      expect(VideoEditorService.formatDuration(const Duration(hours: 1, minutes: 24, seconds: 5)), '01:24:05');
      expect(VideoEditorService.formatDuration(Duration.zero), '00:00');
    });

    test('generateTrimmedOutputPath preserves extension and appends timestamp', () {
      final input = '/storage/emulated/0/DCIM/Camera/VID_20261125.mp4';
      final output = VideoEditorService.instance.generateTrimmedOutputPath(input);

      expect(output.startsWith('/storage/emulated/0/DCIM/Camera/VID_20261125_trimmed_'), isTrue);
      expect(output.endsWith('.mp4'), isTrue);
    });

    test('generateMergedOutputPath creates clean file path in target directory', () {
      final dir = '/storage/emulated/0/Movies';
      final output = VideoEditorService.instance.generateMergedOutputPath(dir);

      expect(output.startsWith('/storage/emulated/0/Movies/merged_video_'), isTrue);
      expect(output.endsWith('.mp4'), isTrue);
    });

    test('VideoMetadata calculates isPortrait and aspectRatio accurately', () {
      const landscape = VideoMetadata(
        duration: Duration(minutes: 2),
        width: 1920,
        height: 1080,
        rotation: 0,
        sizeBytes: 10485760,
      );
      expect(landscape.isPortrait, isFalse);
      expect(landscape.aspectRatio, closeTo(16 / 9, 0.01));

      const portrait = VideoMetadata(
        duration: Duration(seconds: 45),
        width: 1080,
        height: 1920,
        rotation: 0,
        sizeBytes: 5242880,
      );
      expect(portrait.isPortrait, isTrue);
      expect(portrait.aspectRatio, closeTo(9 / 16, 0.01));

      const rotatedLandscape = VideoMetadata(
        duration: Duration(seconds: 30),
        width: 1920,
        height: 1080,
        rotation: 90,
        sizeBytes: 4000000,
      );
      expect(rotatedLandscape.isPortrait, isTrue);
      expect(rotatedLandscape.aspectRatio, closeTo(1080 / 1920, 0.01));
    });

    test('Selection order is strictly preserved regardless of directory sort', () {
      final nodeA = VfsNode(
        path: '/storage/emulated/0/Movies/clip_a.mp4',
        name: 'clip_a.mp4',
        isDirectory: false,
        size: 1000,
        modified: DateTime(2026, 1, 1),
      );
      final nodeB = VfsNode(
        path: '/storage/emulated/0/Movies/clip_b.mp4',
        name: 'clip_b.mp4',
        isDirectory: false,
        size: 2000,
        modified: DateTime(2026, 1, 2),
      );
      final nodeC = VfsNode(
        path: '/storage/emulated/0/Movies/clip_c.mp4',
        name: 'clip_c.mp4',
        isDirectory: false,
        size: 3000,
        modified: DateTime(2026, 1, 3),
      );

      final allItems = [nodeA, nodeB, nodeC];

      // User selects node C, then node A, then node B
      final selectedPaths = <String>{};
      selectedPaths.add(nodeC.path);
      selectedPaths.add(nodeA.path);
      selectedPaths.add(nodeB.path);

      final itemMap = {for (final e in allItems) e.path: e};
      final orderedSelection = <VfsNode>[];
      for (final p in selectedPaths) {
        final node = itemMap[p];
        if (node != null) orderedSelection.add(node);
      }

      expect(orderedSelection.length, 3);
      expect(orderedSelection[0].name, 'clip_c.mp4');
      expect(orderedSelection[1].name, 'clip_a.mp4');
      expect(orderedSelection[2].name, 'clip_b.mp4');
    });
  });
}
