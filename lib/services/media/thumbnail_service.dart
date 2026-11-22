import 'package:flutter/services.dart';

class ThumbnailService {
  static final ThumbnailService instance = ThumbnailService._();
  ThumbnailService._();

  static const _channel = MethodChannel('com.aerofiles.app/storage');
  final Map<String, Uint8List?> _cache = {};
  final List<String> _keys = [];
  static const int _maxCacheSize = 250;

  Future<Uint8List?> getVideoThumbnail(String path) async {
    if (_cache.containsKey(path)) {
      return _cache[path];
    }

    try {
      final dynamic result = await _channel
          .invokeMethod('getVideoThumbnail', {'path': path})
          .timeout(const Duration(milliseconds: 1800), onTimeout: () => null);
      final Uint8List? bytes = result is Uint8List ? result : null;

      if (_keys.length >= _maxCacheSize) {
        final oldest = _keys.removeAt(0);
        _cache.remove(oldest);
      }

      _cache[path] = bytes;
      _keys.add(path);
      return bytes;
    } catch (_) {
      _cache[path] = null;
      return null;
    }
  }

  void clear() {
    _cache.clear();
    _keys.clear();
  }
}
