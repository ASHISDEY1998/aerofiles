import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/network_connection.dart';
import '../../models/vfs_node.dart';
import '../../services/settings_service.dart';
import '../../services/vfs/local_vfs.dart';
import '../../services/vfs/smb_vfs.dart';
import '../../services/vfs/vfs_provider.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/breadcrumb_bar.dart';

class DestinationPickerScreen extends StatefulWidget {
  final String actionTitle; // 'Copy to' or 'Move to'
  final List<VfsNode> itemsToTransfer;
  final LocalVfs localVfs;

  const DestinationPickerScreen({
    super.key,
    required this.actionTitle,
    required this.itemsToTransfer,
    required this.localVfs,
  });

  @override
  State<DestinationPickerScreen> createState() => _DestinationPickerScreenState();
}

class _DestinationPickerScreenState extends State<DestinationPickerScreen> {
  int _selectedTab = 0; // 0: Local Storage, 1: Network Storage
  late VfsProvider _currentVfs;
  late String _currentPath;
  List<VfsNode> _folders = [];
  bool _isLoading = true;

  SmbVfs? _activeSmbVfs;
  NetworkConnection? _selectedConnection;

  List<NetworkConnection> get _availableConnections {
    return SettingsService.instance.savedConnections;
  }

  @override
  void initState() {
    super.initState();
    _currentVfs = widget.localVfs;
    _currentPath = widget.localVfs.rootPath;
    _selectedConnection = _availableConnections.first;
    _loadDirectory();
  }

  @override
  void dispose() {
    _activeSmbVfs?.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory() async {
    setState(() => _isLoading = true);
    try {
      final items = await _currentVfs.listDirectory(_currentPath);
      debugPrint('[DestinationPicker] Path: "$_currentPath", total items: ${items.length}');
      if (mounted) {
        setState(() {
          _folders = items.where((e) {
            if (!e.isDirectory) return false;
            if (!SettingsService.instance.showHiddenFiles && e.name.startsWith('.')) {
              return false;
            }
            return true;
          }).toList();
          debugPrint('[DestinationPicker] filtered folders: ${_folders.map((e) => e.name).toList()}');
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('[DestinationPicker] Error: $e\n$stack');
      if (mounted) {
        setState(() {
          _folders = [];
          _isLoading = false;
        });
      }
    }
  }

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    _loadDirectory();
  }

  Future<void> _connectToSmb(NetworkConnection conn) async {
    setState(() {
      _isLoading = true;
      _selectedConnection = conn;
    });
    _activeSmbVfs?.dispose();
    final smb = SmbVfs(conn);
    try {
      await smb.connect();
      _activeSmbVfs = smb;
      _currentVfs = smb;
      _currentPath = smb.rootPath;
      await _loadDirectory();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect to ${conn.name}: $e')),
        );
      }
    }
  }

  void _showConnectionSwitcher() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Select Network Storage'),
        actions: _availableConnections.map((conn) {
          final isSelected = conn.id == _selectedConnection?.id;
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _connectToSmb(conn);
            },
            child: Text(
              '${conn.name} (${conn.host})',
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppleColors.systemBlue : null,
              ),
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showCreateFolderDialog() {
    if (_selectedTab == 1 && _currentPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a storage drive first to create a folder.')),
      );
      return;
    }

    final controller = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('New Folder'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Folder Name',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            child: const Text('Create'),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                await _currentVfs.createDirectory(_currentPath, name);
                _loadDirectory();
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isSmbRoot = _selectedTab == 1 && _currentPath.isEmpty;

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      appBar: AppBar(
        title: Text('${widget.actionTitle} (${widget.itemsToTransfer.length} items)'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.folder_badge_plus),
            onPressed: _showCreateFolderDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Segmented Control: Local vs Network Storage
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSegmentedControl<int>(
                groupValue: _selectedTab,
                selectedColor: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                unselectedColor: isDark ? AppleColors.darkCard : AppleColors.lightCard,
                borderColor: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
                children: const {
                  0: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.device_phone_portrait, size: 14),
                        SizedBox(width: 6),
                        Text('Local Storage', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  1: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.globe, size: 14),
                        SizedBox(width: 6),
                        Text('Network (SMB)', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                },
                onValueChanged: (tab) {
                  setState(() => _selectedTab = tab);
                  if (tab == 0) {
                    _currentVfs = widget.localVfs;
                    _currentPath = widget.localVfs.rootPath;
                    _loadDirectory();
                  } else {
                    if (_activeSmbVfs != null) {
                      _currentVfs = _activeSmbVfs!;
                      _currentPath = _activeSmbVfs!.rootPath;
                      _loadDirectory();
                    } else {
                      final conn = _selectedConnection ?? _availableConnections.first;
                      _connectToSmb(conn);
                    }
                  }
                },
              ),
            ),
          ),

          // Network Connection Info Bar when on SMB tab
          if (_selectedTab == 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppleColors.darkCard : AppleColors.lightCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.cloud,
                      size: 16,
                      color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedConnection?.name ?? 'Home NAS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                        ),
                      ),
                    ),
                    if (_availableConnections.length > 1)
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: _showConnectionSwitcher,
                        child: Row(
                          children: [
                            Text(
                              'Switch',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                              ),
                            ),
                            Icon(
                              CupertinoIcons.chevron_up_chevron_down,
                              size: 12,
                              color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Breadcrumbs
          BreadcrumbBar(
            currentPath: _currentPath,
            rootPath: _currentVfs.rootPath,
            onPathSelected: _navigateTo,
          ),

          // Directory Listing
          Expanded(
            child: _isLoading
                ? const Center(child: CupertinoActivityIndicator())
                : _folders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.folder,
                              size: 48,
                              color: isDark ? AppleColors.darkTertiary : AppleColors.lightBorderStroke,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No subfolders here',
                              style: TextStyle(
                                color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 12),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              color: isDark ? AppleColors.darkCard : AppleColors.lightCard,
                              borderRadius: BorderRadius.circular(10),
                              onPressed: _showCreateFolderDialog,
                              child: Text(
                                'Create Subfolder',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _folders.length,
                        itemBuilder: (context, index) {
                          final f = _folders[index];
                          final bool isDrive = _selectedTab == 1 && _currentPath.isEmpty;

                          return ListTile(
                            leading: Icon(
                              isDrive ? CupertinoIcons.archivebox_fill : CupertinoIcons.folder_fill,
                              color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                              size: 28,
                            ),
                            title: Text(
                              f.name,
                              style: TextStyle(
                                color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: isDrive
                                ? Text(
                                    'Network Storage Drive',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                    ),
                                  )
                                : null,
                            trailing: const Icon(CupertinoIcons.chevron_right, size: 14),
                            onTap: () => _navigateTo(f.path),
                          );
                        },
                      ),
          ),

          // Bottom Action Bar: "Copy / Move Here"
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppleColors.darkCard : AppleColors.lightCard,
              border: Border(
                top: BorderSide(
                  color: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Target: ${_currentVfs.displayName}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                          ),
                        ),
                        Text(
                          _currentPath.isEmpty ? '/' : p.basename(_currentPath),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CupertinoButton(
                    color: isSmbRoot
                        ? (isDark ? AppleColors.darkTertiary : AppleColors.lightBorderStroke)
                        : (isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    borderRadius: BorderRadius.circular(14),
                    onPressed: isSmbRoot
                        ? null
                        : () {
                            Navigator.pop(context, {
                              'targetPath': _currentPath,
                              'targetVfs': _currentVfs,
                            });
                          },
                    child: Text(
                      isSmbRoot ? 'Select a Drive/Folder' : '${widget.actionTitle} Here',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSmbRoot ? Colors.white54 : Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
