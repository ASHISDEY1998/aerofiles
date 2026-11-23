import 'package:flutter_test/flutter_test.dart';
import 'package:aerofiles/models/vfs_node.dart';

void main() {
  group('VfsNode Tests', () {
    test('Correctly categorizes video extensions and mimeTypes', () {
      final mp4Node = VfsNode(
        path: '/storage/emulated/0/Download/movie.mp4',
        name: 'movie.mp4',
        size: 1048576,
        isDirectory: false,
        modified: DateTime.now(),
      );
      expect(mp4Node.category, FileCategory.video);
      expect(mp4Node.isVideo, isTrue);
      expect(mp4Node.isImage, isFalse);

      final mkvNode = VfsNode(
        path: '/storage/emulated/0/Movies/clip.mkv',
        name: 'clip.mkv',
        size: 2097152,
        isDirectory: false,
        modified: DateTime.now(),
      );
      expect(mkvNode.category, FileCategory.video);
      expect(mkvNode.isVideo, isTrue);
    });

    test('Correctly categorizes images and documents', () {
      final imgNode = VfsNode(
        path: '/storage/emulated/0/DCIM/photo.jpg',
        name: 'photo.jpg',
        size: 524288,
        isDirectory: false,
        modified: DateTime.now(),
      );
      expect(imgNode.category, FileCategory.image);
      expect(imgNode.isImage, isTrue);

      final pdfNode = VfsNode(
        path: '/storage/emulated/0/Documents/report.pdf',
        name: 'report.pdf',
        size: 102400,
        isDirectory: false,
        modified: DateTime.now(),
      );
      expect(pdfNode.category, FileCategory.document);
    });

    test('Formatted size displays human readable units', () {
      final small = VfsNode(
        path: '/a.txt',
        name: 'a.txt',
        size: 512,
        isDirectory: false,
        modified: DateTime.now(),
      );
      expect(small.formattedSize, '512 B');

      final megabyte = VfsNode(
        path: '/b.bin',
        name: 'b.bin',
        size: 5 * 1024 * 1024,
        isDirectory: false,
        modified: DateTime.now(),
      );
      expect(megabyte.formattedSize, '5.0 MB');
    });
  });
}
