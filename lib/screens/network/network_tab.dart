import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/network_connection.dart';
import '../../services/network/ftp_server_service.dart';
import '../../services/network/lan_scanner_service.dart';
import '../../services/settings_service.dart';
import '../../services/vfs/local_vfs.dart';
import '../../services/vfs/sftp_vfs.dart';
import '../../services/vfs/smb_vfs.dart';
import '../../services/vfs/webdav_vfs.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/apple_card.dart';
import '../local/directory_browser_screen.dart';

class NetworkTab extends StatefulWidget {
  final LocalVfs localVfs;

  const NetworkTab({super.key, required this.localVfs});

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  final _ftpServer = FtpServerService();
  final _lanScanner = LanScannerService();

  bool _isServerActive = false;
  bool _isScanning = false;
  double _scanProgress = 0.0;
  List<DiscoveredDevice> _discoveredDevices = [];

  List<NetworkConnection> get _savedConnections => SettingsService.instance.savedConnections;

  @override
  void dispose() {
    _ftpServer.stopServer();
    super.dispose();
  }

  void _toggleServer(bool value) async {
    if (value) {
      final started = await _ftpServer.startServer(
        port: 8080,
        rootPath: widget.localVfs.rootPath,
      );
      setState(() => _isServerActive = started);
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to bind server port')),
        );
      }
    } else {
      await _ftpServer.stopServer();
      setState(() => _isServerActive = false);
    }
  }

  void _startLanScan() async {
    setState(() {
      _isScanning = true;
      _scanProgress = 0.0;
      _discoveredDevices = [];
    });

    final devices = await _lanScanner.scanLocalNetwork(
      onProgress: (p) => setState(() => _scanProgress = p),
    );

    if (mounted) {
      setState(() {
        _discoveredDevices = devices;
        _isScanning = false;
      });
    }
  }

  void _showConnectionOptions(NetworkConnection conn) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(conn.name),
        message: Text('${conn.protocolName} • ${conn.host}:${conn.port}'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _openRemoteConnection(conn);
            },
            child: const Text('Connect to Server'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showAddConnectionDialog(existing: conn);
            },
            child: const Text('Edit Credentials & Drive'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              await SettingsService.instance.removeConnection(conn.id);
              if (mounted) setState(() {});
            },
            child: const Text('Remove Connection'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _openRemoteConnection(NetworkConnection conn) async {
    // If credentials are empty and not marked anonymous, ask user
    if (!conn.isAnonymous && conn.username.isEmpty) {
      _showAddConnectionDialog(existing: conn);
      return;
    }

    if (conn.protocol == ProtocolType.smb) {
      showCupertinoDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CupertinoActivityIndicator(radius: 16),
        ),
      );

      final smbVfs = SmbVfs(conn);
      try {
        await smbVfs.connect();
        if (!mounted) return;
        Navigator.pop(context); // Dismiss loading
        Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => DirectoryBrowserScreen(
              vfs: smbVfs,
              initialPath: '',
              title: conn.name,
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context); // Dismiss loading
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Connection Failed'),
            content: Text('Could not connect to ${conn.host}: ${e.toString()}'),
            actions: [
              CupertinoDialogAction(
                child: const Text('Edit Credentials'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAddConnectionDialog(existing: conn);
                },
              ),
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      }
    } else if (conn.protocol == ProtocolType.webdav) {
      final vfs = WebDavVfs(conn);
      Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => DirectoryBrowserScreen(
            vfs: vfs,
            initialPath: '/',
            title: conn.name,
          ),
        ),
      );
    } else if (conn.protocol == ProtocolType.sftp) {
      final vfs = SftpVfs(conn);
      Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => DirectoryBrowserScreen(
            vfs: vfs,
            initialPath: '/',
            title: conn.name,
          ),
        ),
      );
    }
  }

  void _showAddConnectionDialog({
    String? prefilledHost,
    int? prefilledPort,
    ProtocolType? prefilledProtocol,
    String? prefilledName,
    NetworkConnection? existing,
  }) {
    final nameController = TextEditingController(
      text: existing?.name ?? prefilledName ?? '',
    );
    final hostController = TextEditingController(
      text: existing?.host ?? prefilledHost ?? '',
    );
    final portController = TextEditingController(
      text: (existing?.port ?? prefilledPort ?? 445).toString(),
    );
    final shareController = TextEditingController(
      text: existing?.path.isNotEmpty == true ? existing!.path : '',
    );
    final userController = TextEditingController(
      text: existing?.username ?? '',
    );
    final passController = TextEditingController(
      text: existing?.password ?? '',
    );
    bool isAnonymous = existing?.isAnonymous ?? false;
    ProtocolType selectedProtocol = existing?.protocol ?? prefilledProtocol ?? ProtocolType.smb;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => DefaultTextStyle(
        style: const TextStyle(decoration: TextDecoration.none),
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: AppleColors.darkElevated,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    existing != null ? 'Edit Connection' : 'Add Network Storage',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('Save & Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final conn = NetworkConnection(
                        id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameController.text.trim().isNotEmpty ? nameController.text.trim() : hostController.text.trim(),
                        protocol: selectedProtocol,
                        host: hostController.text.trim(),
                        port: int.tryParse(portController.text) ?? NetworkConnection.defaultPortFor(selectedProtocol),
                        path: shareController.text.trim(),
                        username: isAnonymous ? '' : userController.text.trim(),
                        password: isAnonymous ? '' : passController.text.trim(),
                        isAnonymous: isAnonymous,
                        lastConnected: DateTime.now(),
                      );

                      await SettingsService.instance.saveConnection(conn);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        setState(() {});
                        _openRemoteConnection(conn);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Protocol Picker
              SizedBox(
                width: double.infinity,
                child: CupertinoSegmentedControl<ProtocolType>(
                  groupValue: selectedProtocol,
                  selectedColor: AppleColors.systemBlue,
                  unselectedColor: AppleColors.darkCard,
                  borderColor: AppleColors.borderStroke,
                  children: const {
                    ProtocolType.smb: Text('SMB (Windows/NAS)', style: TextStyle(fontSize: 12)),
                    ProtocolType.webdav: Text('WebDAV', style: TextStyle(fontSize: 12)),
                    ProtocolType.sftp: Text('SFTP', style: TextStyle(fontSize: 12)),
                    ProtocolType.ftp: Text('FTP', style: TextStyle(fontSize: 12)),
                  },
                  onValueChanged: (val) {
                    setDialogState(() {
                      selectedProtocol = val;
                      portController.text = NetworkConnection.defaultPortFor(val).toString();
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              CupertinoTextField(
                controller: nameController,
                placeholder: 'Display Name (e.g. ZimaOS, Synology)',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: CupertinoTextField(
                      controller: hostController,
                      placeholder: 'Server IP (e.g. 192.168.1.100)',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: CupertinoTextField(
                      controller: portController,
                      placeholder: 'Port',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: shareController,
                placeholder: 'Shared Folder (optional - leave blank to list all drives)',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tip: For ZimaOS/CasaOS/Linux, enter your user credentials to access all hard drives and storage pools. Leave blank to explore all shares.',
                style: TextStyle(color: AppleColors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 16),
              // Anonymous Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Anonymous / Guest Access', style: TextStyle(color: Colors.white, fontSize: 14)),
                  CupertinoSwitch(
                    value: isAnonymous,
                    activeTrackColor: AppleColors.systemBlue,
                    onChanged: (val) => setDialogState(() => isAnonymous = val),
                  ),
                ],
              ),
              if (!isAnonymous) ...[
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: userController,
                  placeholder: 'Username',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: passController,
                  placeholder: 'Password',
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
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

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      body: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text('Network', style: TextStyle(color: isDark ? Colors.white : AppleColors.textPrimaryLight)),
            backgroundColor: isDark ? const Color(0xCC000000) : const Color(0xCCF2F2F7),
            border: null,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Access From PC (FTP / HTTP Wireless Server) Card
                AppleCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(CupertinoIcons.desktopcomputer, color: AppleColors.systemBlue, size: 28),
                              SizedBox(width: 12),
                              Text(
                                'Access from PC',
                                style: TextStyle(
                                  color: AppleColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          CupertinoSwitch(
                            value: _isServerActive,
                            activeTrackColor: AppleColors.systemBlue,
                            onChanged: _toggleServer,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isServerActive
                            ? 'Open this URL in your PC browser on the same Wi-Fi:'
                            : 'Manage your device files wirelessly from a PC browser.',
                        style: const TextStyle(color: AppleColors.textSecondary, fontSize: 13),
                      ),
                      if (_isServerActive) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppleColors.pureBlack,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppleColors.systemBlue, width: 1),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _ftpServer.serverUrl,
                                style: const TextStyle(
                                  color: AppleColors.systemTeal,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                child: const Icon(CupertinoIcons.doc_on_clipboard, color: AppleColors.systemBlue),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _ftpServer.serverUrl));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Server URL copied to clipboard!')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Network Storage Header + Add Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Network Storage & Servers',
                      style: TextStyle(
                        color: AppleColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => _showAddConnectionDialog(),
                      child: const Row(
                        children: [
                          Icon(CupertinoIcons.plus_circle_fill, size: 16, color: AppleColors.systemBlue),
                          SizedBox(width: 4),
                          Text('Add', style: TextStyle(color: AppleColors.systemBlue, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Saved Network Locations
                ..._savedConnections.map((conn) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppleCard(
                      onTap: () => _openRemoteConnection(conn),
                      onLongPress: () => _showConnectionOptions(conn),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppleColors.systemBlue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(CupertinoIcons.archivebox_fill, color: AppleColors.systemBlue, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  conn.name,
                                  style: const TextStyle(
                                    color: AppleColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${conn.protocolName} • ${conn.host}:${conn.port}${conn.cleanSharePath.isNotEmpty ? '/${conn.cleanSharePath}' : ''}',
                                  style: const TextStyle(color: AppleColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(CupertinoIcons.ellipsis_circle, color: AppleColors.textSecondary, size: 22),
                            tooltip: 'Connection options',
                            onPressed: () => _showConnectionOptions(conn),
                          ),
                          const Icon(CupertinoIcons.chevron_right, size: 16, color: AppleColors.textTertiary),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // LAN Auto Scan Section
                AppleCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Scan Local Network (LAN)',
                            style: TextStyle(
                              color: AppleColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            color: AppleColors.darkElevated,
                            borderRadius: BorderRadius.circular(16),
                            onPressed: _isScanning ? null : _startLanScan,
                            child: Text(
                              _isScanning ? 'Scanning...' : 'Scan',
                              style: const TextStyle(fontSize: 13, color: AppleColors.systemBlue),
                            ),
                          ),
                        ],
                      ),
                      if (_isScanning) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _scanProgress,
                            backgroundColor: AppleColors.darkElevated,
                            valueColor: const AlwaysStoppedAnimation(AppleColors.systemBlue),
                          ),
                        ),
                      ],
                      if (_discoveredDevices.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Discovered Devices:',
                          style: TextStyle(color: AppleColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        ..._discoveredDevices.map((dev) {
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(CupertinoIcons.antenna_radiowaves_left_right, color: AppleColors.systemGreen),
                            title: Text(dev.hostname, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: Text('${dev.serviceType} on ${dev.ip}:${dev.port}', style: const TextStyle(color: AppleColors.textSecondary, fontSize: 11)),
                            trailing: CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              color: AppleColors.systemBlueSubtle,
                              borderRadius: BorderRadius.circular(12),
                              child: const Text('Connect', style: TextStyle(color: AppleColors.systemBlue, fontSize: 13, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                // Prompt credentials for this discovered device!
                                _showAddConnectionDialog(
                                  prefilledHost: dev.ip,
                                  prefilledPort: dev.port,
                                  prefilledProtocol: dev.serviceType.contains('SMB') ? ProtocolType.smb : ProtocolType.webdav,
                                  prefilledName: dev.hostname,
                                );
                              },
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
