import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/app_update_service.dart';
import '../../services/log_service.dart';
import '../../services/settings_service.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/apple_card.dart';
import 'legal_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService.instance;
  final _logService = LogService.instance;
  bool _isCheckingUpdate = false;
  bool _isUploadingLog = false;

  Future<void> _handleCheckUpdate() async {
    setState(() => _isCheckingUpdate = true);
    final info = await AppUpdateService.instance.checkForUpdate();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (info != null && info.hasUpdate) {
      AppUpdateService.instance.promptUpdate(context, info);
    } else if (info != null) {
      AppUpdateService.instance.showUpToDateDialog(context, info.currentVersion);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reach update server. Check your network.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              // Section 1: Appearance
              _buildSectionHeader('Appearance', isDark),
              AppleCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Theme',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoSegmentedControl<ThemeMode>(
                        groupValue: _settings.themeMode,
                        selectedColor: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                        unselectedColor: isDark ? AppleColors.darkCard : AppleColors.lightCard,
                        borderColor: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
                        children: const {
                          ThemeMode.dark: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(CupertinoIcons.moon_fill, size: 14),
                                SizedBox(width: 6),
                                Text('Dark', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                          ThemeMode.light: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(CupertinoIcons.sun_max_fill, size: 14),
                                SizedBox(width: 6),
                                Text('Light', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                          ThemeMode.system: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(CupertinoIcons.device_phone_portrait, size: 14),
                                SizedBox(width: 6),
                                Text('System', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        },
                        onValueChanged: (mode) => _settings.setThemeMode(mode),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Section 2: Delete & Recycle Bin
              _buildSectionHeader('Delete & Recycle Bin', isDark),
              AppleCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Default Delete Action'),
                      subtitle: Text(_getDeleteBehaviorLabel(_settings.deleteBehavior)),
                      trailing: const Icon(CupertinoIcons.chevron_right, size: 14),
                      onTap: _showDeleteBehaviorPicker,
                    ),
                    const Divider(height: 1, indent: 16),
                    SwitchListTile(
                      title: const Text('Auto-empty Recycle Bin'),
                      subtitle: const Text('Automatically purge files older than 30 days'),
                      value: _settings.autoEmptyTrash,
                      activeTrackColor: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                      onChanged: (val) => _settings.setAutoEmptyTrash(val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Section 3: File Options
              _buildSectionHeader('File Explorer Options', isDark),
              AppleCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Show Hidden Files'),
                      subtitle: const Text('Display files and folders starting with a dot (.)'),
                      value: _settings.showHiddenFiles,
                      activeTrackColor: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                      onChanged: (val) => _settings.setShowHiddenFiles(val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Section 4: Diagnostics & Logging
              _buildSectionHeader('Diagnostics & Logging', isDark),
              AppleCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(CupertinoIcons.waveform_path_ecg, color: AppleColors.systemOrange),
                      title: const Text('Enable Diagnostic Logging'),
                      subtitle: const Text('Record app events, network activity, and errors for debugging'),
                      value: _logService.isLoggingEnabled,
                      activeTrackColor: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                      onChanged: (val) async {
                        await _logService.setLoggingEnabled(val);
                        setState(() {});
                      },
                    ),
                    if (_logService.isLoggingEnabled || _logService.entryCount > 0) ...[
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(CupertinoIcons.doc_text_fill, color: AppleColors.systemBlue),
                        title: Text('Log File (${_logService.logSizeText})'),
                        subtitle: Text(
                          _logService.isLoggingEnabled
                              ? 'Logging active • ${_logService.entryCount} entries'
                              : 'Logging paused • ${_logService.entryCount} entries',
                        ),
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: _showLogViewerModal,
                          child: const Text('View'),
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(CupertinoIcons.paperplane_fill, color: AppleColors.systemGreen),
                        title: const Text(
                          'Send Diagnostic Logs',
                          style: TextStyle(color: AppleColors.systemGreen, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text('Upload link to GitHub/Cloud, share file, or copy'),
                        trailing: _isUploadingLog
                            ? const CupertinoActivityIndicator(radius: 9)
                            : const Icon(CupertinoIcons.chevron_right, size: 14),
                        onTap: _isUploadingLog ? null : _showSendLogSheet,
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(CupertinoIcons.trash, color: AppleColors.systemRed),
                        title: const Text('Clear Log Buffer', style: TextStyle(color: AppleColors.systemRed)),
                        onTap: () async {
                          await _logService.clearLogs();
                          setState(() {});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Log buffer cleared')),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Section 5: Legal & Play Store
              _buildSectionHeader('About & Legal', isDark),
              AppleCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(CupertinoIcons.doc_plaintext),
                      title: const Text('License Agreement (EULA)'),
                      trailing: const Icon(CupertinoIcons.chevron_right, size: 14),
                      onTap: () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const LegalScreen(type: LegalDocType.eula),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(CupertinoIcons.shield_lefthalf_fill),
                      title: const Text('Privacy Policy'),
                      trailing: const Icon(CupertinoIcons.chevron_right, size: 14),
                      onTap: () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const LegalScreen(type: LegalDocType.privacyPolicy),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(CupertinoIcons.checkmark_seal_fill),
                      title: const Text('Open Source Licenses'),
                      trailing: const Icon(CupertinoIcons.chevron_right, size: 14),
                      onTap: () {
                        showLicensePage(
                          context: context,
                          applicationName: 'AeroFiles',
                          applicationVersion: '1.0.2',
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(CupertinoIcons.arrow_clockwise_circle_fill, color: AppleColors.systemBlue),
                      title: const Text('Check for Updates'),
                      subtitle: const Text('Auto-update directly from GitHub'),
                      trailing: _isCheckingUpdate
                          ? const CupertinoActivityIndicator(radius: 9)
                          : const Icon(CupertinoIcons.chevron_right, size: 14),
                      onTap: _isCheckingUpdate ? null : _handleCheckUpdate,
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(CupertinoIcons.info_circle_fill),
                      title: const Text('Version'),
                      trailing: FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, snapshot) {
                          final version = snapshot.hasData ? snapshot.data!.version : '1.0.2';
                          final build = snapshot.hasData ? snapshot.data!.buildNumber : '3';
                          return Text(
                            '$version (Build $build)',
                            style: const TextStyle(color: AppleColors.textSecondary),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _getDeleteBehaviorLabel(DeleteBehavior behavior) {
    switch (behavior) {
      case DeleteBehavior.ask:
        return 'Always ask each time';
      case DeleteBehavior.recycleBin:
        return 'Move to Recycle Bin by default';
      case DeleteBehavior.permanent:
        return 'Delete permanently by default';
    }
  }

  void _showDeleteBehaviorPicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Default Delete Action'),
        message: const Text('Choose what happens when you delete files or folders'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              _settings.setDeleteBehavior(DeleteBehavior.ask);
              Navigator.pop(ctx);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_settings.deleteBehavior == DeleteBehavior.ask)
                  const Icon(CupertinoIcons.check_mark, size: 16),
                const SizedBox(width: 8),
                const Text('Always ask each time'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              _settings.setDeleteBehavior(DeleteBehavior.recycleBin);
              Navigator.pop(ctx);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_settings.deleteBehavior == DeleteBehavior.recycleBin)
                  const Icon(CupertinoIcons.check_mark, size: 16),
                const SizedBox(width: 8),
                const Text('Move to Recycle Bin (Recommended)'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              _settings.setDeleteBehavior(DeleteBehavior.permanent);
              Navigator.pop(ctx);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_settings.deleteBehavior == DeleteBehavior.permanent)
                  const Icon(CupertinoIcons.check_mark, size: 16),
                const SizedBox(width: 8),
                const Text('Delete permanently'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showSendLogSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Send Diagnostic Logs'),
        message: const Text('Choose how to send or export your diagnostic logs to developers:'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await _handleUploadLogCloud();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.cloud_upload_fill, size: 18),
                SizedBox(width: 8),
                Text('Upload & Get Shareable Cloud Link'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await _handleShareLogFile();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.share, size: 18),
                SizedBox(width: 8),
                Text('Share File via Apps (Email, Drive, Chat)'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await _handleSaveToDownloads();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.arrow_down_doc_fill, size: 18),
                SizedBox(width: 8),
                Text('Save to Device Downloads Folder'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final content = await _logService.getLogContent();
              await Clipboard.setData(ClipboardData(text: content));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All logs copied to clipboard')),
                );
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.doc_on_clipboard_fill, size: 18),
                SizedBox(width: 8),
                Text('Copy All Text to Clipboard'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _handleUploadLogCloud() async {
    setState(() => _isUploadingLog = true);
    final url = await _logService.uploadLogCloud();
    if (!mounted) return;
    setState(() => _isUploadingLog = false);

    if (url != null) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;

      showCupertinoDialog(
        context: context,
        builder: (dialogCtx) => CupertinoAlertDialog(
          title: const Text('Logs Uploaded Successfully!'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Public link has been copied to your clipboard:'),
                const SizedBox(height: 8),
                SelectableText(
                  url,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppleColors.systemBlue),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You can share this link in the chat or create a GitHub issue directly.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Submit to GitHub Issues'),
              onPressed: () {
                Navigator.pop(dialogCtx);
                final ghUrl =
                    'https://github.com/ASHISDEY1998/aerofiles/issues/new?title=Diagnostic+Log&body=View+full+diagnostic+log+here:+${Uri.encodeComponent(url)}';
                OpenFilex.open(ghUrl);
              },
            ),
            CupertinoDialogAction(
              child: const Text('Open Link'),
              onPressed: () {
                Navigator.pop(dialogCtx);
                OpenFilex.open(url);
              },
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('Done'),
              onPressed: () => Navigator.pop(dialogCtx),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload logs. Check your network or try "Share File".')),
      );
    }
  }

  Future<void> _handleShareLogFile() async {
    try {
      final content = await _logService.getLogContent();
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/aerofiles_diagnostic_log.txt');
      await tempFile.writeAsString(content, flush: true);

      await Share.shareXFiles(
        [XFile(tempFile.path)],
        subject: 'AeroFiles Diagnostic Log',
        text: 'AeroFiles Diagnostic Log export',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    }
  }

  Future<void> _handleSaveToDownloads() async {
    final savedPath = await _logService.saveLogToDownloads();
    if (mounted) {
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Log saved to: $savedPath')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save to Downloads')),
        );
      }
    }
  }

  void _showLogViewerModal() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = await _logService.getLogContent();
    if (!mounted) return;

    showCupertinoModalPopup(
      context: context,
      builder: (modalCtx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? AppleColors.darkElevated : AppleColors.lightCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(modalCtx),
                    child: const Text('Close'),
                  ),
                  const Text('Live Diagnostics Log', style: TextStyle(fontWeight: FontWeight.w600)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: content));
                      if (modalCtx.mounted) {
                        Navigator.pop(modalCtx);
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Log copied to clipboard')),
                        );
                      }
                    },
                    child: const Text('Copy All'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  content.isEmpty ? 'No log entries recorded yet.' : content,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
