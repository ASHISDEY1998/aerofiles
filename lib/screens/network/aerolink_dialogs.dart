import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/aerolink_models.dart';
import '../../services/network/aerolink_service.dart';
import '../../services/vfs/local_vfs.dart';
import '../../theme/apple_theme.dart';

class AeroLinkPairDialog extends StatefulWidget {
  final AeroLinkDevice device;

  const AeroLinkPairDialog({super.key, required this.device});

  @override
  State<AeroLinkPairDialog> createState() => _AeroLinkPairDialogState();
}

class _AeroLinkPairDialogState extends State<AeroLinkPairDialog> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handlePair() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'Enter the 6-digit PIN');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final ok = await AeroLinkService.instance.pairWithDevice(widget.device, pin);

    if (mounted) {
      if (ok) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Pairing failed. Check PIN and Wi-Fi connection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CupertinoAlertDialog(
      title: Column(
        children: [
          const Icon(CupertinoIcons.lock_shield_fill, color: AppleColors.systemBlue, size: 36),
          const SizedBox(height: 8),
          Text('Connect to ${widget.device.deviceName}'),
        ],
      ),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the 6-digit PIN displayed on ${widget.device.deviceName} under AeroLink Mesh.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 14),
            CupertinoTextField(
              controller: _pinController,
              placeholder: '6-digit PIN (e.g. 123456)',
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: const TextStyle(fontSize: 20, letterSpacing: 4, fontWeight: FontWeight.bold),
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : Colors.black12,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppleColors.systemRed, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _isLoading ? null : _handlePair,
          child: _isLoading ? const CupertinoActivityIndicator(radius: 8) : const Text('Pair & Connect'),
        ),
      ],
    );
  }
}

class AeroLinkSharesSheet extends StatefulWidget {
  final LocalVfs localVfs;

  const AeroLinkSharesSheet({super.key, required this.localVfs});

  @override
  State<AeroLinkSharesSheet> createState() => _AeroLinkSharesSheetState();
}

class _AeroLinkSharesSheetState extends State<AeroLinkSharesSheet> {
  final _service = AeroLinkService.instance;

  void _showAddFolderPicker() {
    final root = widget.localVfs.rootPath;
    final candidates = [
      {'name': 'Movies', 'path': p.join(root, 'Movies')},
      {'name': 'Download', 'path': p.join(root, 'Download')},
      {'name': 'Pictures', 'path': p.join(root, 'Pictures')},
      {'name': 'DCIM (Camera)', 'path': p.join(root, 'DCIM')},
      {'name': 'Music', 'path': p.join(root, 'Music')},
      {'name': 'Documents', 'path': p.join(root, 'Documents')},
    ];

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Select a Folder to Share Privately'),
        message: const Text('Only paired AeroFiles devices will be able to stream from this folder.'),
        actions: [
          for (final c in candidates)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                final dir = Directory(c['path']!);
                if (!dir.existsSync()) {
                  try {
                    dir.createSync(recursive: true);
                  } catch (_) {}
                }
                _service.addShare(name: c['name']!, localPath: c['path']!);
                setState(() {});
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(CupertinoIcons.folder_badge_plus, size: 18),
                  const SizedBox(width: 8),
                  Text(c['name']!),
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

  void _promptEditDeviceName() {
    final controller = TextEditingController(text: _service.deviceName);
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Device Sharing Name'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Device Name (e.g. Living Room Tablet)',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Save'),
            onPressed: () {
              Navigator.pop(ctx);
              _service.setDeviceName(controller.text);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shares = _service.sharedFolders;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sheet grabber
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppleColors.systemBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(CupertinoIcons.folder_fill_badge_person_crop, color: AppleColors.systemBlue, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AeroLink Shared Folders',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Private Wi-Fi Streaming Mesh',
                          style: TextStyle(fontSize: 12, color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight),
                        ),
                      ],
                    ),
                  ],
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Device Name & Pairing PIN Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DEVICE NAME',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _service.deviceName,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: _promptEditDeviceName,
                        child: const Icon(CupertinoIcons.pencil_circle_fill, size: 22, color: AppleColors.systemBlue),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '6-DIGIT PAIRING PIN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _service.pairingPin,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3, color: AppleColors.systemGreen),
                          ),
                        ],
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        color: AppleColors.systemBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        onPressed: () {
                          _service.regeneratePin();
                          setState(() {});
                        },
                        child: const Text('Regenerate', style: TextStyle(fontSize: 12, color: AppleColors.systemBlue, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Shared Folders List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SHARED FOLDERS (${shares.length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: _showAddFolderPicker,
                  child: const Row(
                    children: [
                      Icon(CupertinoIcons.plus_circle_fill, size: 16, color: AppleColors.systemBlue),
                      SizedBox(width: 4),
                      Text('Add Folder', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppleColors.systemBlue)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (shares.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'No folders shared yet. Tap "+ Add Folder" to share movies or downloads across your devices.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight),
                  ),
                ),
              )
            else
              for (final s in shares)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.folder_fill, color: AppleColors.systemBlue, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            Text(s.localPath, style: TextStyle(fontSize: 11, color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        child: const Icon(CupertinoIcons.trash, color: AppleColors.systemRed, size: 18),
                        onPressed: () {
                          _service.removeShare(s.id);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
