import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/app_update_service.dart';
import '../services/recycle_bin_service.dart';
import '../services/vfs/local_vfs.dart';
import '../theme/apple_theme.dart';
import 'library/library_tab.dart';
import 'local/local_tab.dart';
import 'network/network_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_ready) {
      return Scaffold(
        backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
        body: const Center(child: CupertinoActivityIndicator(radius: 16)),
      );
    }

    final pages = [
      LocalTab(localVfs: _localVfs, recycleBinService: _recycleBinService),
      LibraryTab(localVfs: _localVfs),
      NetworkTab(localVfs: _localVfs),
    ];

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      body: FadeIndexedStack(
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
