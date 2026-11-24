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
  String _localIp = '';

  @override
  void initState() {
    super.initState();
    _loadIp();
  }

  void _loadIp() async {
    final ip = await _service.getLocalIp();
    if (mounted) setState(() => _localIp = ip);
  }

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
    final pin = _service.pairingPin;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Grabber bar
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

                  // Header with Done button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
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
                            ),
                            alignment: Alignment.center,
                            child: const Icon(CupertinoIcons.folder_fill_badge_person_crop, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AeroLink Mesh Settings',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                ),
                              ),
                              Text(
                                'Private Wi-Fi Streaming & Sharing',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        borderRadius: BorderRadius.circular(14),
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        child: Text(
                          'Done',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Same Network Wi-Fi Status Pill
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppleColors.systemBlue.withValues(alpha: isDark ? 0.12 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppleColors.systemBlue.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.wifi, color: AppleColors.systemBlue, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Same Network Required',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                    ),
                                  ),
                                  if (_localIp.isNotEmpty && _localIp != '127.0.0.1') ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '($_localIp)',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppleColors.systemBlue,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Other devices must be connected to this same Wi-Fi network to discover and stream.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 1. Device Name Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              CupertinoIcons.device_phone_portrait,
                              color: AppleColors.systemBlue,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
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
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          color: AppleColors.systemBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          onPressed: _promptEditDeviceName,
                          child: const Row(
                            children: [
                              Icon(CupertinoIcons.pencil, size: 12, color: AppleColors.systemBlue),
                              SizedBox(width: 4),
                              Text('Edit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppleColors.systemBlue)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. 6-Digit Pairing PIN Card (New Apple-Style Digit Boxes)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
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
                                  'Enter this PIN on other devices to pair',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                  ),
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
                              child: const Row(
                                children: [
                                  Icon(CupertinoIcons.arrow_2_circlepath, size: 12, color: AppleColors.systemBlue),
                                  SizedBox(width: 4),
                                  Text('Regenerate', style: TextStyle(fontSize: 12, color: AppleColors.systemBlue, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Beautiful 6 PIN Boxes
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (int i = 0; i < 6; i++)
                              Container(
                                width: 44,
                                height: 50,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppleColors.systemBlue.withValues(alpha: 0.35),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  i < pin.length ? pin[i] : '•',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: AppleColors.systemGreen,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 3. Shared Folders Section
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
                          'No folders shared yet. Tap "+ Add Folder" to designate directories for remote streaming.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight),
                        ),
                      ),
                    )
                  else
                    for (final s in shares)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppleColors.systemBlue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(CupertinoIcons.folder_fill, color: AppleColors.systemBlue, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                    ),
                                  ),
                                  Text(
                                    s.localPath,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                  const SizedBox(height: 12),

                  // Privacy Note
                  Center(
                    child: Text(
                      '🔒 Only devices on your Wi-Fi entering this 6-digit PIN can stream or browse.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
