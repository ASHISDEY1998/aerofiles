import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/network_connection.dart';
import '../../services/network/lan_scanner_service.dart';
import '../../services/settings_service.dart';
import '../../services/vfs/local_vfs.dart';
import '../../services/vfs/sftp_vfs.dart';
import '../../services/vfs/smb_vfs.dart';
import '../../services/vfs/webdav_vfs.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/apple_card.dart';
import '../local/directory_browser_screen.dart';
import 'aerolink_mesh_view.dart';

class NetworkTab extends StatefulWidget {
  final LocalVfs localVfs;

  const NetworkTab({super.key, required this.localVfs});

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  final _lanScanner = LanScannerService();

  bool _isScanning = false;
  double _scanProgress = 0.0;
  List<DiscoveredDevice> _discoveredDevices = [];

  // Live Connection Status Tracking
  final Map<String, bool?> _connectionStatus = {};
  final Map<String, int?> _pingLatencies = {};
  bool _isPingingAll = false;

  List<NetworkConnection> get _savedConnections => SettingsService.instance.savedConnections;

  @override
  void initState() {
    super.initState();
    _pingAllConnections();
  }

  Future<void> _pingAllConnections() async {
    if (_isPingingAll) return;
    _isPingingAll = true;
    final conns = _savedConnections;
    for (final conn in conns) {
      if (!mounted) break;
      setState(() {
        _connectionStatus[conn.id] = null;
      });
      final latency = await LanScannerService.pingHost(conn.host, conn.port);
      if (mounted) {
        setState(() {
          _connectionStatus[conn.id] = (latency != null);
          _pingLatencies[conn.id] = latency;
        });
      }
    }
    _isPingingAll = false;
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
              _connectionStatus.remove(conn.id);
              _pingLatencies.remove(conn.id);
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
                        _pingAllConnections();
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
                // AeroLink Mesh - Private Device-to-Device Sharing & Zero-Download Streaming
                AeroLinkMeshView(localVfs: widget.localVfs),

                const SizedBox(height: 24),

                // Network Storage Header + Add & Refresh Buttons
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
                    Row(
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.only(right: 6),
                          onPressed: _isPingingAll ? null : _pingAllConnections,
                          child: _isPingingAll
                              ? const CupertinoActivityIndicator(radius: 8)
                              : const Icon(CupertinoIcons.arrow_clockwise, size: 16, color: AppleColors.systemBlue),
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
                  ],
                ),

                const SizedBox(height: 10),

                // Saved Network Locations
                ..._savedConnections.map((conn) {
                  final status = _connectionStatus[conn.id];
                  final latency = _pingLatencies[conn.id];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppleCard(
                      onTap: () => _openRemoteConnection(conn),
                      onLongPress: () => _showConnectionOptions(conn),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppleColors.systemBlue.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  conn.protocol == ProtocolType.sftp
                                      ? Icons.terminal_rounded
                                      : conn.protocol == ProtocolType.webdav
                                          ? CupertinoIcons.cloud_fill
                                          : conn.protocol == ProtocolType.ftp
                                              ? CupertinoIcons.folder_fill_badge_person_crop
                                              : CupertinoIcons.archivebox_fill,
                                  color: AppleColors.systemBlue,
                                  size: 24,
                                ),
                              ),
                              // Live status dot
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: status == true
                                        ? AppleColors.systemGreen
                                        : status == false
                                            ? Colors.white24
                                            : AppleColors.systemBlueSubtle,
                                    border: Border.all(color: Colors.black, width: 2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        conn.name,
                                        style: const TextStyle(
                                          color: AppleColors.textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (status == true && latency != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: AppleColors.systemGreen.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${latency}ms',
                                          style: const TextStyle(
                                            color: AppleColors.systemGreen,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      status == true
                                          ? 'Online • '
                                          : status == false
                                              ? 'Offline • '
                                              : 'Checking • ',
                                      style: TextStyle(
                                        color: status == true
                                            ? AppleColors.systemGreen
                                            : AppleColors.textTertiary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        '${conn.protocolName} • ${conn.host}:${conn.port}${conn.cleanSharePath.isNotEmpty ? '/${conn.cleanSharePath}' : ''}',
                                        style: const TextStyle(color: AppleColors.textSecondary, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
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

                if (_savedConnections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppleCard(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.antenna_radiowaves_left_right, color: AppleColors.textSecondary.withValues(alpha: 0.6), size: 28),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('No Saved Servers', style: TextStyle(color: AppleColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                                SizedBox(height: 2),
                                Text('Tap "+ Add" or scan your local network below.', style: TextStyle(color: AppleColors.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

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
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Scan Local Network (LAN)',
                                style: TextStyle(
                                  color: AppleColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Auto-detect SMB, NAS, and PC shares on Wi-Fi',
                                style: TextStyle(color: AppleColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            color: AppleColors.systemBlue,
                            borderRadius: BorderRadius.circular(16),
                            onPressed: _isScanning ? null : _startLanScan,
                            child: Text(
                              _isScanning ? 'Scanning...' : 'Scan LAN',
                              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      if (_isScanning) ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Probing subnet...', style: TextStyle(color: AppleColors.textSecondary, fontSize: 12)),
                            Text('${(_scanProgress * 100).toInt()}%', style: const TextStyle(color: AppleColors.systemBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
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
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Discovered Devices (${_discoveredDevices.length}):',
                              style: const TextStyle(color: AppleColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            const Text('1-Tap Connect', style: TextStyle(color: AppleColors.systemBlue, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._discoveredDevices.map((dev) {
                          final isSmb = dev.serviceType.contains('SMB');
                          final isSftp = dev.serviceType.contains('SFTP');
                          final isWeb = dev.serviceType.contains('WebDAV') || dev.serviceType.contains('HTTP');

                          final icon = isSmb
                              ? CupertinoIcons.desktopcomputer
                              : isSftp
                                  ? Icons.terminal_rounded
                                  : isWeb
                                      ? CupertinoIcons.cloud_fill
                                      : CupertinoIcons.folder_fill_badge_person_crop;

                          final color = isSmb
                              ? AppleColors.systemBlue
                              : isSftp
                                  ? AppleColors.systemPurple
                                  : isWeb
                                      ? AppleColors.systemOrange
                                      : AppleColors.systemGreen;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppleColors.darkElevated,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12, width: 0.5),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(icon, color: color, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          dev.hostname,
                                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              '${dev.serviceType} • ${dev.ip}:${dev.port}',
                                              style: const TextStyle(color: AppleColors.textSecondary, fontSize: 11),
                                            ),
                                            if (dev.pingMs != null) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '(${dev.pingMs}ms)',
                                                style: const TextStyle(color: AppleColors.systemGreen, fontSize: 11),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    color: AppleColors.systemBlueSubtle,
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Text(
                                      'Connect',
                                      style: TextStyle(color: AppleColors.systemBlue, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () {
                                      _showAddConnectionDialog(
                                        prefilledHost: dev.ip,
                                        prefilledPort: dev.port,
                                        prefilledProtocol: isSftp
                                            ? ProtocolType.sftp
                                            : isWeb
                                                ? ProtocolType.webdav
                                                : dev.serviceType.contains('FTP')
                                                    ? ProtocolType.ftp
                                                    : ProtocolType.smb,
                                        prefilledName: dev.hostname,
                                      );
                                    },
                                  ),
                                ],
                              ),
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
