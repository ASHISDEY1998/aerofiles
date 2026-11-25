import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../models/vfs_node.dart';
import '../../services/file_operation_service.dart';
import '../../services/log_service.dart';
import '../../services/media/media_player_service.dart';
import '../../services/recycle_bin_service.dart';
import '../../services/settings_service.dart';
import '../../services/vfs/aerolink_vfs.dart';
import '../../services/vfs/local_vfs.dart';
import '../../services/vfs/vfs_provider.dart';
import '../../theme/apple_theme.dart';

class UniversalAudioPlayerScreen extends StatefulWidget {
  final List<VfsNode> playlist;
  final int initialIndex;
  final VfsProvider? vfs;

  const UniversalAudioPlayerScreen({
    super.key,
    required this.playlist,
    required this.initialIndex,
    this.vfs,
  });

  @override
  State<UniversalAudioPlayerScreen> createState() => _UniversalAudioPlayerScreenState();
}

class _UniversalAudioPlayerScreenState extends State<UniversalAudioPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final MediaPlayerService _mediaService;
  late int _currentIndex;
  late List<VfsNode> _playlist;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isShuffle = false;
  int _repeatMode = 1; // 0 = off, 1 = repeat all, 2 = repeat one
  double _playbackRate = 1.0;
  bool _hasDeletedAny = false;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferSub;
  StreamSubscription? _completedSub;

  late final AnimationController _discAnimController;

  bool get _isReadOnly {
    if (widget.vfs is AeroLinkVfs) return true;
    if (_playlist.isNotEmpty && _currentIndex < _playlist.length) {
      final cur = _playlist[_currentIndex];
      if (cur.path.contains('/aerolink/stream') || cur.path.startsWith('http://') || cur.path.startsWith('https://')) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _playlist = List.from(widget.playlist);
    _currentIndex = widget.initialIndex.clamp(0, _playlist.isEmpty ? 0 : _playlist.length - 1);

    _discAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    _mediaService = MediaPlayerService();
    _setupSubscriptions();
    _loadAndPlayCurrentTrack(autoPlay: true);
  }

  void _setupSubscriptions() {
    final player = _mediaService.player;

    _posSub = player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _durSub = player.stream.duration.listen((dur) {
      if (mounted && dur > Duration.zero) setState(() => _duration = dur);
    });

    _playingSub = player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
        if (playing) {
          _discAnimController.repeat();
        } else {
          _discAnimController.stop();
        }
      }
    });

    _bufferSub = player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });

    _completedSub = player.stream.completed.listen((completed) {
      if (completed && mounted) {
        _handleTrackCompleted();
      }
    });

    // Headset / Bluetooth buttons
    _mediaService.onMediaPlayPause = () => _togglePlayPause();
    _mediaService.onMediaNext = () => _playNext();
    _mediaService.onMediaPrevious = () => _playPrevious();
    _mediaService.onAudioFocusInterrupted = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _playingSub?.cancel();
    _bufferSub?.cancel();
    _completedSub?.cancel();

    _mediaService.onMediaPlayPause = null;
    _mediaService.onMediaNext = null;
    _mediaService.onMediaPrevious = null;
    _mediaService.onAudioFocusInterrupted = null;

    _discAnimController.dispose();
    _mediaService.dispose();
    super.dispose();
  }

  Future<void> _loadAndPlayCurrentTrack({bool autoPlay = true}) async {
    if (_playlist.isEmpty || _currentIndex >= _playlist.length) return;
    final node = _playlist[_currentIndex];

    setState(() {
      _position = Duration.zero;
      _duration = Duration.zero;
      _isBuffering = true;
    });

    try {
      String playbackUri = node.path;
      if (widget.vfs != null) {
        playbackUri = await widget.vfs!.getPlaybackUri(node.path);
      }
      await _mediaService.openMedia(playbackUri, autoPlay: autoPlay);
      if (_playbackRate != 1.0) {
        await _mediaService.setRate(_playbackRate);
      }
    } catch (e) {
      LogService.instance.error('AUDIO_PLAYER', 'Failed to open audio: $e');
    } finally {
      if (mounted) setState(() => _isBuffering = false);
    }
  }

  void _handleTrackCompleted() {
    if (_repeatMode == 2) {
      // Repeat Current Song
      _mediaService.seek(Duration.zero);
      _mediaService.play();
    } else if (_playlist.length > 1) {
      _playNext();
    } else if (_repeatMode == 1) {
      _mediaService.seek(Duration.zero);
      _mediaService.play();
    }
  }

  void _togglePlayPause() {
    HapticFeedback.lightImpact();
    _mediaService.playOrPause();
  }

  void _playNext() {
    if (_playlist.isEmpty) return;
    HapticFeedback.selectionClick();

    int nextIndex;
    if (_isShuffle && _playlist.length > 1) {
      final rand = Random();
      do {
        nextIndex = rand.nextInt(_playlist.length);
      } while (nextIndex == _currentIndex);
    } else {
      nextIndex = (_currentIndex + 1) % _playlist.length;
      if (nextIndex == 0 && _repeatMode == 0) {
        // Stopped at end of playlist
        _mediaService.seek(Duration.zero);
        _mediaService.pause();
        return;
      }
    }

    setState(() => _currentIndex = nextIndex);
    _loadAndPlayCurrentTrack(autoPlay: true);
  }

  void _playPrevious() {
    if (_playlist.isEmpty) return;
    HapticFeedback.selectionClick();

    // If more than 3 seconds into song, restart track
    if (_position.inSeconds > 3) {
      _mediaService.seek(Duration.zero);
      return;
    }

    final prevIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    setState(() => _currentIndex = prevIndex);
    _loadAndPlayCurrentTrack(autoPlay: true);
  }

  void _toggleShuffle() {
    HapticFeedback.lightImpact();
    setState(() => _isShuffle = !_isShuffle);
  }

  void _cycleRepeatMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _repeatMode = (_repeatMode + 1) % 3; // 0 = off, 1 = all, 2 = one
    });
  }

  void _showSpeedPicker() {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Playback Speed'),
        actions: [
          for (final speed in speeds)
            CupertinoActionSheetAction(
              onPressed: () {
                setState(() => _playbackRate = speed);
                _mediaService.setRate(speed);
                Navigator.pop(ctx);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((_playbackRate - speed).abs() < 0.01)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(CupertinoIcons.check_mark, size: 16),
                    ),
                  Text('${speed}x${speed == 1.0 ? ' (Normal)' : ''}'),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showQueueSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: const BoxDecoration(
          color: Color(0xFF161618),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.list_bullet, color: AppleColors.systemBlue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Queue (${_playlist.length} songs)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done', style: TextStyle(color: AppleColors.systemBlue, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: _playlist.length,
                itemBuilder: (context, index) {
                  final item = _playlist[index];
                  final isCurrent = index == _currentIndex;

                  return Container(
                    color: isCurrent ? AppleColors.systemBlue.withValues(alpha: 0.15) : Colors.transparent,
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isCurrent ? AppleColors.systemBlue : const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isCurrent
                              ? (_isPlaying ? CupertinoIcons.speaker_3_fill : CupertinoIcons.pause_fill)
                              : CupertinoIcons.music_note,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? AppleColors.systemBlue : Colors.white,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${item.formattedSize} • ${p.dirname(item.path)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      trailing: isCurrent
                          ? const Icon(CupertinoIcons.waveform, color: AppleColors.systemBlue, size: 18)
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        if (index != _currentIndex) {
                          setState(() => _currentIndex = index);
                          _loadAndPlayCurrentTrack(autoPlay: true);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreMenu() {
    if (_playlist.isEmpty || _currentIndex >= _playlist.length) return;
    final node = _playlist[_currentIndex];

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        message: Text('${node.formattedSize} • ${p.dirname(node.path)}'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              FileOperationService.instance.openWith(node);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.arrow_up_right_square, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Open with Other Player...',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              FileOperationService.instance.shareItems([node]);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.share, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Share Audio File',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              FileOperationService.instance.showFileInfo(context, node);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.info_circle, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Track Details',
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
              _confirmDeleteCurrentTrack();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.trash, size: 18, color: AppleColors.systemRed),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Delete Audio File',
                    style: TextStyle(color: AppleColors.systemRed),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _confirmDeleteCurrentTrack() {
    if (_playlist.isEmpty || _currentIndex >= _playlist.length) return;
    final currentAudio = _playlist[_currentIndex];

    if (_isReadOnly) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppleColors.darkCard,
          behavior: SnackBarBehavior.floating,
          dismissDirection: DismissDirection.down,
          duration: const Duration(seconds: 4),
          content: const Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_circle, color: AppleColors.systemOrange, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cannot modify remote files. AeroLink storage is read-only.',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
      Timer(const Duration(seconds: 4), () {
        messenger.hideCurrentSnackBar();
      });
      return;
    }

    final settings = SettingsService.instance;
    final behavior = settings.deleteBehavior;

    if (behavior == DeleteBehavior.recycleBin) {
      _executeDeleteCurrentTrack(currentAudio, moveToTrash: true);
      return;
    } else if (behavior == DeleteBehavior.permanent) {
      _confirmPermanentDelete(currentAudio);
      return;
    }

    bool moveToTrash = true;
    bool rememberChoice = false;

    showCupertinoDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return CupertinoAlertDialog(
            title: Text('Delete "${currentAudio.name}"?'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Choose how to delete this audio file:',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Option 1: Move to Recycle Bin
                  GestureDetector(
                    onTap: () => setDialogState(() => moveToTrash = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: moveToTrash
                            ? (isDark
                                ? AppleColors.systemBlue.withValues(alpha: 0.2)
                                : AppleColors.systemBlueLight.withValues(alpha: 0.15))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            moveToTrash ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                            color: moveToTrash ? AppleColors.systemBlue : AppleColors.textTertiary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Move to Recycle Bin',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                Text(
                                  'Safely restore anytime from Trash',
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
                  ),
                  const SizedBox(height: 8),

                  // Option 2: Delete Permanently
                  GestureDetector(
                    onTap: () => setDialogState(() => moveToTrash = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: !moveToTrash
                            ? (isDark
                                ? AppleColors.systemRed.withValues(alpha: 0.2)
                                : AppleColors.systemRed.withValues(alpha: 0.15))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            !moveToTrash ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                            color: !moveToTrash ? AppleColors.systemRed : AppleColors.textTertiary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delete Permanently',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                Text(
                                  'Cannot be undone. Space is freed now.',
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
                  ),

                  const SizedBox(height: 14),

                  // Remember choice checkbox
                  GestureDetector(
                    onTap: () => setDialogState(() => rememberChoice = !rememberChoice),
                    child: Row(
                      children: [
                        Icon(
                          rememberChoice ? CupertinoIcons.checkmark_square_fill : CupertinoIcons.square,
                          size: 18,
                          color: rememberChoice ? AppleColors.systemBlue : AppleColors.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Make this the default choice',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(ctx),
              ),
              CupertinoDialogAction(
                isDestructiveAction: !moveToTrash,
                child: Text(moveToTrash ? 'Move to Bin' : 'Delete'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (rememberChoice) {
                    await settings.setDeleteBehavior(
                      moveToTrash ? DeleteBehavior.recycleBin : DeleteBehavior.permanent,
                    );
                  }
                  _executeDeleteCurrentTrack(currentAudio, moveToTrash: moveToTrash);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmPermanentDelete(VfsNode node) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Permanently delete "${node.name}"?'),
        content: const Text('This cannot be undone and will permanently remove this audio file from your storage.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete Permanently'),
            onPressed: () {
              Navigator.pop(ctx);
              _executeDeleteCurrentTrack(node, moveToTrash: false);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _executeDeleteCurrentTrack(VfsNode node, {required bool moveToTrash}) async {
    LogService.instance.info('AUDIO', 'Delete requested for "${node.name}" (moveToTrash: $moveToTrash)');
    await _mediaService.stop();
    _hasDeletedAny = true;

    try {
      final vfsProvider = widget.vfs ?? LocalVfs();
      await vfsProvider.delete(node.path, moveToTrash: moveToTrash);
      await RecycleBinService.notifyMediaScanner(node.path);

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.removeCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppleColors.darkCard,
            behavior: SnackBarBehavior.floating,
            dismissDirection: DismissDirection.down,
            duration: const Duration(seconds: 4),
            content: Text(
              moveToTrash
                  ? '"${node.name}" moved to Recycle Bin'
                  : '"${node.name}" permanently deleted',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        );
        Timer(const Duration(seconds: 4), () {
          messenger.hideCurrentSnackBar();
        });
      }

      setState(() {
        _playlist.removeAt(_currentIndex);
        if (_playlist.isEmpty) {
          Navigator.pop(context, true);
        } else {
          _currentIndex = _currentIndex.clamp(0, _playlist.length - 1);
          _loadAndPlayCurrentTrack(autoPlay: true);
        }
      });
    } catch (e) {
      LogService.instance.error('AUDIO', 'Failed to delete audio file: $e');
    }
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '0:00';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_playlist.isEmpty) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) Navigator.pop(context, _hasDeletedAny);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: CupertinoNavigationBar(
            backgroundColor: Colors.transparent,
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context, _hasDeletedAny),
              child: const Icon(CupertinoIcons.chevron_back, color: Colors.white, size: 28),
            ),
          ),
          body: const Center(
            child: Text('No audio files to play', style: TextStyle(color: Colors.white70)),
          ),
        ),
      );
    }

    final currentTrack = _playlist[_currentIndex];
    final progressValue = (_duration.inMilliseconds > 0)
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _hasDeletedAny);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.0, -0.4),
              radius: 1.1,
              colors: [
                Color(0xFF1E2640),
                Color(0xFF0F121C),
                Color(0xFF000000),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // 1. Top Navigation Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context, _hasDeletedAny),
                        child: const Icon(CupertinoIcons.chevron_down, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'PLAYING FROM FOLDER',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              p.basename(p.dirname(currentTrack.path)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _showMoreMenu,
                        child: const Icon(CupertinoIcons.ellipsis_circle, color: Colors.white, size: 24),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                // 2. Center Vinyl Disc / Artwork Display
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Center(
                    child: RotationTransition(
                      turns: _discAnimController,
                      child: Container(
                        width: min(MediaQuery.of(context).size.width * 0.72, 280),
                        height: min(MediaQuery.of(context).size.width * 0.72, 280),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF121214),
                          boxShadow: [
                            BoxShadow(
                              color: AppleColors.systemBlue.withValues(alpha: _isPlaying ? 0.28 : 0.12),
                              blurRadius: 36,
                              spreadRadius: 6,
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 2,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Vinyl Grooves
                            Container(
                              margin: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.all(48),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
                              ),
                            ),
                            // Center Record Label
                            Container(
                              width: 90,
                              height: 90,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  _isBuffering
                                      ? CupertinoIcons.arrow_2_circlepath
                                      : (_isPlaying ? CupertinoIcons.music_note_2 : CupertinoIcons.music_note),
                                  color: Colors.white,
                                  size: 38,
                                ),
                              ),
                            ),
                            // Center Spindle Hole
                            Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF000000),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // 3. Track Info (Title, Category, File Format Badge)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      Text(
                        currentTrack.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              p.extension(currentTrack.path).replaceAll('.', '').toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            currentTrack.formattedSize,
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '•  ${_currentIndex + 1} of ${_playlist.length}',
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // 4. Progress Scrubber Slider & Timestamps
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      CupertinoSlider(
                        value: progressValue,
                        activeColor: AppleColors.systemBlue,
                        thumbColor: Colors.white,
                        onChanged: (val) {
                          if (_duration.inMilliseconds > 0) {
                            final targetMs = (val * _duration.inMilliseconds).round();
                            _mediaService.seek(Duration(milliseconds: targetMs));
                          }
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(_position),
                              style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              _duration > Duration.zero ? _formatDuration(_duration) : '--:--',
                              style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // 5. Main Transport Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Shuffle button
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _toggleShuffle,
                        child: Icon(
                          CupertinoIcons.shuffle,
                          color: _isShuffle ? AppleColors.systemBlue : Colors.white38,
                          size: 22,
                        ),
                      ),

                      // Previous button
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _playPrevious,
                        child: const Icon(
                          CupertinoIcons.backward_fill,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),

                      // Play/Pause Big Button
                      GestureDetector(
                        onTap: _togglePlayPause,
                        child: Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.25),
                                blurRadius: 18,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: _isBuffering
                                ? const CupertinoActivityIndicator(color: Colors.black, radius: 14)
                                : Icon(
                                    _isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                                    color: Colors.black,
                                    size: 30,
                                  ),
                          ),
                        ),
                      ),

                      // Next button
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _playNext,
                        child: const Icon(
                          CupertinoIcons.forward_fill,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),

                      // Repeat button
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _cycleRepeatMode,
                        child: Icon(
                          _repeatMode == 2 ? CupertinoIcons.repeat_1 : CupertinoIcons.repeat,
                          color: _repeatMode > 0 ? AppleColors.systemBlue : Colors.white38,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // 6. Bottom Utility Actions (Speed, Open With, Queue)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Speed indicator
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        onPressed: _showSpeedPicker,
                        child: Text(
                          '${_playbackRate}x',
                          style: TextStyle(
                            color: _playbackRate != 1.0 ? AppleColors.systemBlue : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      // Open With other app (User request)
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        onPressed: () => FileOperationService.instance.openWith(currentTrack),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.arrow_up_right_square, color: Colors.white70, size: 15),
                            SizedBox(width: 6),
                            Text(
                              'Open With...',
                              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),

                      // Queue List Button
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        onPressed: _showQueueSheet,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.list_bullet, color: Colors.white70, size: 15),
                            SizedBox(width: 4),
                            Text(
                              'Queue',
                              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
