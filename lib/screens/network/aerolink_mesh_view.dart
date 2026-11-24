import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/aerolink_models.dart';
import '../../services/network/aerolink_service.dart';
import '../../services/vfs/aerolink_vfs.dart';
import '../../services/vfs/local_vfs.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/apple_card.dart';
import '../local/directory_browser_screen.dart';
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

  Future<void> _handleDeviceTap(AeroLinkDevice device) async {
    if (!device.isOnline) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(device.deviceName),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This device is currently offline.\n\nMake sure ${device.deviceName} is connected to the same Wi-Fi network and has AeroLink enabled.',
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

    // If device is not yet paired, trigger 6-digit PIN pairing dialog
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
                      Row(
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
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AeroLink Mesh',
                                style: TextStyle(
                                  color: AppleColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Private Device-to-Device Sharing',
                                style: TextStyle(color: AppleColors.textSecondary, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                      CupertinoSwitch(
                        value: isActive,
                        activeTrackColor: AppleColors.systemBlue,
                        onChanged: _toggleSharing,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isActive
                        ? 'Streaming active on local Wi-Fi. Files can be streamed on-the-fly without downloading.'
                        : 'Enable AeroLink to share folders and stream videos directly to your other AeroFiles devices.',
                    style: const TextStyle(color: AppleColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          isActive
                              ? 'Sharing ${shares.length} folder${shares.length == 1 ? '' : 's'} as "${_service.deviceName}"'
                              : '${shares.length} folder${shares.length == 1 ? '' : 's'} configured',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isActive ? AppleColors.systemGreen : AppleColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        color: AppleColors.systemBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        onPressed: _openSharesSheet,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.gear_alt, size: 14, color: AppleColors.systemBlue),
                            const SizedBox(width: 4),
                            Text(
                              'PIN: ${_service.pairingPin}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppleColors.systemBlue),
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
            ValueListenableBuilder<List<AeroLinkDevice>>(
              valueListenable: _service.nearbyDevices,
              builder: (context, devices, _) {
                final onlineCount = devices.where((d) => d.isOnline).length;
                return Text(
                  onlineCount > 0 ? '$onlineCount online' : 'Scanning...',
                  style: TextStyle(
                    fontSize: 11,
                    color: onlineCount > 0 ? AppleColors.systemGreen : AppleColors.textTertiary,
                    fontWeight: FontWeight.w500,
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
                    const Icon(CupertinoIcons.antenna_radiowaves_left_right, color: AppleColors.systemBlue, size: 32),
                    const SizedBox(height: 10),
                    Text(
                      'Looking for AeroFiles devices on your Wi-Fi...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Devices with AeroLink enabled will automatically appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
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
                            if (dev.isOnline && !dev.isPaired)
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                minimumSize: Size.zero,
                                color: AppleColors.systemBlue,
                                borderRadius: BorderRadius.circular(12),
                                onPressed: () => _handleDeviceTap(dev),
                                child: const Text(
                                  'Pair',
                                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              )
                            else
                              Icon(
                                CupertinoIcons.chevron_right,
                                size: 16,
                                color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
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
