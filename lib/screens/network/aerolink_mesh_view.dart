import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/aerolink_models.dart';
import '../../services/network/aerolink_service.dart';
import '../../services/vfs/aerolink_vfs.dart';
import '../../services/vfs/local_vfs.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/apple_card.dart';
import '../local/directory_browser_screen.dart';
import 'aerolink_about_sheet.dart';
import 'aerolink_dialogs.dart';

class AeroLinkMeshView extends StatefulWidget {
  final LocalVfs localVfs;

  const AeroLinkMeshView({super.key, required this.localVfs});

  @override
  State<AeroLinkMeshView> createState() => _AeroLinkMeshViewState();
}

class _AeroLinkMeshViewState extends State<AeroLinkMeshView> {
  final _service = AeroLinkService.instance;

  @override
  void initState() {
    super.initState();
    _service.init();
  }

  void _toggleSharing(bool value) async {
    if (value) {
      final ok = await _service.startSharing();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start AeroLink. Check Wi-Fi connection.')),
        );
      }
    } else {
      await _service.stopSharing();
    }
  }

  void _openSharesSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => AeroLinkSharesSheet(localVfs: widget.localVfs),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openAboutSheet() {
    AeroLinkAboutSheet.show(context);
  }

  Future<void> _handleDeviceTap(AeroLinkDevice device) async {
    if (!device.isOnline) {
      // Direct ping to check if peer is reachable
      final ok = await _service.pingDevice(device);
      if (!ok && mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: Text(device.deviceName),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'This device is currently unreachable.\n\nMake sure ${device.deviceName} is connected to this Wi-Fi and has AeroLink enabled.',
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
        return;
      }
    }

    // If device is not yet paired, trigger 6-digit PIN pairing dialog
    if (!mounted) return;
    if (!device.isPaired) {
      final paired = await showCupertinoDialog<bool>(
        context: context,
        builder: (_) => AeroLinkPairDialog(device: device),
      );

      if (paired != true || !mounted) return;
    }

    if (!mounted) return;

    // Open remote device in DirectoryBrowserScreen using AeroLinkVfs!
    final vfs = AeroLinkVfs(device: device, authToken: device.authToken!);
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => DirectoryBrowserScreen(
          vfs: vfs,
          initialPath: '/',
          title: device.deviceName,
        ),
      ),
    );
  }

  void _showDeviceOptions(AeroLinkDevice device) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(device.deviceName),
        message: Text('${device.ip} • ${device.subtitle}'),
        actions: [
          if (device.isOnline && device.isPaired)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _handleDeviceTap(device);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.folder_badge_person_crop, size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Browse Shared Folders',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (device.isOnline && !device.isPaired)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _handleDeviceTap(device);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.lock_shield, size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Pair with PIN',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (device.isPaired)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(ctx);
                _service.unpairDevice(device.deviceId);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Unpaired from ${device.deviceName}. Next connection will require PIN.')),
                );
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.lock_open, size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Forget Pairing (Unpair)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _service.forgetDevice(device.deviceId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Removed ${device.deviceName} from list.')),
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.trash, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Forget & Remove Device',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(ctx),
        ),
      ),
    );
  }

  IconData _getDeviceIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('tab') || lower.contains('pad')) {
      return CupertinoIcons.device_phone_landscape;
    } else if (lower.contains('tv') || lower.contains('box')) {
      return CupertinoIcons.tv;
    } else if (lower.contains('mac') || lower.contains('book') || lower.contains('laptop') || lower.contains('pc')) {
      return CupertinoIcons.device_laptop;
    }
    return CupertinoIcons.device_phone_portrait;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Host Device Sharing Card
        ValueListenableBuilder<bool>(
          valueListenable: _service.isSharingActive,
          builder: (context, isActive, _) {
            final shares = _service.sharedFolders;
            return AppleCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppleColors.systemBlue, AppleColors.systemIndigo],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(CupertinoIcons.folder_fill_badge_person_crop, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'AeroLink Mesh',
                                        style: TextStyle(
                                          color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(width: 6),
                                      CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        onPressed: _openAboutSheet,
                                        child: const Icon(
                                          CupertinoIcons.info_circle,
                                          size: 17,
                                          color: AppleColors.systemBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    isActive ? 'Active on Local Wi-Fi' : 'Direct Device-to-Device Sharing',
                                    style: TextStyle(
                                      color: isActive ? AppleColors.systemGreen : AppleColors.textSecondary,
                                      fontSize: 11,
                                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      CupertinoSwitch(
                        value: isActive,
                        activeTrackColor: AppleColors.systemBlue,
                        onChanged: _toggleSharing,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          isActive
                              ? '${_service.deviceName} • ${shares.length} shared'
                              : 'Transfer and stream without cloud or internet',
                          style: TextStyle(
                            fontSize: 12,
                            color: isActive ? (isDark ? Colors.white70 : Colors.black87) : AppleColors.textSecondary,
                            fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(12),
                        onPressed: _openSharesSheet,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.slider_horizontal_3, size: 12, color: AppleColors.systemBlue),
                            const SizedBox(width: 5),
                            Text(
                              'PIN: ${_service.pairingPin}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppleColors.systemBlue),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // 2. Discovered Nearby Devices Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Nearby AeroFiles Devices',
              style: TextStyle(
                color: AppleColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _service.isScanning,
              builder: (context, isScanning, _) {
                if (isScanning) {
                  return ValueListenableBuilder<int>(
                    valueListenable: _service.scanSecondsRemaining,
                    builder: (context, seconds, _) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CupertinoActivityIndicator(radius: 6),
                          const SizedBox(width: 6),
                          Text(
                            'Scanning (${seconds}s)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppleColors.systemBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            onPressed: _service.stopScan,
                            child: const Text(
                              'Stop',
                              style: TextStyle(fontSize: 12, color: AppleColors.systemRed, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                }

                return CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  borderRadius: BorderRadius.circular(10),
                  color: AppleColors.systemBlue.withValues(alpha: 0.12),
                  onPressed: () => _service.startScan(durationSeconds: 30),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.arrow_clockwise, size: 12, color: AppleColors.systemBlue),
                      SizedBox(width: 4),
                      Text(
                        'Scan (30s)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppleColors.systemBlue),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 10),

        // 3. Discovered Devices List
        ValueListenableBuilder<List<AeroLinkDevice>>(
          valueListenable: _service.nearbyDevices,
          builder: (context, devices, _) {
            if (devices.isEmpty) {
              return ValueListenableBuilder<bool>(
                valueListenable: _service.isScanning,
                builder: (context, isScanning, _) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? AppleColors.darkCard : AppleColors.lightCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isScanning) ...[
                          const CupertinoActivityIndicator(radius: 12),
                          const SizedBox(height: 10),
                          ValueListenableBuilder<int>(
                            valueListenable: _service.scanSecondsRemaining,
                            builder: (context, seconds, _) {
                              return Text(
                                'Searching for devices... (${seconds}s)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Looking for AeroFiles devices on this Wi-Fi network.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                            ),
                          ),
                        ] else ...[
                          Icon(CupertinoIcons.antenna_radiowaves_left_right, color: AppleColors.systemBlue.withValues(alpha: 0.8), size: 30),
                          const SizedBox(height: 8),
                          Text(
                            'No Devices Nearby',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Turn on AeroLink on your other devices on this Wi-Fi to connect.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            }

            return Column(
              children: [
                for (final dev in devices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Opacity(
                      opacity: dev.isOnline ? 1.0 : 0.65,
                      child: AppleCard(
                        onTap: () => _handleDeviceTap(dev),
                        onLongPress: () => _showDeviceOptions(dev),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: dev.isOnline
                                    ? AppleColors.systemBlue.withValues(alpha: 0.15)
                                    : (isDark ? Colors.white10 : Colors.black12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                _getDeviceIcon(dev.deviceName),
                                color: dev.isOnline ? AppleColors.systemBlue : Colors.grey,
                                size: 24,
                              ),
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
                                          dev.deviceName,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: dev.isOnline ? AppleColors.systemGreen : Colors.grey,
                                        ),
                                      ),
                                      if (dev.isPaired) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppleColors.systemGreen.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'PAIRED',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: AppleColors.systemGreen,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dev.subtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: dev.isOnline
                                          ? (isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight)
                                          : AppleColors.systemRed,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (dev.isOnline && !dev.isPaired) ...[
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    minimumSize: Size.zero,
                                    color: AppleColors.systemBlue,
                                    borderRadius: BorderRadius.circular(10),
                                    onPressed: () => _handleDeviceTap(dev),
                                    child: const Text(
                                      'Pair',
                                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                CupertinoButton(
                                  padding: const EdgeInsets.all(8),
                                  minimumSize: Size.zero,
                                  onPressed: () => _showDeviceOptions(dev),
                                  child: Icon(
                                    CupertinoIcons.ellipsis,
                                    size: 18,
                                    color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
