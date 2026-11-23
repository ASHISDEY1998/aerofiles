import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlaybackHistoryService {
  static final PlaybackHistoryService instance = PlaybackHistoryService._();
  PlaybackHistoryService._();

  static const String _keyPrefix = 'vpos_';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  String _sanitizeKey(String path) {
    return '$_keyPrefix${path.hashCode.toRadixString(16)}';
  }

  /// Saves the current playback position for a media path.
  Future<void> savePosition(String path, Duration position, Duration totalDuration) async {
    try {
      final posSec = position.inSeconds;
      final totalSec = totalDuration.inSeconds;
      final prefs = await _getPrefs();
      final key = _sanitizeKey(path);

      // If video is finished (>95% or within 15s of end) or barely started (<10s), clear position
      if (posSec < 10 || (totalSec > 0 && posSec >= totalSec - 15)) {
        await prefs.remove(key);
        return;
      }

      final data = jsonEncode({
        'path': path,
        'position': posSec,
        'total': totalSec,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      await prefs.setString(key, data);
    } catch (e) {
      debugPrint('PlaybackHistoryService savePosition error: $e');
    }
  }

  /// Retrieves the saved position in seconds for a media path, or 0 if none exists.
  Future<int> getSavedPosition(String path) async {
    try {
      final prefs = await _getPrefs();
      final key = _sanitizeKey(path);
      final raw = prefs.getString(key);
      if (raw == null) return 0;

      final map = jsonDecode(raw) as Map<String, dynamic>;
      final pos = map['position'] as int? ?? 0;
      return pos;
    } catch (_) {
      return 0;
    }
  }

  /// Clears the saved position for a media path.
  Future<void> clearPosition(String path) async {
    try {
      final prefs = await _getPrefs();
      final key = _sanitizeKey(path);
      await prefs.remove(key);
    } catch (_) {}
  }
}
