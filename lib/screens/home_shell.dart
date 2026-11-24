import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/app_update_service.dart';
import '../services/recycle_bin_service.dart';
import '../services/vfs/local_vfs.dart';
import '../theme/apple_theme.dart';
import 'library/library_tab.dart';
import 'local/directory_browser_screen.dart';
import 'local/local_tab.dart';
import 'local/recycle_bin_screen.dart';
import 'local/storage_analysis_screen.dart';
import 'network/network_tab.dart';
import 'settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
  int _tabletNavIndex = 0;
  late final RecycleBinService _recycleBinService;
  late final LocalVfs _localVfs;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    _recycleBinService = RecycleBinService();
    await _recycleBinService.init();

    _localVfs = LocalVfs(recycleBinService: _recycleBinService);

    // Request full storage management permission on Android
    try {
      if (await Permission.manageExternalStorage.isRestricted) {
        await Permission.manageExternalStorage.request();
      } else {
        await [
          Permission.storage,
          Permission.manageExternalStorage,
        ].request();
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _ready = true);

      // Silent background update check after 3 seconds on app launch
      Future.delayed(const Duration(seconds: 3), () async {
        if (!mounted) return;
        final info = await AppUpdateService.instance.checkForUpdate();
        if (mounted && info != null && info.hasUpdate) {
          AppUpdateService.instance.promptUpdate(context, info);
        }
      });
    }
  }

  Widget _buildTabletSidebar(bool isDark) {
    return Container(
      width: 270,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101010) : AppleColors.lightCard,
        border: Border(
          right: BorderSide(
            color: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Branding Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppleColors.systemBlue, AppleColors.systemIndigo],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppleColors.systemBlue.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(CupertinoIcons.folder_fill, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AeroFiles',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                          color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                        ),
                      ),
                      Text(
                        'v1.0.14 Pro',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
            ),
            const SizedBox(height: 8),

            // Navigation Sections
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                children: [
                  _buildSidebarSectionHeader('LOCATIONS', isDark),
                  _buildSidebarItem(
                    index: 0,
                    icon: CupertinoIcons.folder_fill,
                    iconColor: AppleColors.systemBlue,
                    label: 'Internal Storage',
                    isDark: isDark,
                  ),
                  _buildSidebarItem(
                    index: 1,
                    icon: CupertinoIcons.gauge,
                    iconColor: AppleColors.systemIndigo,
                    label: 'Dashboard',
                    isDark: isDark,
                  ),
                  _buildSidebarItem(
                    index: 2,
                    icon: CupertinoIcons.trash_fill,
                    iconColor: AppleColors.systemRed,
                    label: 'Recycle Bin',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildSidebarSectionHeader('MEDIA', isDark),
                  _buildSidebarItem(
                    index: 3,
                    icon: CupertinoIcons.rectangle_grid_2x2_fill,
                    iconColor: AppleColors.systemPurple,
                    label: 'Media Library',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildSidebarSectionHeader('CONNECTIVITY', isDark),
                  _buildSidebarItem(
                    index: 4,
                    icon: CupertinoIcons.globe,
                    iconColor: AppleColors.systemTeal,
                    label: 'Network Drives & SMB',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildSidebarSectionHeader('SYSTEM & TOOLS', isDark),
                  _buildSidebarItem(
                    index: 5,
                    icon: CupertinoIcons.chart_pie_fill,
                    iconColor: AppleColors.systemOrange,
                    label: 'Storage Analyzer',
                    isDark: isDark,
                  ),
                  _buildSidebarItem(
                    index: 6,
                    icon: CupertinoIcons.gear_alt_fill,
                    iconColor: CupertinoColors.systemGrey,
                    label: 'Settings',
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required int index,
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool isDark,
  }) {
    final isSelected = _tabletNavIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() => _tabletNavIndex = index);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? AppleColors.systemBlue.withValues(alpha: 0.22) : AppleColors.systemBlueLight.withValues(alpha: 0.15))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: isSelected ? (isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight) : iconColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? (isDark ? Colors.white : AppleColors.textPrimaryLight)
                          : (isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight),
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_ready) {
      return Scaffold(
        backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
        body: const Center(child: CupertinoActivityIndicator(radius: 16)),
      );
    }

    final size = MediaQuery.of(context).size;
    final orientation = MediaQuery.of(context).orientation;
    final isTabletLandscape = size.width >= 800 || (size.width >= 720 && orientation == Orientation.landscape);

    if (isTabletLandscape) {
      final tabletPages = [
        DirectoryBrowserScreen(
          vfs: _localVfs,
          initialPath: _localVfs.rootPath,
          title: 'Internal Storage',
        ),
        LocalTab(localVfs: _localVfs, recycleBinService: _recycleBinService),
        RecycleBinScreen(recycleBinService: _recycleBinService),
        LibraryTab(localVfs: _localVfs),
        NetworkTab(localVfs: _localVfs),
        StorageAnalysisScreen(rootPath: _localVfs.rootPath),
        const SettingsScreen(),
      ];

      return Scaffold(
        backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
        body: Row(
          children: [
            _buildTabletSidebar(isDark),
            Expanded(
              child: FadeIndexedStack(
                index: _tabletNavIndex,
                children: tabletPages,
              ),
            ),
          ],
        ),
      );
    }

    final pages = [
      LocalTab(localVfs: _localVfs, recycleBinService: _recycleBinService),
      LibraryTab(localVfs: _localVfs),
      NetworkTab(localVfs: _localVfs),
    ];

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppleColors.darkCard : AppleColors.lightCard,
          border: Border(
            top: BorderSide(
              color: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
              width: 0.5,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: Colors.transparent,
          selectedItemColor: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
          unselectedItemColor: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.folder),
              activeIcon: Icon(CupertinoIcons.folder_fill),
              label: 'Local',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.rectangle_grid_2x2),
              activeIcon: Icon(CupertinoIcons.rectangle_grid_2x2_fill),
              label: 'Library',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.globe),
              activeIcon: Icon(CupertinoIcons.globe),
              label: 'Network',
            ),
          ],
        ),
      ),
    );
  }
}

class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 220),
  });

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.forward();
  }

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      child: IndexedStack(
        index: widget.index,
        children: widget.children,
      ),
    );
  }
}
