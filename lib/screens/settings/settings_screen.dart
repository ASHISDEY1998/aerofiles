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
import '../../services/media/thumbnail_service.dart';
import '../../services/security/biometric_service.dart';
import '../../services/security/safe_vault_service.dart';
import '../../services/settings_service.dart';
import '../../theme/apple_theme.dart';
import '../security/safe_vault_screen.dart';
import '../security/vault_pin_dialog.dart';
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

  Widget _buildSquircleIcon(IconData icon, Color bgColor, {Color iconColor = Colors.white, double size = 18}) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: iconColor, size: size),
    );
  }

  Widget _buildGroupCard({required List<Widget> children, required bool isDark}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildRowItem({
    required Widget icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool showDivider = true,
    bool isDark = true,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing,
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 58,
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: isDark ? AppleColors.pureBlack : const Color(0xFFF2F2F7),
        elevation: 0,
      ),
      body: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // Hero Header Card (Apple Profile Style)
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppleColors.systemBlue, AppleColors.systemIndigo],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: [
                              BoxShadow(
                                color: AppleColors.systemBlue.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Icon(CupertinoIcons.folder_fill, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'AeroFiles',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppleColors.systemBlue.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'PRO',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppleColors.systemBlue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Private Local & Network File Manager',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          color: AppleColors.systemBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          onPressed: _handleCheckUpdate,
                          child: _isCheckingUpdate
                              ? const CupertinoActivityIndicator(radius: 7)
                              : const Text(
                                  'Update',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppleColors.systemBlue),
                                ),
                        ),
                      ],
                    ),
                  ),

                  // Section 1: Appearance
                  _buildSectionHeader('APPEARANCE', isDark),
                  _buildGroupCard(
                    isDark: isDark,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _buildSquircleIcon(CupertinoIcons.sun_max_fill, AppleColors.systemBlue),
                                const SizedBox(width: 14),
                                Text(
                                  'Interface Theme',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                    color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: CupertinoSegmentedControl<ThemeMode>(
                                groupValue: _settings.themeMode,
                                selectedColor: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                                unselectedColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                                borderColor: Colors.transparent,
                                children: const {
                                  ThemeMode.dark: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(CupertinoIcons.moon_fill, size: 14),
                                        SizedBox(width: 6),
                                        Text('Dark', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                                        Text('Light', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                                        Text('System', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                    ],
                  ),

                  const SizedBox(height: 22),

                  // Section 2: File Management & Trash
                  _buildSectionHeader('FILE MANAGEMENT & TRASH', isDark),
                  _buildGroupCard(
                    isDark: isDark,
                    children: [
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.trash_fill, AppleColors.systemRed),
                        title: 'Default Delete Action',
                        subtitle: _getDeleteBehaviorLabel(_settings.deleteBehavior),
                        trailing: const Icon(CupertinoIcons.chevron_right, size: 14, color: AppleColors.textTertiary),
                        onTap: _showDeleteBehaviorPicker,
                        isDark: isDark,
                      ),
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.clock_fill, AppleColors.systemOrange),
                        title: 'Auto-empty Recycle Bin',
                        subtitle: 'Automatically purge files older than 30 days',
                        trailing: CupertinoSwitch(
                          value: _settings.autoEmptyTrash,
                          activeTrackColor: AppleColors.systemBlue,
                          onChanged: (val) => _settings.setAutoEmptyTrash(val),
                        ),
                        isDark: isDark,
                      ),
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.eye_fill, AppleColors.systemPurple),
                        title: 'Show Hidden Files',
                        subtitle: 'Display files and folders starting with a dot (.)',
                        trailing: CupertinoSwitch(
                          value: _settings.showHiddenFiles,
                          activeTrackColor: AppleColors.systemBlue,
                          onChanged: (val) => _settings.setShowHiddenFiles(val),
                        ),
                        showDivider: false,
                        isDark: isDark,
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  // Section 3: Security & Privacy
                  _buildSectionHeader('SECURITY & PRIVACY', isDark),
                  _buildGroupCard(
                    isDark: isDark,
                    children: [
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.lock_shield_fill, AppleColors.systemGreen),
                        title: 'App Lock (Biometrics & PIN)',
                        subtitle: 'Require Fingerprint, Face ID, or PIN to open app',
                        trailing: CupertinoSwitch(
                          value: BiometricService.instance.isAppLockEnabled,
                          activeTrackColor: AppleColors.systemBlue,
                          onChanged: (val) async {
                            final canAuth = await BiometricService.instance.canAuthenticate();
                            if (!canAuth && val) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('No biometrics or device PIN configured on this device')),
                                );
                              }
                              return;
                            }

                            final authenticated = await BiometricService.instance.authenticate(
                              reason: val
                                  ? 'Verify identity to enable App Lock'
                                  : 'Verify identity to disable App Lock',
                            );

                            if (authenticated) {
                              await BiometricService.instance.setAppLockEnabled(val);
                              setState(() {});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(val ? 'App Lock enabled' : 'App Lock disabled'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                        isDark: isDark,
                      ),
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.shield_lefthalf_fill, AppleColors.systemIndigo),
                        title: 'Safe Vault (AES-256)',
                        subtitle: 'Hardware encrypted folder hidden from gallery and files',
                        trailing: CupertinoSwitch(
                          value: SafeVaultService.instance.isVaultEnabled,
                          activeTrackColor: AppleColors.systemIndigo,
                          onChanged: (val) async {
                            if (val) {
                              if (!SafeVaultService.instance.hasPin) {
                                final created = await VaultPinDialog.show(
                                  context,
                                  mode: VaultPinMode.setup,
                                );
                                if (created && context.mounted) {
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Safe Vault enabled. Entry is now visible in Local Storage.'),
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                }
                              } else {
                                final unlocked = await VaultPinDialog.show(
                                  context,
                                  mode: VaultPinMode.unlock,
                                );
                                if (unlocked) {
                                  await SafeVaultService.instance.setVaultEnabled(true);
                                  if (context.mounted) {
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Safe Vault enabled and visible in app'),
                                        duration: Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                }
                              }
                            } else {
                              final unlocked = await VaultPinDialog.show(
                                context,
                                mode: VaultPinMode.unlock,
                              );
                              if (unlocked) {
                                await SafeVaultService.instance.setVaultEnabled(false);
                                if (context.mounted) {
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Safe Vault is now completely hidden from app'),
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                        ),
                        showDivider: SafeVaultService.instance.isVaultEnabled,
                        isDark: isDark,
                      ),
                      if (SafeVaultService.instance.isVaultEnabled) ...[
                        _buildRowItem(
                          icon: _buildSquircleIcon(CupertinoIcons.viewfinder, AppleColors.systemTeal),
                          title: 'Vault Fingerprint Unlock',
                          subtitle: 'Allow biometric fingerprint to unlock Safe Vault',
                          trailing: CupertinoSwitch(
                            value: SafeVaultService.instance.isBiometricsEnabled,
                            activeTrackColor: AppleColors.systemBlue,
                            onChanged: (val) async {
                              await SafeVaultService.instance.setBiometricsEnabled(val);
                              setState(() {});
                            },
                          ),
                          isDark: isDark,
                        ),
                        _buildRowItem(
                          icon: _buildSquircleIcon(CupertinoIcons.pencil_circle_fill, AppleColors.systemOrange),
                          title: 'Change Vault PIN',
                          subtitle: 'Update your custom Safe Vault password',
                          trailing: const Icon(CupertinoIcons.chevron_right, size: 14, color: AppleColors.textTertiary),
                          onTap: () async {
                            final changed = await VaultPinDialog.show(
                              context,
                              mode: VaultPinMode.change,
                            );
                            if (changed && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Safe Vault PIN updated successfully'),
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                          isDark: isDark,
                        ),
                        _buildRowItem(
                          icon: _buildSquircleIcon(CupertinoIcons.folder_badge_person_crop, AppleColors.systemGreen),
                          title: 'Open Safe Vault',
                          subtitle: '${SafeVaultService.instance.items.length} encrypted items',
                          trailing: const Icon(CupertinoIcons.chevron_right, size: 14, color: AppleColors.textTertiary),
                          onTap: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (_) => const SafeVaultScreen(),
                              ),
                            ).then((_) {
                              if (mounted) setState(() {});
                            });
                          },
                          showDivider: false,
                          isDark: isDark,
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 22),

                  // Section 4: Diagnostics & Cache
                  _buildSectionHeader('DIAGNOSTICS & SYSTEM', isDark),
                  _buildGroupCard(
                    isDark: isDark,
                    children: [
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.waveform_path_ecg, AppleColors.systemOrange),
                        title: 'Diagnostic Logging',
                        subtitle: 'Record app events, network activity, and errors for debugging',
                        trailing: CupertinoSwitch(
                          value: _logService.isLoggingEnabled,
                          activeTrackColor: AppleColors.systemBlue,
                          onChanged: (val) async {
                            await _logService.setLoggingEnabled(val);
                            setState(() {});
                          },
                        ),
                        showDivider: _logService.isLoggingEnabled || _logService.entryCount > 0,
                        isDark: isDark,
                      ),
                      if (_logService.isLoggingEnabled || _logService.entryCount > 0) ...[
                        _buildRowItem(
                          icon: _buildSquircleIcon(CupertinoIcons.doc_text_fill, AppleColors.systemBlue),
                          title: 'Log File (${_logService.logSizeText})',
                          subtitle: _logService.isLoggingEnabled
                              ? 'Logging active • ${_logService.entryCount} entries'
                              : 'Logging paused • ${_logService.entryCount} entries',
                          trailing: CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            color: AppleColors.systemBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            onPressed: _showLogViewerModal,
                            child: const Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppleColors.systemBlue)),
                          ),
                          isDark: isDark,
                        ),
                        _buildRowItem(
                          icon: _buildSquircleIcon(CupertinoIcons.paperplane_fill, AppleColors.systemGreen),
                          title: 'Send Diagnostic Logs',
                          subtitle: 'Upload cloud link, share file, or copy',
                          trailing: _isUploadingLog
                              ? const CupertinoActivityIndicator(radius: 8)
                              : const Icon(CupertinoIcons.chevron_right, size: 14, color: AppleColors.textTertiary),
                          onTap: _isUploadingLog ? null : _showSendLogSheet,
                          isDark: isDark,
                        ),
                        _buildRowItem(
                          icon: _buildSquircleIcon(CupertinoIcons.trash_fill, AppleColors.systemRed),
                          title: 'Clear Log Buffer',
                          trailing: const Icon(CupertinoIcons.chevron_right, size: 14, color: AppleColors.textTertiary),
                          onTap: () async {
                            await _logService.clearLogs();
                            setState(() {});
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Log buffer cleared')),
                              );
                            }
                          },
                          isDark: isDark,
                        ),
                      ],
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.photo_fill, AppleColors.systemPink),
                        title: 'Clear Thumbnail Cache',
                        subtitle: 'Free disk space used by video thumbnails',
                        trailing: const Icon(CupertinoIcons.chevron_right, size: 14, color: AppleColors.textTertiary),
                        onTap: () async {
                          await ThumbnailService.instance.clearAll();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Thumbnail cache cleared')),
                            );
                          }
                        },
                        showDivider: false,
                        isDark: isDark,
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  // Section 5: About & Legal
                  _buildSectionHeader('ABOUT & LEGAL', isDark),
                  _buildGroupCard(
                    isDark: isDark,
                    children: [
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.arrow_clockwise_circle_fill, AppleColors.systemBlue),
                        title: 'Check for Updates',
                        subtitle: 'Auto-update directly from GitHub releases',
                        trailing: _isCheckingUpdate
                            ? const CupertinoActivityIndicator(radius: 8)
                            : const Icon(CupertinoIcons.chevron_right, size: 14, color: AppleColors.textTertiary),
                        onTap: _isCheckingUpdate ? null : _handleCheckUpdate,
                        isDark: isDark,
                      ),
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.doc_plaintext, AppleColors.catSystem),
                        title: 'License Agreement (EULA)',
                        trailing: const Icon(CupertinoIcons.chevron_right, size: 14, color: AppleColors.textTertiary),
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const LegalScreen(type: LegalDocType.eula),
                            ),
                          );
                        },
                        isDark: isDark,
                      ),
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.shield_fill, AppleColors.systemIndigo),
                        title: 'Privacy Policy',
                        trailing: const Icon(CupertinoIcons.chevron_right, size: 14, color: AppleColors.textTertiary),
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const LegalScreen(type: LegalDocType.privacyPolicy),
                            ),
                          );
                        },
                        isDark: isDark,
                      ),
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.checkmark_seal_fill, AppleColors.systemTeal),
                        title: 'Open Source Licenses',
                        trailing: const Icon(CupertinoIcons.chevron_right, size: 14, color: AppleColors.textTertiary),
                        onTap: () {
                          showLicensePage(
                            context: context,
                            applicationName: 'AeroFiles',
                            applicationVersion: '2.1.3',
                          );
                        },
                        isDark: isDark,
                      ),
                      _buildRowItem(
                        icon: _buildSquircleIcon(CupertinoIcons.info_circle_fill, AppleColors.catSystem),
                        title: 'Version',
                        trailing: FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) {
                            final version = snapshot.hasData ? snapshot.data!.version : '2.1.3';
                            final build = snapshot.hasData ? snapshot.data!.buildNumber : '20';
                            return Text(
                              '$version (Build $build)',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                              ),
                            );
                          },
                        ),
                        showDivider: false,
                        isDark: isDark,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
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

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          subject: 'AeroFiles Diagnostic Log',
          text: 'AeroFiles Diagnostic Log export',
        ),
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
