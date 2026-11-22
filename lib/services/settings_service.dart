import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/network_connection.dart';

enum DeleteBehavior {
  ask,
  recycleBin,
  permanent,
}

class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  late SharedPreferences _prefs;
  bool _initialized = false;

  ThemeMode _themeMode = ThemeMode.dark;
  DeleteBehavior _deleteBehavior = DeleteBehavior.ask;
  bool _showHiddenFiles = false;
  bool _autoEmptyTrash = true;
  final List<NetworkConnection> _savedConnections = [];

  ThemeMode get themeMode => _themeMode;
  DeleteBehavior get deleteBehavior => _deleteBehavior;
  bool get showHiddenFiles => _showHiddenFiles;
  bool get autoEmptyTrash => _autoEmptyTrash;
  List<NetworkConnection> get savedConnections => List.unmodifiable(_savedConnections);

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();

    final themeStr = _prefs.getString('theme_mode') ?? 'dark';
    if (themeStr == 'light') {
      _themeMode = ThemeMode.light;
    } else if (themeStr == 'system') {
      _themeMode = ThemeMode.system;
    } else {
      _themeMode = ThemeMode.dark;
    }

    final deleteStr = _prefs.getString('delete_behavior') ?? 'ask';
    if (deleteStr == 'recycleBin') {
      _deleteBehavior = DeleteBehavior.recycleBin;
    } else if (deleteStr == 'permanent') {
      _deleteBehavior = DeleteBehavior.permanent;
    } else {
      _deleteBehavior = DeleteBehavior.ask;
    }

    _showHiddenFiles = _prefs.getBool('show_hidden_files') ?? false;
    _autoEmptyTrash = _prefs.getBool('auto_empty_trash') ?? true;

    // Load saved network connections (Dual persistence: SharedPreferences + Persistent File Backup)
    _savedConnections.clear();
    final connJsonStr = _prefs.getString('saved_network_connections');
    if (connJsonStr != null && connJsonStr.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(connJsonStr);
        for (final item in list) {
          _savedConnections.add(NetworkConnection.fromJson(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    // Fallback: If SharedPreferences was reset during app update, restore from file backup
    if (_savedConnections.isEmpty || _savedConnections.every((c) => c.username.isEmpty && !c.isAnonymous)) {
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final backupFile = File('${docsDir.path}/network_connections_backup.json');
        if (await backupFile.exists()) {
          final content = await backupFile.readAsString();
          if (content.isNotEmpty) {
            final List<dynamic> list = jsonDecode(content);
            if (list.isNotEmpty) {
              _savedConnections.clear();
              for (final item in list) {
                _savedConnections.add(NetworkConnection.fromJson(item as Map<String, dynamic>));
              }
              // Resync to SharedPreferences
              await _prefs.setString('saved_network_connections', content);
            }
          }
        }
      } catch (_) {}
    }

    // Default connection if none saved yet
    if (_savedConnections.isEmpty) {
      _savedConnections.add(
        NetworkConnection(
          id: 'home_nas_smb',
          name: 'Home NAS (SMB)',
          protocol: ProtocolType.smb,
          host: '192.168.1.41',
          port: 445,
          username: '',
          password: '',
          path: '',
          isAnonymous: false,
          lastConnected: DateTime.now(),
        ),
      );
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> saveConnection(NetworkConnection conn) async {
    final idx = _savedConnections.indexWhere((c) => c.id == conn.id);
    if (idx != -1) {
      _savedConnections[idx] = conn;
    } else {
      _savedConnections.add(conn);
    }
    await _persistConnections();
    notifyListeners();
  }

  Future<void> removeConnection(String id) async {
    _savedConnections.removeWhere((c) => c.id == id);
    await _persistConnections();
    notifyListeners();
  }

  Future<void> _persistConnections() async {
    final list = _savedConnections.map((c) => c.toJson()).toList();
    final jsonStr = jsonEncode(list);
    await _prefs.setString('saved_network_connections', jsonStr);

    // Write to persistent file backup so credentials and connections survive updates
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final backupFile = File('${docsDir.path}/network_connections_backup.json');
      await backupFile.writeAsString(jsonStr, flush: true);
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    String val = 'dark';
    if (mode == ThemeMode.light) val = 'light';
    if (mode == ThemeMode.system) val = 'system';
    await _prefs.setString('theme_mode', val);
  }

  Future<void> setDeleteBehavior(DeleteBehavior behavior) async {
    _deleteBehavior = behavior;
    notifyListeners();
    String val = 'ask';
    if (behavior == DeleteBehavior.recycleBin) val = 'recycleBin';
    if (behavior == DeleteBehavior.permanent) val = 'permanent';
    await _prefs.setString('delete_behavior', val);
  }

  Future<void> setShowHiddenFiles(bool show) async {
    _showHiddenFiles = show;
    notifyListeners();
    await _prefs.setBool('show_hidden_files', show);
  }

  Future<void> setAutoEmptyTrash(bool autoEmpty) async {
    _autoEmptyTrash = autoEmpty;
    notifyListeners();
    await _prefs.setBool('auto_empty_trash', autoEmpty);
  }
}
