import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/storage_info.dart';
import '../../services/recycle_bin_service.dart';
import '../../services/security/safe_vault_service.dart';
import '../../services/storage_analyzer_service.dart';
import '../../services/vfs/local_vfs.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/apple_card.dart';
import '../../widgets/storage_donut_chart.dart';
import '../security/safe_vault_screen.dart';
import '../settings/settings_screen.dart';
import 'directory_browser_screen.dart';
import 'recycle_bin_screen.dart';
import 'storage_analysis_screen.dart';

class LocalTab extends StatefulWidget {
  final LocalVfs localVfs;
  final RecycleBinService recycleBinService;

  const LocalTab({
    super.key,
    required this.localVfs,
    required this.recycleBinService,
  });

  @override
  State<LocalTab> createState() => _LocalTabState();
}

class _LocalTabState extends State<LocalTab> {
  final _analyzer = StorageAnalyzerService();
  StorageInfo _storageInfo = const StorageInfo(
    totalBytes: 128 * 1024 * 1024 * 1024,
    usedBytes: 0,
    freeBytes: 128 * 1024 * 1024 * 1024,
  );
  bool _permissionGranted = true;

  @override
  void initState() {
    super.initState();
    _quickLoadHwStorage();
    _checkPermissionAndFetch();
  }

  Future<void> _quickLoadHwStorage() async {
    final hw = await _analyzer.getHardwareStorage(path: widget.localVfs.rootPath);
    if (mounted) {
      setState(() {
        _storageInfo = StorageInfo(
          totalBytes: hw['total']!,
          usedBytes: hw['used']!,
          freeBytes: hw['free']!,
        );
      });
    }
  }

  Future<void> _checkPermissionAndFetch() async {
    final granted = await Permission.manageExternalStorage.isGranted ||
        await Permission.storage.isGranted;
    if (mounted) {
      setState(() => _permissionGranted = granted);
    }
    _fetchStorage();
  }

  Future<void> _fetchStorage() async {
    final info = await _analyzer.analyze(widget.localVfs.rootPath);
    if (mounted) {
      setState(() {
        _storageInfo = info;
      });
    }
  }

  Widget _buildTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return AppleCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      body: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(
              'Local Files',
              style: TextStyle(color: isDark ? Colors.white : AppleColors.textPrimaryLight),
            ),
            backgroundColor: isDark ? const Color(0xCC000000) : const Color(0xCCF2F2F7),
            border: null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _fetchStorage,
                  child: Icon(
                    CupertinoIcons.arrow_clockwise,
                    size: 20,
                    color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ).then((_) {
                      if (mounted) setState(() {});
                    });
                  },
                  child: Icon(
                    CupertinoIcons.gear_alt_fill,
                    size: 22,
                    color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                  ),
                ),
              ],
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Storage Permission Warning Banner if not granted
                if (!_permissionGranted) ...[
                  AppleCard(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: const Color(0x33FF9F0A),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(CupertinoIcons.exclamationmark_triangle_fill, color: AppleColors.systemOrange),
                            SizedBox(width: 8),
                            Text(
                              'All Files Access Needed',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Grant file access to browse your internal storage, videos, and music without restrictions.',
                          style: TextStyle(color: AppleColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        CupertinoButton(
                          color: AppleColors.systemOrange,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          borderRadius: BorderRadius.circular(16),
                          onPressed: () async {
                            await openAppSettings();
                            _checkPermissionAndFetch();
                          },
                          child: const Text('Grant Permission in Settings', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Storage Gauge Card
                AppleCard(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      StorageDonutChart(storageInfo: _storageInfo, size: 110),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Main Storage',
                              style: TextStyle(
                                color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_storageInfo.formattedFree} free of ${_storageInfo.formattedTotal}',
                              style: TextStyle(
                                color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: CupertinoButton(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                                borderRadius: BorderRadius.circular(12),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    CupertinoPageRoute(
                                      builder: (_) => StorageAnalysisScreen(rootPath: widget.localVfs.rootPath),
                                    ),
                                  );
                                },
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Analyze Storage',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    SizedBox(width: 6),
                                    Icon(CupertinoIcons.chevron_right, size: 12, color: Colors.white),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'Storage Locations',
                  style: TextStyle(
                    color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),

                const SizedBox(height: 10),

                // Main Storage Tile
                _buildTile(
                  icon: CupertinoIcons.device_phone_portrait,
                  iconColor: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                  title: 'Main Storage',
                  subtitle: 'Internal device storage',
                  isDark: isDark,
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => DirectoryBrowserScreen(
                          vfs: widget.localVfs,
                          initialPath: widget.localVfs.rootPath,
                          title: 'Main Storage',
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 10),

                // Downloads Tile
                _buildTile(
                  icon: CupertinoIcons.arrow_down_circle_fill,
                  iconColor: AppleColors.systemTeal,
                  title: 'Downloads',
                  subtitle: 'Saved internet files',
                  isDark: isDark,
                  onTap: () async {
                    final dlPath = await widget.localVfs.getDownloadsPath();
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => DirectoryBrowserScreen(
                          vfs: widget.localVfs,
                          initialPath: dlPath,
                          title: 'Downloads',
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 10),

                // Recycle Bin Tile
                _buildTile(
                  icon: CupertinoIcons.trash_fill,
                  iconColor: AppleColors.systemOrange,
                  title: 'Recycle Bin',
                  subtitle: '${widget.recycleBinService.items.length} deleted items',
                  isDark: isDark,
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => RecycleBinScreen(recycleBinService: widget.recycleBinService),
                      ),
                    ).then((_) => setState(() {}));
                  },
                ),

                // Safe Vault Tile (Stealth Mode: Visible only when enabled in Settings)
                if (SafeVaultService.instance.isVaultEnabled) ...[
                  const SizedBox(height: 10),
                  _buildTile(
                    icon: CupertinoIcons.lock_shield_fill,
                    iconColor: AppleColors.systemIndigo,
                    title: 'Safe Vault',
                    subtitle: '${SafeVaultService.instance.items.length} encrypted items (AES-256)',
                    isDark: isDark,
                    onTap: () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => const SafeVaultScreen(),
                        ),
                      ).then((_) => setState(() {}));
                    },
                  ),
                ],

                const SizedBox(height: 20),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
