import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final sectionBg = isDark ? AppleColors.pureBlack : const Color(0xFFF2F2F7);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          decoration: BoxDecoration(
            color: sectionBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
                  const SizedBox(height: 14),

                  // Header with Done button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppleColors.systemBlue,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(CupertinoIcons.folder_fill_badge_person_crop, color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'AeroLink Settings',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                              color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                            ),
                          ),
                        ],
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        borderRadius: BorderRadius.circular(16),
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Done',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Section 1: Device Information
                  Text(
                    'DEVICE INFORMATION',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                      color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        width: 0.6,
                      ),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: _promptEditDeviceName,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                const Icon(CupertinoIcons.device_phone_portrait, color: AppleColors.systemBlue, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Device Name',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                    ),
                                  ),
                                ),
                                Text(
                                  _service.deviceName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(CupertinoIcons.pencil, size: 14, color: AppleColors.systemBlue),
                              ],
                            ),
                          ),
                        ),
                        Divider(
                          height: 0.5,
                          thickness: 0.5,
                          indent: 46,
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(CupertinoIcons.wifi, color: AppleColors.systemBlue, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Wi-Fi IP',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                  ),
                                ),
                              ),
                              Text(
                                _localIp.isNotEmpty ? _localIp : 'Connecting...',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'Devices must be on the same local Wi-Fi to connect.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Section 2: 6-Digit Pairing Code (Clean AirDrop Style)
                  Text(
                    'PAIRING CODE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                      color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        width: 0.6,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          pin.length == 6 ? '${pin.substring(0, 3)}  ${pin.substring(3)}' : pin,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 6,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              minimumSize: Size.zero,
                              borderRadius: BorderRadius.circular(14),
                              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                              onPressed: () {
                                _service.regeneratePin();
                                setState(() {});
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(CupertinoIcons.arrow_2_circlepath, size: 14, color: AppleColors.systemBlue),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Regenerate',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              minimumSize: Size.zero,
                              borderRadius: BorderRadius.circular(14),
                              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: pin));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('PIN copied to clipboard'), duration: Duration(seconds: 2)),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(CupertinoIcons.doc_on_doc, size: 14, color: AppleColors.systemBlue),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Copy',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'Enter this code on another AeroFiles device to pair.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Section 3: Shared Items
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SHARED ITEMS (${shares.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
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
                  const SizedBox(height: 6),
                  if (shares.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                          width: 0.6,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'No items shared yet.\nTap "+ Add Item" to share folders or files.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                          width: 0.6,
                        ),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < shares.length; i++) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(
                                    shares[i].isFile ? CupertinoIcons.doc_fill : CupertinoIcons.folder_fill,
                                    color: shares[i].isFile ? AppleColors.systemGreen : AppleColors.systemBlue,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          shares[i].name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          shares[i].localPath,
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
                                      _service.removeShare(shares[i].id);
                                      setState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                            if (i < shares.length - 1)
                              Divider(
                                height: 0.5,
                                thickness: 0.5,
                                indent: 48,
                                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                              ),
                          ],
                        ],
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
