import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../models/vfs_node.dart';
import '../../services/media/media_player_service.dart';
import '../../services/settings_service.dart';
import '../../services/vfs/local_vfs.dart';
import '../../services/vfs/vfs_provider.dart';
import '../../theme/apple_theme.dart';

class UniversalVideoPlayerScreen extends StatefulWidget {
  final String title;
  final String playbackUri;
  final List<VfsNode>? playlist;
  final int initialIndex;
  final VfsProvider? vfs;

  const UniversalVideoPlayerScreen({
    super.key,
    required this.title,
    required this.playbackUri,
    this.playlist,
    this.initialIndex = 0,
    this.vfs,
  });

  @override
  State<UniversalVideoPlayerScreen> createState() => _UniversalVideoPlayerScreenState();
}

class _UniversalVideoPlayerScreenState extends State<UniversalVideoPlayerScreen> {
  late final MediaPlayerService _mediaService;
  late List<VfsNode> _playlist;
  late int _currentIndex;
  late String _currentTitle;
  late String _currentPlaybackUri;
  StreamSubscription? _completedSubscription;
  bool _isSwitchingVideo = false;
  bool _hasDeletedAny = false;

  bool _showControls = true;
  Timer? _hideTimer;
  double _playbackSpeed = 1.0;
  bool _isLandscape = true;

  // Horizontal seek gestures (Smooth seeking without middle preview box)
  Duration _dragStartPosition = Duration.zero;
  Duration _targetSeekPosition = Duration.zero;
  double _dragAccumulatedDx = 0.0;

  // Vertical swipe gestures (MX Player style: Left = Brightness, Right = Volume)
  double _brightness = 1.0; // 0.1 to 1.0
  double _volume = 100.0; // 0.0 to 100.0
  bool _isAdjustingBrightness = false;
  bool _isAdjustingVolume = false;
  Timer? _hideVerticalHudTimer;
  double _verticalDragStartY = 0.0;
  double _verticalDragStartValue = 0.0;

  @override
  void initState() {
    super.initState();
    _mediaService = MediaPlayerService();
    _playlist = widget.playlist != null ? List<VfsNode>.from(widget.playlist!) : [];
    _currentIndex = widget.initialIndex;
    _currentTitle = widget.title;
    _currentPlaybackUri = widget.playbackUri;

    _mediaService.openMedia(_currentPlaybackUri);
    _startHideTimer();

    // Auto rotate to landscape for immersive video
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Initialize volume from player
    _volume = _mediaService.player.state.volume;

    // Auto-advance to next video when playback finishes
    _completedSubscription = _mediaService.player.stream.completed.listen((completed) {
      if (completed && mounted && _hasNext) {
        _playVideoAtIndex(_currentIndex + 1);
      }
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isAdjustingBrightness && !_isAdjustingVolume) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) _startHideTimer();
    });
  }

  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
    });
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  bool get _hasNext =>
      _playlist.isNotEmpty && _currentIndex < _playlist.length - 1;

  bool get _hasPrevious =>
      _playlist.isNotEmpty && _currentIndex > 0;

  Future<void> _playVideoAtIndex(int index) async {
    if (_playlist.isEmpty || index < 0 || index >= _playlist.length) return;

    final node = _playlist[index];
    setState(() {
      _currentIndex = index;
      _currentTitle = node.name;
      _isSwitchingVideo = true;
    });

    try {
      String uri = node.path;
      if (widget.vfs != null) {
        uri = await widget.vfs!.getPlaybackUri(node.path);
      }
      _currentPlaybackUri = uri;
      await _mediaService.openMedia(uri);
    } catch (e) {
      debugPrint('Error playing video at index $index: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingVideo = false;
        });
        _startHideTimer();
      }
    }
  }

  // Horizontal seek gestures: seeks directly without center popup timeline card
  void _onHorizontalDragStart(DragStartDetails details) {
    _hideTimer?.cancel();
    _dragStartPosition = _mediaService.player.state.position;
    _targetSeekPosition = _dragStartPosition;
    _dragAccumulatedDx = 0.0;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _dragAccumulatedDx += details.primaryDelta ?? 0.0;

    // 1 physical pixel = 0.35s seek delta
    final deltaSec = (_dragAccumulatedDx * 0.35).round();
    final totalDuration = _mediaService.player.state.duration;

    final newPosSec = (_dragStartPosition.inSeconds + deltaSec).clamp(
      0,
      totalDuration.inSeconds > 0 ? totalDuration.inSeconds : 0,
    );

    _targetSeekPosition = Duration(seconds: newPosSec);
    _mediaService.player.seek(_targetSeekPosition);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _mediaService.player.seek(_targetSeekPosition);
    _startHideTimer();
  }

  // Vertical drag gestures: Left side = Brightness, Right side = Volume
  void _onVerticalDragStart(DragStartDetails details) {
    _hideTimer?.cancel();
    _hideVerticalHudTimer?.cancel();
    final screenWidth = MediaQuery.of(context).size.width;
    _verticalDragStartY = details.localPosition.dy;

    if (details.localPosition.dx < screenWidth / 2) {
      _isAdjustingBrightness = true;
      _isAdjustingVolume = false;
      _verticalDragStartValue = _brightness;
    } else {
      _isAdjustingVolume = true;
      _isAdjustingBrightness = false;
      _verticalDragStartValue = _volume;
    }
    setState(() {});
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    final deltaY = _verticalDragStartY - details.localPosition.dy;
    final deltaFraction = deltaY / (screenHeight * 0.7);

    if (_isAdjustingBrightness) {
      final newBrightness = (_verticalDragStartValue + deltaFraction).clamp(0.1, 1.0);
      setState(() {
        _brightness = newBrightness;
      });
    } else if (_isAdjustingVolume) {
      final newVolume = (_verticalDragStartValue + (deltaFraction * 100.0)).clamp(0.0, 100.0);
      setState(() {
        _volume = newVolume;
      });
      _mediaService.player.setVolume(newVolume);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _hideVerticalHudTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _isAdjustingBrightness = false;
          _isAdjustingVolume = false;
        });
        _startHideTimer();
      }
    });
  }

  // Delete Video Actions with identical Apple confirmation popup
  void _confirmDeleteCurrentVideo() {
    if (_playlist.isEmpty || _currentIndex >= _playlist.length) return;
    final currentNode = _playlist[_currentIndex];
    final settings = SettingsService.instance;
    final behavior = settings.deleteBehavior;

    if (behavior == DeleteBehavior.recycleBin) {
      _executeDeleteCurrentVideo(currentNode, moveToTrash: true);
      return;
    } else if (behavior == DeleteBehavior.permanent) {
      _confirmPermanentDelete(currentNode);
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
            title: Text('Delete "${currentNode.name}"?'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Choose how to delete this video:',
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
                  _executeDeleteCurrentVideo(currentNode, moveToTrash: moveToTrash);
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
        content: const Text('This cannot be undone and will permanently remove this video from your storage.'),
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
              _executeDeleteCurrentVideo(node, moveToTrash: false);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _executeDeleteCurrentVideo(VfsNode node, {required bool moveToTrash}) async {
    await _mediaService.pause();
    _hasDeletedAny = true;

    try {
      final vfsProvider = widget.vfs ?? LocalVfs();
      await vfsProvider.delete(node.path, moveToTrash: moveToTrash);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              moveToTrash
                  ? '"${node.name}" moved to Recycle Bin'
                  : '"${node.name}" permanently deleted',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Remove from playlist
      _playlist.removeAt(_currentIndex);

      if (_playlist.isEmpty) {
        // No videos left in folder/playlist, exit back to directory browser
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        // Play next video (or previous if it was the last video in the list)
        if (_currentIndex >= _playlist.length) {
          _currentIndex = _playlist.length - 1;
        }
        await _playVideoAtIndex(_currentIndex);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete video: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hideVerticalHudTimer?.cancel();
    _completedSubscription?.cancel();
    _mediaService.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _showTrackSheet({required bool isAudio}) {
    final player = _mediaService.player;
    final tracks = isAudio ? player.state.tracks.audio : player.state.tracks.subtitle;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(isAudio ? 'Audio Tracks' : 'Subtitles'),
        message: Text(isAudio ? 'Select multi-language audio track' : 'Select or toggle subtitle stream'),
        actions: [
          if (!isAudio)
            CupertinoActionSheetAction(
              onPressed: () {
                _mediaService.setSubtitleTrack(SubtitleTrack.no());
                Navigator.pop(ctx);
              },
              child: const Text('Off (Disable Subtitles)', style: TextStyle(color: AppleColors.systemRed)),
            ),
          ...tracks.map((track) {
            final label = track.title ?? track.language ?? track.id;
            return CupertinoActionSheetAction(
              onPressed: () {
                if (isAudio) {
                  _mediaService.setAudioTrack(track as AudioTrack);
                } else {
                  _mediaService.setSubtitleTrack(track as SubtitleTrack);
                }
                Navigator.pop(ctx);
              },
              child: Text(label),
            );
          }),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = _mediaService.player;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _hasDeletedAny);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Video Output
            Center(
              child: Video(
                controller: _mediaService.controller,
                controls: NoVideoControls,
              ),
            ),

            // Visual Hardware-accelerated Brightness scrim
            if (_brightness < 1.0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: (1.0 - _brightness).clamp(0.0, 0.85)),
                  ),
                ),
              ),

            // Left Brightness HUD Indicator
            if (_isAdjustingBrightness)
              Positioned(
                left: 36,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.sun_max_fill, color: AppleColors.systemBlue, size: 24),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 110,
                          width: 8,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: LinearProgressIndicator(
                                value: _brightness,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(AppleColors.systemBlue),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${(_brightness * 100).toInt()}%',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Right Volume HUD Indicator
            if (_isAdjustingVolume)
              Positioned(
                right: 36,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _volume == 0
                              ? CupertinoIcons.speaker_slash_fill
                              : _volume < 50
                                  ? CupertinoIcons.speaker_1_fill
                                  : CupertinoIcons.speaker_3_fill,
                          color: AppleColors.systemBlue,
                          size: 24,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 110,
                          width: 8,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: LinearProgressIndicator(
                                value: (_volume / 100.0).clamp(0.0, 1.0),
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(AppleColors.systemBlue),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${_volume.toInt()}%',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Loading spinner when switching videos
            if (_isSwitchingVideo)
              const Center(
                child: CupertinoActivityIndicator(
                  radius: 20,
                  color: AppleColors.systemBlue,
                ),
              ),

            // Controls Overlay
            if (_showControls) ...[
              // Top Bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xCC000000), Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context, _hasDeletedAny),
                        child: const Icon(CupertinoIcons.chevron_back, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currentTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_playlist.length > 1)
                              Text(
                                '${_currentIndex + 1} of ${_playlist.length}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Rotate Screen Toggle Button
                      IconButton(
                        icon: Icon(
                          _isLandscape ? CupertinoIcons.device_phone_portrait : CupertinoIcons.device_phone_landscape,
                          color: Colors.white,
                        ),
                        tooltip: _isLandscape ? 'Switch to Portrait' : 'Switch to Landscape',
                        onPressed: _toggleOrientation,
                      ),
                      // Subtitles
                      IconButton(
                        icon: const Icon(CupertinoIcons.captions_bubble, color: Colors.white),
                        tooltip: 'Subtitles',
                        onPressed: () => _showTrackSheet(isAudio: false),
                      ),
                      // Audio Track
                      IconButton(
                        icon: const Icon(CupertinoIcons.speaker_2, color: Colors.white),
                        tooltip: 'Audio Tracks',
                        onPressed: () => _showTrackSheet(isAudio: true),
                      ),
                      // Playback Speed
                      PopupMenuButton<double>(
                        icon: const Icon(CupertinoIcons.speedometer, color: Colors.white),
                        tooltip: 'Speed',
                        color: AppleColors.darkElevated,
                        onSelected: (speed) {
                          setState(() => _playbackSpeed = speed);
                          _mediaService.setRate(speed);
                        },
                        itemBuilder: (ctx) => [
                          for (final s in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                            PopupMenuItem(
                              value: s,
                              child: Text(
                                '${s}x',
                                style: TextStyle(
                                  color: _playbackSpeed == s ? AppleColors.systemBlue : Colors.white,
                                  fontWeight: _playbackSpeed == s ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                        ],
                      ),
                      // Delete Current Video Button
                      IconButton(
                        icon: const Icon(CupertinoIcons.trash, color: Colors.white),
                        tooltip: 'Delete Video',
                        onPressed: _confirmDeleteCurrentVideo,
                      ),
                    ],
                  ),
                ),
              ),

              // Center Play/Pause, Next/Previous, & Skip Controls
              Center(
                child: StreamBuilder<bool>(
                  stream: player.stream.playing,
                  builder: (context, snapshot) {
                    final isPlaying = snapshot.data ?? true;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Previous Video Button
                        IconButton(
                          iconSize: 34,
                          tooltip: 'Previous Video',
                          icon: Icon(
                            CupertinoIcons.backward_end_fill,
                            color: _hasPrevious ? Colors.white : Colors.white24,
                          ),
                          onPressed: _hasPrevious
                              ? () {
                                  _playVideoAtIndex(_currentIndex - 1);
                                  _startHideTimer();
                                }
                              : null,
                        ),
                        const SizedBox(width: 16),
                        // -10s Rewind
                        IconButton(
                          iconSize: 40,
                          tooltip: 'Rewind 10s',
                          icon: const Icon(CupertinoIcons.gobackward_10, color: Colors.white),
                          onPressed: () {
                            player.seek(player.state.position - const Duration(seconds: 10));
                            _startHideTimer();
                          },
                        ),
                        const SizedBox(width: 20),
                        // Play / Pause Control
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0x66000000),
                          ),
                          child: IconButton(
                            iconSize: 48,
                            tooltip: isPlaying ? 'Pause' : 'Play',
                            icon: Icon(
                              isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                              color: AppleColors.systemBlue,
                            ),
                            onPressed: () {
                              _mediaService.playOrPause();
                              _startHideTimer();
                            },
                          ),
                        ),
                        const SizedBox(width: 20),
                        // +10s Forward
                        IconButton(
                          iconSize: 40,
                          tooltip: 'Forward 10s',
                          icon: const Icon(CupertinoIcons.goforward_10, color: Colors.white),
                          onPressed: () {
                            player.seek(player.state.position + const Duration(seconds: 10));
                            _startHideTimer();
                          },
                        ),
                        const SizedBox(width: 16),
                        // Next Video Button
                        IconButton(
                          iconSize: 34,
                          tooltip: 'Next Video',
                          icon: Icon(
                            CupertinoIcons.forward_end_fill,
                            color: _hasNext ? Colors.white : Colors.white24,
                          ),
                          onPressed: _hasNext
                              ? () {
                                  _playVideoAtIndex(_currentIndex + 1);
                                  _startHideTimer();
                                }
                              : null,
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Bottom Progress Bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 12,
                    left: 20,
                    right: 20,
                    top: 16,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Color(0xCC000000)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: StreamBuilder<Duration>(
                    stream: player.stream.position,
                    builder: (context, posSnap) {
                      final pos = posSnap.data ?? Duration.zero;
                      final total = player.state.duration;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(pos),
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              Text(
                                _formatDuration(total),
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppleColors.systemBlue,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayColor: const Color(0x330A84FF),
                            ),
                            child: Slider(
                              value: pos.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
                              max: total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0,
                              onChanged: (val) {
                                _startHideTimer();
                                player.seek(Duration(milliseconds: val.toInt()));
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
}
