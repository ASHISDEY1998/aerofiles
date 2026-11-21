import '../../models/vfs_node.dart';

abstract class VfsProvider {
  String get providerId;
  String get displayName;
  String get rootPath;

  Future<List<VfsNode>> listDirectory(String path);
  Future<VfsNode?> getMetadata(String path);
  Future<bool> createDirectory(String parentPath, String dirName);
  Future<bool> rename(String path, String newName);
  Future<bool> delete(String path, {bool moveToTrash = true});
  Future<bool> copy(String sourcePath, String destPath, {void Function(double)? onProgress});
  Future<bool> move(String sourcePath, String destPath, {void Function(double)? onProgress});
  
  /// Returns a path or streaming URL suitable for media_kit / libmpv hardware playback
  Future<String> getPlaybackUri(String path);
}
