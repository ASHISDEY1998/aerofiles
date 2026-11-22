import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recycle_bin_service.dart';

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String tag;
  final String message;
  final String? error;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
  });

  @override
  String toString() {
    final timeStr = timestamp.toIso8601String().substring(0, 19).replaceAll('T', ' ');
    final errStr = error != null ? '\n  Error: $error' : '';
    return '[$timeStr] [$level] [$tag] $message$errStr';
  }
}

class LogService extends ChangeNotifier {
  static final LogService instance = LogService._();
  LogService._();

  static const String _prefKey = 'diagnostics_logging_enabled';
  bool _isLoggingEnabled = false;
  File? _logFile;
  final List<LogEntry> _recentEntries = [];
  int _entryCount = 0;

  bool get isLoggingEnabled => _isLoggingEnabled;
  int get entryCount => _entryCount;
  List<LogEntry> get recentEntries => List.unmodifiable(_recentEntries);

  int get logSizeBytes {
    try {
      if (_logFile != null && _logFile!.existsSync()) {
        return _logFile!.lengthSync();
      }
    } catch (_) {}
    return 0;
  }

  String get logSizeText {
    final bytes = logSizeBytes;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isLoggingEnabled = prefs.getBool(_prefKey) ?? false;

      final docsDir = await getApplicationDocumentsDirectory();
      _logFile = File(p.join(docsDir.path, 'aerofiles_debug.log'));

      if (_logFile!.existsSync()) {
        final lines = await _logFile!.readAsLines();
        _entryCount = lines.length;
      }

      if (_isLoggingEnabled) {
        info('APP', 'Logging service initialized (Session start)');
      }
    } catch (e) {
      debugPrint('LogService init error: $e');
    }
  }

  Future<void> setLoggingEnabled(bool enabled) async {
    _isLoggingEnabled = enabled;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, enabled);

      if (enabled) {
        info('APP', 'Diagnostics logging ENABLED by user');
      } else {
        info('APP', 'Diagnostics logging DISABLED by user');
      }
    } catch (_) {}
  }

  void info(String tag, String message) {
    log(tag, message, level: 'INFO');
  }

  void warn(String tag, String message) {
    log(tag, message, level: 'WARN');
  }

  void error(String tag, String message, [dynamic error, StackTrace? stackTrace]) {
    String? errDetails;
    if (error != null) {
      errDetails = error.toString();
      if (stackTrace != null) {
        errDetails += '\nStackTrace:\n$stackTrace';
      }
    }
    log(tag, message, level: 'ERROR', error: errDetails);
  }

  void log(String tag, String message, {String level = 'INFO', String? error}) {
    if (!_isLoggingEnabled) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error,
    );

    _recentEntries.add(entry);
    if (_recentEntries.length > 500) {
      _recentEntries.removeAt(0);
    }
    _entryCount++;
    notifyListeners();

    // Asynchronously write to file
    _appendToFile(entry.toString());
  }

  Future<void> _appendToFile(String line) async {
    try {
      if (_logFile != null) {
        await _logFile!.writeAsString('$line\n', mode: FileMode.append, flush: false);
      }
    } catch (_) {}
  }

  Future<String> getLogContent() async {
    final buffer = StringBuffer();
    buffer.writeln('==============================================');
    buffer.writeln('AeroFiles Diagnostic & System Log');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('Total Log Entries: $_entryCount');
    buffer.writeln('==============================================\n');

    try {
      if (_logFile != null && await _logFile!.exists()) {
        final content = await _logFile!.readAsString();
        buffer.write(content);
      } else {
        for (final entry in _recentEntries) {
          buffer.writeln(entry.toString());
        }
      }
    } catch (e) {
      buffer.writeln('Error reading log file: $e');
    }

    return buffer.toString();
  }

  Future<String?> uploadLogCloud() async {
    final content = await getLogContent();
    if (content.trim().isEmpty) return null;

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(Uri.parse('https://dpaste.org/api/'));
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');

      final body = 'content=${Uri.encodeQueryComponent(content)}'
          '&title=${Uri.encodeQueryComponent('AeroFiles Log - ${DateTime.now().toString().substring(0, 16)}')}'
          '&expiry_days=30';

      req.write(body);
      final res = await req.close();
      if (res.statusCode == 200) {
        final result = await res.transform(utf8.decoder).join();
        return result.replaceAll('"', '').trim();
      }
      return null;
    } catch (e) {
      debugPrint('Log upload failed: $e');
      return null;
    } finally {
      client?.close();
    }
  }

  Future<String?> saveLogToDownloads() async {
    try {
      final content = await getLogContent();
      const extDir = '/storage/emulated/0/Download';
      final downloadDir = Directory(extDir);

      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final dateStamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final targetFile = File('$extDir/aerofiles_debug_$dateStamp.txt');
      await targetFile.writeAsString(content, flush: true);

      // Notify Android MediaScanner so user sees it instantly
      await RecycleBinService.notifyMediaScanner(targetFile.path);
      return targetFile.path;
    } catch (e) {
      debugPrint('Failed to save log to downloads: $e');
      return null;
    }
  }

  Future<void> clearLogs() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.delete();
      }
      _recentEntries.clear();
      _entryCount = 0;
      notifyListeners();
    } catch (_) {}
  }
}
