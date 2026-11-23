import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/vfs_node.dart';
import '../log_service.dart';
import '../vfs/local_vfs.dart';

class VaultItem {
  final String id;
  final String fileName;
  final String originalPath;
  final int size;
  final DateTime dateAdded;

  VaultItem({
    required this.id,
    required this.fileName,
    required this.originalPath,
    required this.size,
    required this.dateAdded,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'originalPath': originalPath,
        'size': size,
        'dateAdded': dateAdded.toIso8601String(),
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) => VaultItem(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        originalPath: json['originalPath'] as String,
        size: json['size'] as int,
        dateAdded: DateTime.parse(json['dateAdded'] as String),
      );

  bool get isVideo => [
        'mp4',
        'mkv',
        'avi',
        'mov',
        'flv',
        'webm',
        'wmv',
        'm4v',
        'ts',
        '3gp'
      ].contains(p.extension(fileName).toLowerCase().replaceAll('.', ''));

  bool get isImage => [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'bmp',
        'heic',
        'svg'
      ].contains(p.extension(fileName).toLowerCase().replaceAll('.', ''));

  bool get isAudio => [
        'mp3',
        'm4a',
        'aac',
        'wav',
        'flac',
        'ogg',
        'opus',
        'wma'
      ].contains(p.extension(fileName).toLowerCase().replaceAll('.', ''));

  bool get isDocument => [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'txt',
        'rtf',
        'csv'
      ].contains(p.extension(fileName).toLowerCase().replaceAll('.', ''));
}

class SafeVaultService {
  static final SafeVaultService instance = SafeVaultService._();
  SafeVaultService._();

  static const String _keyVaultEnabled = 'vault_is_enabled';
  static const String _keyVaultPinHash = 'vault_pin_hash';
  static const String _keyVaultSalt = 'vault_salt';
  static const String _keyVaultBiometrics = 'vault_biometrics_enabled';
  static const String _keyVaultKeyBackup = 'vault_key_backup';

  static const MethodChannel _storageChannel = MethodChannel('com.aerofiles.app/storage');

  final LocalAuthentication _auth = LocalAuthentication();
  SharedPreferences? _prefs;

  Uint8List? _unlockedKey;
  Directory? _vaultDir;
  final List<VaultItem> _items = [];

  bool get isUnlocked => _unlockedKey != null;
  bool get isVaultEnabled => _prefs?.getBool(_keyVaultEnabled) ?? false;
  bool get hasPin => (_prefs?.getString(_keyVaultPinHash) ?? '').isNotEmpty;
  bool get isBiometricsEnabled => _prefs?.getBool(_keyVaultBiometrics) ?? true;
  List<VaultItem> get items => List.unmodifiable(_items);

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _ensureVaultDir();
    await _loadMetadata();
  }

  Future<void> _ensureVaultDir() async {
    try {
      final extStorage = LocalVfs().rootPath;
      if (extStorage.isNotEmpty && await Directory(extStorage).exists()) {
        _vaultDir = Directory(p.join(extStorage, '.aerofiles_vault'));
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        _vaultDir = Directory(p.join(appDir.path, '.aerofiles_vault'));
      }

      if (!await _vaultDir!.exists()) {
        await _vaultDir!.create(recursive: true);
      }

      // Add .nomedia file so Android MediaScanner never indexes vault contents
      final nomedia = File(p.join(_vaultDir!.path, '.nomedia'));
      if (!await nomedia.exists()) {
        await nomedia.writeAsString('');
      }
    } catch (e) {
      LogService.instance.error('VAULT', 'Failed to ensure vault directory: $e');
    }
  }

  Future<void> _loadMetadata() async {
    if (_vaultDir == null) return;
    try {
      final metaFile = File(p.join(_vaultDir!.path, 'vault_index.json'));
      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        if (content.isNotEmpty) {
          final List list = jsonDecode(content) as List;
          _items.clear();
          for (final it in list) {
            _items.add(VaultItem.fromJson(Map<String, dynamic>.from(it as Map)));
          }
        }
      }
    } catch (e) {
      LogService.instance.error('VAULT', 'Failed to load vault metadata: $e');
    }
  }

  Future<void> _saveMetadata() async {
    if (_vaultDir == null) return;
    try {
      final metaFile = File(p.join(_vaultDir!.path, 'vault_index.json'));
      final encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
      await metaFile.writeAsString(encoded, flush: true);
    } catch (e) {
      LogService.instance.error('VAULT', 'Failed to save vault metadata: $e');
    }
  }

  Future<void> setVaultEnabled(bool enabled) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_keyVaultEnabled, enabled);
    if (!enabled) {
      lock();
    }
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_keyVaultBiometrics, enabled);
  }

  String _generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes);
  }

  Uint8List _deriveKey(String pin, String salt) {
    // 256-bit AES key derived from PIN + Salt
    final keyBytes = sha256.convert(utf8.encode('$pin::$salt::aerofiles_vault_v1')).bytes;
    return Uint8List.fromList(keyBytes);
  }

  Future<bool> setVaultPin(String pin) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final salt = _generateSalt();
      final hash = sha256.convert(utf8.encode('$pin::$salt::hash_verifier')).toString();

      final key = _deriveKey(pin, salt);
      final keyHex = base64UrlEncode(key);

      await _prefs!.setString(_keyVaultSalt, salt);
      await _prefs!.setString(_keyVaultPinHash, hash);
      await _prefs!.setString(_keyVaultKeyBackup, keyHex);
      await _prefs!.setBool(_keyVaultEnabled, true);

      _unlockedKey = key;
      LogService.instance.info('VAULT', 'New Safe Vault PIN configured successfully');
      return true;
    } catch (e) {
      LogService.instance.error('VAULT', 'Failed to set Vault PIN: $e');
      return false;
    }
  }

  bool verifyPin(String pin) {
    _prefs ??= null;
    final salt = _prefs?.getString(_keyVaultSalt) ?? '';
    final storedHash = _prefs?.getString(_keyVaultPinHash) ?? '';
    if (salt.isEmpty || storedHash.isEmpty) return false;

    final computed = sha256.convert(utf8.encode('$pin::$salt::hash_verifier')).toString();
    if (computed == storedHash) {
      _unlockedKey = _deriveKey(pin, salt);
      return true;
    }
    return false;
  }

  Future<bool> authenticateBiometrics() async {
    if (!isBiometricsEnabled) return false;
    try {
      final canAuth = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canAuth) return false;

      final success = await _auth.authenticate(
        localizedReason: 'Authenticate with fingerprint to unlock Safe Vault',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (success) {
        final keyHex = _prefs?.getString(_keyVaultKeyBackup) ?? '';
        if (keyHex.isNotEmpty) {
          _unlockedKey = base64Url.decode(keyHex);
          return true;
        }
      }
      return false;
    } catch (e) {
      LogService.instance.warn('VAULT', 'Biometric auth failed: $e');
      return false;
    }
  }

  void lock() {
    _unlockedKey = null;
    clearPreviewCache();
  }

  // --- Encryption / Decryption ---

  Future<void> _encryptFile(File source, File dest, Uint8List key) async {
    final iv = Uint8List(16);
    final rng = Random.secure();
    for (int i = 0; i < 16; i++) {
      iv[i] = rng.nextInt(256);
    }

    final cipher = StreamCipher('AES/CTR')
      ..init(true, ParametersWithIV(KeyParameter(key), iv));

    final out = dest.openWrite();
    out.add(iv); // prepend 16-byte random IV

    final inStream = source.openRead();
    await for (final chunk in inStream) {
      final enc = cipher.process(Uint8List.fromList(chunk));
      out.add(enc);
    }
    await out.flush();
    await out.close();
  }

  Future<void> _decryptFile(File source, File dest, Uint8List key) async {
    final inStream = source.openRead();
    Uint8List? iv;
    StreamCipher? cipher;
    final out = dest.openWrite();

    await for (final chunk in inStream) {
      var data = Uint8List.fromList(chunk);
      if (iv == null) {
        if (data.length < 16) continue;
        iv = data.sublist(0, 16);
        cipher = StreamCipher('AES/CTR')
          ..init(false, ParametersWithIV(KeyParameter(key), iv));
        data = data.sublist(16);
      }
      if (data.isNotEmpty && cipher != null) {
        final dec = cipher.process(data);
        out.add(dec);
      }
    }
    await out.flush();
    await out.close();
  }

  // --- Vault File Operations ---

  Future<bool> moveToVault(List<VfsNode> nodes) async {
    if (!isUnlocked || _unlockedKey == null || _vaultDir == null) return false;

    bool allOk = true;
    for (final node in nodes) {
      if (node.isDirectory) continue; // files only
      final srcFile = File(node.path);
      if (!await srcFile.exists()) continue;

      try {
        final id = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
        final encFile = File(p.join(_vaultDir!.path, '$id.aef'));

        await _encryptFile(srcFile, encFile, _unlockedKey!);

        // Securely delete original
        await srcFile.delete();

        // Trigger MediaScanner so gallery removes the file immediately
        try {
          if (Platform.isAndroid) {
            await _storageChannel.invokeMethod('scanFile', {'path': node.path});
          }
        } catch (_) {}

        final item = VaultItem(
          id: id,
          fileName: node.name,
          originalPath: node.path,
          size: node.size,
          dateAdded: DateTime.now(),
        );
        _items.insert(0, item);
      } catch (e) {
        LogService.instance.error('VAULT', 'Error moving "${node.name}" to vault: $e');
        allOk = false;
      }
    }

    await _saveMetadata();
    return allOk;
  }

  Future<bool> restoreFromVault(List<VaultItem> itemsToRestore) async {
    if (!isUnlocked || _unlockedKey == null || _vaultDir == null) return false;

    bool allOk = true;
    for (final item in itemsToRestore) {
      final encFile = File(p.join(_vaultDir!.path, '${item.id}.aef'));
      if (!await encFile.exists()) continue;

      try {
        // Ensure original directory exists
        final targetDir = Directory(p.dirname(item.originalPath));
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        var targetPath = item.originalPath;
        if (await File(targetPath).exists()) {
          final ext = p.extension(item.fileName);
          final base = p.basenameWithoutExtension(item.fileName);
          targetPath = p.join(targetDir.path, '${base}_restored$ext');
        }

        final destFile = File(targetPath);
        await _decryptFile(encFile, destFile, _unlockedKey!);

        // Delete encrypted copy
        await encFile.delete();

        // Notify MediaScanner
        try {
          if (Platform.isAndroid) {
            await _storageChannel.invokeMethod('scanFile', {'path': targetPath});
          }
        } catch (_) {}

        _items.removeWhere((e) => e.id == item.id);
      } catch (e) {
        LogService.instance.error('VAULT', 'Error restoring "${item.fileName}": $e');
        allOk = false;
      }
    }

    await _saveMetadata();
    return allOk;
  }

  Future<bool> deletePermanently(List<VaultItem> itemsToDelete) async {
    if (_vaultDir == null) return false;

    for (final item in itemsToDelete) {
      try {
        final encFile = File(p.join(_vaultDir!.path, '${item.id}.aef'));
        if (await encFile.exists()) {
          await encFile.delete();
        }
        _items.removeWhere((e) => e.id == item.id);
      } catch (_) {}
    }

    await _saveMetadata();
    return true;
  }

  Future<File?> getDecryptedPreviewFile(VaultItem item) async {
    if (!isUnlocked || _unlockedKey == null || _vaultDir == null) return null;

    final encFile = File(p.join(_vaultDir!.path, '${item.id}.aef'));
    if (!await encFile.exists()) return null;

    try {
      final cacheDir = await getTemporaryDirectory();
      final previewDir = Directory(p.join(cacheDir.path, 'vault_preview'));
      if (!await previewDir.exists()) {
        await previewDir.create(recursive: true);
      }

      final destFile = File(p.join(previewDir.path, '${item.id}_${item.fileName}'));
      if (!await destFile.exists()) {
        await _decryptFile(encFile, destFile, _unlockedKey!);
      }
      return destFile;
    } catch (e) {
      LogService.instance.error('VAULT', 'Failed to decrypt preview file: $e');
      return null;
    }
  }

  Future<void> clearPreviewCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final previewDir = Directory(p.join(cacheDir.path, 'vault_preview'));
      if (await previewDir.exists()) {
        await previewDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
