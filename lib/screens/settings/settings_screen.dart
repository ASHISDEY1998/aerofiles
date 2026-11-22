import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/app_update_service.dart';
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
  bool _isCheckingUpdate = false;

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

              // Section 4: Legal & Play Store
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
                          applicationVersion: '1.0.0',
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
                          final version = snapshot.hasData ? snapshot.data!.version : '1.0.0';
                          final build = snapshot.hasData ? snapshot.data!.buildNumber : '1';
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
}
