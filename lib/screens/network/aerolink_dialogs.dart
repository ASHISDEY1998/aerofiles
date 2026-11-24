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
    final quickFolders = [
      {'name': 'Movies', 'path': p.join(root, 'Movies')},
      {'name': 'Download', 'path': p.join(root, 'Download')},
      {'name': 'Pictures', 'path': p.join(root, 'Pictures')},
      {'name': 'DCIM (Camera)', 'path': p.join(root, 'DCIM')},
      {'name': 'Documents', 'path': p.join(root, 'Documents')},
      {'name': 'Music', 'path': p.join(root, 'Music')},
    ];

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Add Shared Folder or File'),
        message: const Text('Share any folder or individual file on your device with other AeroFiles devices.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _openStoragePicker(AeroLinkPickerMode.folder);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(CupertinoIcons.folder_badge_plus, size: 18, color: AppleColors.systemBlue),
                SizedBox(width: 8),
                Text('Browse & Pick Any Folder...', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _openStoragePicker(AeroLinkPickerMode.file);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(CupertinoIcons.doc_fill, size: 18, color: AppleColors.systemGreen),
                SizedBox(width: 8),
                Text('Browse & Pick Any File...', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          for (final c in quickFolders)
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
                  const Icon(CupertinoIcons.folder, size: 16),
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

  void _openStoragePicker(AeroLinkPickerMode mode) {
    showCupertinoModalPopup<String>(
      context: context,
      builder: (_) => AeroLinkStoragePickerModal(
        localVfs: widget.localVfs,
        mode: mode,
      ),
    ).then((selectedPath) {
      if (selectedPath != null && selectedPath.isNotEmpty) {
        final name = p.basename(selectedPath);
        _service.addShare(name: name, localPath: selectedPath);
        if (mounted) setState(() {});
      }
    });
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

                  // 3. Shared Folders & Files Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SHARED ITEMS (${shares.length})',
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
                            Text('Add Item', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppleColors.systemBlue)),
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
                          'No items shared yet. Tap "+ Add Item" to select any folder or file to share.',
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
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: (s.isFile ? AppleColors.systemGreen : AppleColors.systemBlue).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                s.isFile ? CupertinoIcons.doc_fill : CupertinoIcons.folder_fill,
                                color: s.isFile ? AppleColors.systemGreen : AppleColors.systemBlue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          s.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (s.isFile ? AppleColors.systemGreen : AppleColors.systemBlue).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          s.isFile ? 'FILE' : 'FOLDER',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: s.isFile ? AppleColors.systemGreen : AppleColors.systemBlue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
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

enum AeroLinkPickerMode { folder, file }

class AeroLinkStoragePickerModal extends StatefulWidget {
  final LocalVfs localVfs;
  final AeroLinkPickerMode mode;

  const AeroLinkStoragePickerModal({
    super.key,
    required this.localVfs,
    required this.mode,
  });

  @override
  State<AeroLinkStoragePickerModal> createState() => _AeroLinkStoragePickerModalState();
}

class _AeroLinkStoragePickerModalState extends State<AeroLinkStoragePickerModal> {
  late String _currentPath;
  List<FileSystemEntity> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.localVfs.rootPath;
    _loadDirectory();
  }

  void _loadDirectory() {
    setState(() => _isLoading = true);
    try {
      final dir = Directory(_currentPath);
      if (dir.existsSync()) {
        final list = dir.listSync(followLinks: false);
        final visible = list.where((e) => !p.basename(e.path).startsWith('.')).toList();
        visible.sort((a, b) {
          final isADir = a is Directory;
          final isBDir = b is Directory;
          if (isADir && !isBDir) return -1;
          if (!isADir && isBDir) return 1;
          return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
        });
        _entries = visible;
      } else {
        _entries = [];
      }
    } catch (_) {
      _entries = [];
    }
    setState(() => _isLoading = false);
  }

  void _navigateUp() {
    final parent = p.dirname(_currentPath);
    if (parent.startsWith(widget.localVfs.rootPath) || parent == widget.localVfs.rootPath) {
      _currentPath = parent;
      _loadDirectory();
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  IconData _getFileIcon(String ext) {
    switch (ext.toLowerCase()) {
      case '.mp4':
      case '.mkv':
      case '.mov':
      case '.avi':
      case '.webm':
        return CupertinoIcons.film_fill;
      case '.mp3':
      case '.flac':
      case '.m4a':
      case '.wav':
      case '.aac':
        return CupertinoIcons.music_note_2;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
      case '.gif':
        return CupertinoIcons.photo_fill;
      case '.pdf':
      case '.doc':
      case '.docx':
      case '.txt':
        return CupertinoIcons.doc_text_fill;
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return CupertinoIcons.archivebox_fill;
      case '.apk':
        return CupertinoIcons.app_badge_fill;
      default:
        return CupertinoIcons.doc_fill;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canGoUp = _currentPath != widget.localVfs.rootPath && _currentPath.startsWith(widget.localVfs.rootPath);
    final title = widget.mode == AeroLinkPickerMode.folder ? 'Select Folder to Share' : 'Select File to Share';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 650),
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
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                // Top Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (canGoUp)
                          CupertinoButton(
                            padding: const EdgeInsets.only(right: 8),
                            minimumSize: Size.zero,
                            onPressed: _navigateUp,
                            child: const Row(
                              children: [
                                Icon(CupertinoIcons.chevron_left, size: 18),
                                Text('Up', style: TextStyle(fontSize: 14)),
                              ],
                            ),
                          ),
                        Text(
                          title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Current Path Breadcrumb Bar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.folder, size: 14, color: AppleColors.systemBlue),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _currentPath,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Entity list
                Expanded(
                  child: _isLoading
                      ? const Center(child: CupertinoActivityIndicator(radius: 12))
                      : _entries.isEmpty
                          ? Center(
                              child: Text(
                                'This folder is empty.',
                                style: TextStyle(color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _entries.length,
                              itemBuilder: (ctx, i) {
                                final e = _entries[i];
                                final isDir = e is Directory;
                                final name = p.basename(e.path);

                                if (isDir) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF2C2C2E).withValues(alpha: 0.5) : const Color(0xFFF2F2F7).withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      leading: const Icon(CupertinoIcons.folder_fill, color: AppleColors.systemBlue, size: 24),
                                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                      trailing: widget.mode == AeroLinkPickerMode.folder
                                          ? CupertinoButton(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              minimumSize: Size.zero,
                                              color: AppleColors.systemBlue,
                                              borderRadius: BorderRadius.circular(8),
                                              onPressed: () => Navigator.pop(context, e.path),
                                              child: const Text('Share', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                            )
                                          : const Icon(CupertinoIcons.chevron_right, size: 14),
                                      onTap: () {
                                        _currentPath = e.path;
                                        _loadDirectory();
                                      },
                                    ),
                                  );
                                } else {
                                  // File entity
                                  int size = 0;
                                  try {
                                    size = (e as File).lengthSync();
                                  } catch (_) {}
                                  final ext = p.extension(e.path);
                                  final icon = _getFileIcon(ext);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF2C2C2E).withValues(alpha: 0.4) : const Color(0xFFF2F2F7).withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      enabled: widget.mode == AeroLinkPickerMode.file,
                                      leading: Icon(icon, color: AppleColors.systemGreen, size: 22),
                                      title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                      subtitle: Text(_formatSize(size), style: const TextStyle(fontSize: 11, color: AppleColors.textSecondary)),
                                      trailing: widget.mode == AeroLinkPickerMode.file
                                          ? CupertinoButton(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              minimumSize: Size.zero,
                                              color: AppleColors.systemGreen,
                                              borderRadius: BorderRadius.circular(8),
                                              onPressed: () => Navigator.pop(context, e.path),
                                              child: const Text('Share', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                            )
                                          : null,
                                      onTap: widget.mode == AeroLinkPickerMode.file
                                          ? () => Navigator.pop(context, e.path)
                                          : null,
                                    ),
                                  );
                                }
                              },
                            ),
                ),

                // Bottom Action for Folder Mode: "Share Current Folder"
                if (widget.mode == AeroLinkPickerMode.folder) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      color: AppleColors.systemBlue,
                      borderRadius: BorderRadius.circular(12),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: () => Navigator.pop(context, _currentPath),
                      child: Text(
                        'Share This Folder ("${p.basename(_currentPath)}")',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
