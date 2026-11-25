import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/apple_theme.dart';

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseTitle;
  final String releaseNotes;
  final String apkUrl;
  final int apkSize;
  final bool hasUpdate;
  final DateTime? publishedAt;

  AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.apkUrl,
    required this.apkSize,
    required this.hasUpdate,
    this.publishedAt,
  });
}

class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._();
  AppUpdateService._();

  static const String _releasesApiUrl =
      'https://api.github.com/repos/ASHISDEY1998/aerofiles/releases/latest';

  /// Release compilation timestamp (UTC) for legacy testing.
  static final DateTime localReleaseDate = DateTime.utc(2026, 11, 24, 23, 56, 0);

  bool _isChecking = false;
  bool _isDialogShowing = false;

  /// Compares [remote] version against [local] version.
  /// Returns 1 if remote > local, -1 if remote < local, 0 if identical.
  static int compareVersions(String remote, String local) {
    final cleanRemote = remote.replaceAll(RegExp(r'^[vV]'), '').trim();
    final cleanLocal = local.replaceAll(RegExp(r'^[vV]'), '').trim();

    final rParts = cleanRemote
        .split(RegExp(r'[.+_-]'))
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final lParts = cleanLocal
        .split(RegExp(r'[.+_-]'))
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    final maxLen = rParts.length > lParts.length ? rParts.length : lParts.length;
    for (int i = 0; i < maxLen; i++) {
      final rVal = i < rParts.length ? rParts[i] : 0;
      final lVal = i < lParts.length ? lParts[i] : 0;
      if (rVal > lVal) return 1;
      if (rVal < lVal) return -1;
    }
    return 0;
  }

  /// Determines whether an update is available by evaluating Semantic Versioning,
  /// build numbers, and optional explicit build dates.
  /// Prevents false positives where identical versions trigger update prompts.
  static bool isUpdateAvailable({
    required String remoteTag,
    required String localVersion,
    required String localBuildNumber,
    required DateTime? remotePublishedAt,
    DateTime? localBuildDate,
    String? releaseTitle,
  }) {
    // 1. Semantic Version comparison
    final semVerComparison = compareVersions(remoteTag, localVersion);
    if (semVerComparison > 0) return true;
    if (semVerComparison < 0) return false;

    // 2. If SemVer versions are identical, compare build numbers if present
    int? remoteBuild;
    if (remoteTag.contains('+')) {
      remoteBuild = int.tryParse(remoteTag.split('+').last);
    }
    if (remoteBuild == null && releaseTitle != null) {
      final match = RegExp(r'Build\s+(\d+)', caseSensitive: false).firstMatch(releaseTitle);
      if (match != null) {
        remoteBuild = int.tryParse(match.group(1)!);
      }
    }
    final localBuild = int.tryParse(localBuildNumber);
    if (remoteBuild != null && localBuild != null) {
      if (remoteBuild > localBuild) return true;
      if (remoteBuild <= localBuild) return false;
    }

    // 3. If an explicit localBuildDate is passed (e.g. unit tests or custom CI),
    // check if remote was published after local build date (+10 min buffer)
    if (localBuildDate != null && remotePublishedAt != null) {
      if (remotePublishedAt.isAfter(localBuildDate.add(const Duration(minutes: 10)))) {
        return true;
      }
    }

    // 4. Default: identical versions with no newer build are already up-to-date
    return false;
  }

  /// Legacy helper for backwards compatibility
  static bool isNewerVersion(String remote, String local) {
    return compareVersions(remote, local) > 0;
  }

  static String _detectDeviceAbi() {
    try {
      final abi = Abi.current();
      if (abi == Abi.androidArm64) return 'arm64';
      if (abi == Abi.androidArm) return 'armv7';
      if (abi == Abi.androidX64) return 'x86_64';
    } catch (_) {}
    return 'arm64'; // Default to arm64-v8a for modern Android
  }

  Future<AppUpdateInfo?> checkForUpdate() async {
    if (_isChecking) return null;
    _isChecking = true;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = packageInfo.buildNumber;

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(_releasesApiUrl));
      request.headers.set('User-Agent', 'AeroFiles-Android-App');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close();
      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final json = jsonDecode(body) as Map<String, dynamic>;
      final rawTag = (json['tag_name'] as String?) ?? '';
      final releaseTitle = (json['name'] as String?) ?? 'AeroFiles Update';
      final releaseNotes = (json['body'] as String?) ?? '';
      final assets = (json['assets'] as List<dynamic>?) ?? [];
      final publishedAtStr = json['published_at'] as String?;
      final publishedAt = publishedAtStr != null ? DateTime.tryParse(publishedAtStr) : null;

      // Select best APK asset matching device architecture
      final targetAbi = _detectDeviceAbi();
      String apkUrl = '';
      int apkSize = 0;

      // 1. Try matching target ABI (e.g. AeroFiles-arm64-v8a.apk)
      for (final asset in assets) {
        final name = (asset['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk') && name.toLowerCase().contains(targetAbi)) {
          apkUrl = (asset['browser_download_url'] as String?) ?? '';
          apkSize = (asset['size'] as int?) ?? 0;
          break;
        }
      }

      // 2. Try universal AeroFiles.apk
      if (apkUrl.isEmpty) {
        for (final asset in assets) {
          final name = (asset['name'] as String?) ?? '';
          final lower = name.toLowerCase();
          if (lower.endsWith('.apk') && !lower.contains('armv7') && !lower.contains('x86')) {
            apkUrl = (asset['browser_download_url'] as String?) ?? '';
            apkSize = (asset['size'] as int?) ?? 0;
            break;
          }
        }
      }

      // 3. Fallback to any APK
      if (apkUrl.isEmpty) {
        for (final asset in assets) {
          final name = (asset['name'] as String?) ?? '';
          if (name.toLowerCase().endsWith('.apk')) {
            apkUrl = (asset['browser_download_url'] as String?) ?? '';
            apkSize = (asset['size'] as int?) ?? 0;
            break;
          }
        }
      }

      final hasUpdate = isUpdateAvailable(
        remoteTag: rawTag,
        localVersion: currentVersion,
        localBuildNumber: currentBuildNumber,
        remotePublishedAt: publishedAt,
        releaseTitle: releaseTitle,
      ) && apkUrl.isNotEmpty;

      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: rawTag.replaceAll(RegExp(r'^[vV]'), ''),
        releaseTitle: releaseTitle,
        releaseNotes: releaseNotes,
        apkUrl: apkUrl,
        apkSize: apkSize,
        hasUpdate: hasUpdate,
        publishedAt: publishedAt,
      );
    } catch (e) {
      debugPrint('Check for update error: $e');
      return null;
    } finally {
      _isChecking = false;
    }
  }

  Future<void> installApk(File apkFile) async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.requestInstallPackages.status;
        if (!status.isGranted) {
          await Permission.requestInstallPackages.request();
        }
      }
      await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );
    } catch (e) {
      debugPrint('Error installing APK: $e');
    }
  }

  void promptUpdate(BuildContext context, AppUpdateInfo info) {
    if (_isDialogShowing) return;
    if (!info.hasUpdate) return;
    // Safety check: Never show update dialog if current and latest versions are identical
    if (info.currentVersion == info.latestVersion) return;
    _isDialogShowing = true;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.arrow_down_circle_fill, color: AppleColors.systemBlue, size: 24),
            const SizedBox(width: 8),
            const Text('Update Available', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? AppleColors.darkElevated : AppleColors.lightElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'v${info.currentVersion}  ➔  v${info.latestVersion}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppleColors.systemBlue,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (info.apkSize > 0)
                Text(
                  'Download size: ${(info.apkSize / (1024 * 1024)).toStringAsFixed(1)} MB',
                  style: TextStyle(
                    color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 12),
              if (info.releaseNotes.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? AppleColors.pureBlack : AppleColors.lightCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
                      width: 0.5,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      info.releaseNotes,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Later'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Update Now'),
            onPressed: () {
              Navigator.pop(ctx);
              _startDownloadAndInstall(context, info);
            },
          ),
        ],
      ),
    ).whenComplete(() {
      _isDialogShowing = false;
    });
  }

  void _startDownloadAndInstall(BuildContext context, AppUpdateInfo info) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(info: info),
    );
  }

  void showUpToDateDialog(BuildContext context, String version) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.checkmark_circle_fill, color: AppleColors.systemGreen, size: 24),
            SizedBox(width: 8),
            Text('Up to Date'),
          ],
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'AeroFiles v$version is currently the newest version available.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final AppUpdateInfo info;

  const _DownloadProgressDialog({required this.info});

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  bool _isInstalling = false;
  String? _errorMessage;
  HttpClient? _client;
  IOSink? _fileSink;
  File? _targetFile;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/AeroFiles_v${widget.info.latestVersion}.apk');
      _targetFile = file;

      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      _client = HttpClient();
      _client!.autoUncompress = true;
      final request = await _client!.getUrl(Uri.parse(widget.info.apkUrl));
      request.headers.set('User-Agent', 'AeroFiles-Android-App');
      final response = await request.close();

      if (response.statusCode != 200 && response.statusCode != 206) {
        if (mounted) {
          setState(() => _errorMessage = 'Failed to download (HTTP ${response.statusCode})');
        }
        return;
      }

      _totalBytes = response.contentLength > 0 ? response.contentLength : widget.info.apkSize;
      _fileSink = file.openWrite();

      await for (final chunk in response) {
        if (_cancelled) break;
        _fileSink!.add(chunk);
        _downloadedBytes += chunk.length;
        if (mounted) {
          setState(() {
            _progress = _totalBytes > 0 ? (_downloadedBytes / _totalBytes).clamp(0.0, 1.0) : 0.0;
          });
        }
      }

      await _fileSink?.flush();
      await _fileSink?.close();
      _fileSink = null;

      if (_cancelled) {
        if (await file.exists()) await file.delete();
        return;
      }

      if (mounted) {
        setState(() => _isInstalling = true);
      }

      await AppUpdateService.instance.installApk(file);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!_cancelled && mounted) {
        setState(() => _errorMessage = 'Download error: $e');
      }
    }
  }

  void _cancel() {
    _cancelled = true;
    _client?.close(force: true);
    _fileSink?.close();
    if (_targetFile != null && _targetFile!.existsSync()) {
      try {
        _targetFile!.deleteSync();
      } catch (_) {}
    }
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _client?.close(force: true);
    _fileSink?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_errorMessage != null) {
      return CupertinoAlertDialog(
        title: const Text('Download Failed'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_errorMessage!, style: const TextStyle(fontSize: 12)),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Close'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
    }

    return CupertinoAlertDialog(
      title: Text(_isInstalling ? 'Launching Installer' : 'Downloading Update'),
      content: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _isInstalling ? null : _progress,
                backgroundColor: isDark ? AppleColors.darkElevated : AppleColors.lightElevated,
                valueColor: const AlwaysStoppedAnimation<Color>(AppleColors.systemBlue),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isInstalling
                  ? 'Please confirm the install prompt...'
                  : '${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(_totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB (${(_progress * 100).toInt()}%)',
              style: TextStyle(
                color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!_isInstalling)
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}
