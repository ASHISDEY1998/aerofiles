import 'package:flutter/services.dart';

class ThumbnailService {
  static final ThumbnailService instance = ThumbnailService._();
  ThumbnailService._();

  static const _channel = MethodChannel('com.aerofiles.app/storage');

  // L1 In-Memory LRU Cache (compact 100-entry limit to prevent memory bloat)
  final Map<String, Uint8List?> _l1Cache = {};
  final List<String> _l1Keys = [];
  static const int _maxL1CacheSize = 100;

  // In-flight deduplication so concurrent widgets never duplicate decode requests
  final Map<String, Future<Uint8List?>> _inFlight = {};

  Future<Uint8List?> getVideoThumbnail(String path) async {
    // 1. Fast L1 In-Memory Cache Hit
    if (_l1Cache.containsKey(path)) {
      return _l1Cache[path];
    }

    // 2. Request Deduplication: Reuse ongoing fetch if already in flight
    if (_inFlight.containsKey(path)) {
      return _inFlight[path]!;
    }

    final future = _fetchThumbnail(path);
    _inFlight[path] = future;
    return future;
  }

  Future<Uint8List?> _fetchThumbnail(String path) async {
    try {
      // 3. Platform Channel fetches from L2 Persistent Disk Cache or decodes
      final dynamic result = await _channel
          .invokeMethod('getVideoThumbnail', {'path': path})
          .timeout(const Duration(milliseconds: 4000), onTimeout: () => null);

      final Uint8List? bytes = result is Uint8List ? result : null;

      // 4. Populate L1 Cache with LRU eviction
      if (_l1Keys.length >= _maxL1CacheSize) {
        final oldest = _l1Keys.removeAt(0);
        _l1Cache.remove(oldest);
      }
      _l1Cache[path] = bytes;
      _l1Keys.add(path);

      return bytes;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(path);
    }
  }

  /// Clears in-memory L1 cache.
  void clear() {
    _l1Cache.clear();
    _l1Keys.clear();
    _inFlight.clear();
  }

  /// Evicts a specific path from in-memory cache so a fresh thumbnail is generated
  void evict(String path) {
    _l1Cache.remove(path);
    _l1Keys.remove(path);
    _inFlight.remove(path);
  }

  /// Clears both in-memory L1 and persistent L2 disk cache.
  Future<void> clearAll() async {
    clear();
    try {
      await _channel.invokeMethod('clearThumbnailCache');
    } catch (_) {}
  }
}
