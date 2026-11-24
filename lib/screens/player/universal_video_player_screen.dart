import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import '../../models/vfs_node.dart';
import '../../services/log_service.dart';
import '../../services/media/media_player_service.dart';
import '../../services/media/playback_history_service.dart';
import '../../services/settings_service.dart';
import '../../services/vfs/aerolink_vfs.dart';
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

enum _PlayerGestureMode {
  none,
  pinchZoom,
  panZoomed,
  seeking,
  brightness,
  volume,
}

class _UniversalVideoPlayerScreenState extends State<UniversalVideoPlayerScreen> {
  late final MediaPlayerService _mediaService;
  late List<VfsNode> _playlist;
  late int _currentIndex;
  late String _currentTitle;
  late String _currentPlaybackUri;
  StreamSubscription? _completedSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _videoParamsSubscription;
  bool _isSwitchingVideo = false;
  bool _hasDeletedAny = false;

  bool _showControls = true;
  Timer? _hideTimer;
  double _playbackSpeed = 1.0;
  bool _isLandscape = true;

  // Video aspect ratio / fit mode (Fit, Fill/Zoom, Stretch)
  BoxFit _videoFit = BoxFit.contain;
  String _fitLabel = 'Fit to Screen';
  bool _showFitHudIndicator = false;
  Timer? _fitHudTimer;

  // Pinch-to-zoom & pan gestures
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _panOffset = Offset.zero;
  Offset _startFocalPoint = Offset.zero;
  Offset _accumulatedDelta = Offset.zero;
  bool _showZoomHud = false;
  Timer? _zoomHudTimer;
  _PlayerGestureMode _gestureMode = _PlayerGestureMode.none;

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

  // Playback Resume
  int _savedResumeSeconds = 0;
  bool _showResumeBanner = false;
  Timer? _resumeBannerTimer;

  // Quick Double-Tap Seek (±10s)
  bool _showLeftSeekRipple = false;
  bool _showRightSeekRipple = false;
  Timer? _seekRippleTimer;

  @override
  void initState() {
    super.initState();
    _mediaService = MediaPlayerService();
    _playlist = widget.playlist != null ? List<VfsNode>.from(widget.playlist!) : [];
    _currentIndex = widget.initialIndex;
    _currentTitle = widget.title;
    _currentPlaybackUri = widget.playbackUri;

    LogService.instance.info('PLAYER', 'Opening initial video: "$_currentTitle" uri: $_currentPlaybackUri (index: $_currentIndex)');
    _mediaService.openMedia(_currentPlaybackUri);
    _startHideTimer();
    _checkSavedPlaybackPosition();

    // Auto-pause when Bluetooth audio disconnects or call arrives (AudioFocus loss / Noisy)
    _mediaService.onAudioFocusInterrupted = () {
      if (mounted) {
        setState(() {
          _showControls = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(CupertinoIcons.phone_down_fill, color: AppleColors.systemOrange, size: 18),
                SizedBox(width: 10),
                Text('Playback paused (Call / Audio redirected)'),
              ],
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: AppleColors.darkCard,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    };

    // Enable immersive sticky fullscreen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Natural orientation - allow free sensor rotation without forced landscape default
    SystemChrome.setPreferredOrientations([]);

    // Adapt orientation automatically based on actual video aspect ratio
    _videoParamsSubscription = _mediaService.player.stream.videoParams.listen((params) {
      if (!mounted) return;
      if (params.w != null && params.h != null && params.w! > 0 && params.h! > 0) {
        final isPortraitVideo = params.h! > params.w!;
        setState(() {
          _isLandscape = !isPortraitVideo;
        });
      }
    });

    // Support headphone & Bluetooth media next/prev buttons
    _mediaService.onMediaNext = () {
      if (mounted) {
        if (_hasNext) {
          _playVideoAtIndex(_currentIndex + 1);
        } else {
          final current = _mediaService.player.state.position;
          final total = _mediaService.player.state.duration;
          final target = current + const Duration(seconds: 10);
          _mediaService.seek(target < total ? target : total);
        }
      }
    };
    _mediaService.onMediaPrevious = () {
      if (mounted) {
        final current = _mediaService.player.state.position;
        if (current.inSeconds > 3) {
          _mediaService.seek(Duration.zero);
        } else if (_hasPrevious) {
          _playVideoAtIndex(_currentIndex - 1);
        } else {
          _mediaService.seek(Duration.zero);
        }
      }
    };

    // Initialize volume from player
    _volume = _mediaService.player.state.volume;

    // Periodically save playback position every 5s
    _positionSubscription = _mediaService.player.stream.position.listen((pos) {
      final total = _mediaService.player.state.duration;
      if (total.inSeconds > 0 && pos.inSeconds > 0 && pos.inSeconds % 5 == 0) {
        PlaybackHistoryService.instance.savePosition(_currentPlaybackUri, pos, total);
      }
    });

    // Auto-advance to next video when playback finishes
    _completedSubscription = _mediaService.player.stream.completed.listen((completed) {
      if (completed) {
        PlaybackHistoryService.instance.clearPosition(_currentPlaybackUri);
      }
      if (completed && mounted && _hasNext) {
        _playVideoAtIndex(_currentIndex + 1);
      }
    });
  }

  void _toggleVideoFit() {
    setState(() {
      _scale = 1.0;
      _panOffset = Offset.zero;
      if (_videoFit == BoxFit.contain) {
        _videoFit = BoxFit.cover;
        _fitLabel = 'Crop to Fill';
      } else if (_videoFit == BoxFit.cover) {
        _videoFit = BoxFit.fill;
        _fitLabel = 'Stretch';
      } else {
        _videoFit = BoxFit.contain;
        _fitLabel = 'Fit to Screen';
      }
      _showFitHudIndicator = true;
    });

    _fitHudTimer?.cancel();
    _fitHudTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _showFitHudIndicator = false);
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

    // Save position of current video before switching
    PlaybackHistoryService.instance.savePosition(
      _currentPlaybackUri,
      _mediaService.player.state.position,
      _mediaService.player.state.duration,
    );

    final node = _playlist[index];
    setState(() {
      _currentIndex = index;
      _currentTitle = node.name;
      _isSwitchingVideo = true;
      _showResumeBanner = false;
      _scale = 1.0;
      _panOffset = Offset.zero;
    });

    try {
      String uri = node.path;
      if (widget.vfs != null) {
        uri = await widget.vfs!.getPlaybackUri(node.path);
      }
      _currentPlaybackUri = uri;
      LogService.instance.info('PLAYER', 'Switching video index $index: "${node.name}" uri: $uri');
      await _mediaService.openMedia(uri);
      _checkSavedPlaybackPosition();
    } catch (e, st) {
      LogService.instance.error('PLAYER', 'Error playing video at index $index: $e', e, st);
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

  // Unified gestures: Pinch-to-zoom (2 fingers), Pan when zoomed, Horizontal seek, Left vertical brightness, Right vertical volume
  void _onScaleStart(ScaleStartDetails details) {
    _hideTimer?.cancel();
    _zoomHudTimer?.cancel();
    _hideVerticalHudTimer?.cancel();

    _startFocalPoint = details.localFocalPoint;
    _accumulatedDelta = Offset.zero;
    _baseScale = _scale;
    _dragStartPosition = _mediaService.player.state.position;
    _targetSeekPosition = _dragStartPosition;
    _dragAccumulatedDx = 0.0;

    if (details.pointerCount >= 2) {
      _gestureMode = _PlayerGestureMode.pinchZoom;
      _isAdjustingBrightness = false;
      _isAdjustingVolume = false;
      _showZoomHud = true;
      setState(() {});
    } else {
      _gestureMode = _PlayerGestureMode.none;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      // Two fingers: Pinch-to-zoom
      _gestureMode = _PlayerGestureMode.pinchZoom;
      _isAdjustingBrightness = false;
      _isAdjustingVolume = false;

      final targetScale = (_baseScale * details.scale).clamp(1.0, 5.0);
      final size = MediaQuery.of(context).size;
      final maxPanX = (size.width * (targetScale - 1.0)) / 2;
      final maxPanY = (size.height * (targetScale - 1.0)) / 2;

      Offset newPan = _panOffset + details.focalPointDelta;
      if (targetScale <= 1.0) {
        newPan = Offset.zero;
      } else {
        newPan = Offset(
          newPan.dx.clamp(-maxPanX, maxPanX),
          newPan.dy.clamp(-maxPanY, maxPanY),
        );
      }

      setState(() {
        _scale = targetScale;
        _panOffset = newPan;
        _showZoomHud = true;
      });
      return;
    }

    // Single finger:
    if (_scale > 1.05) {
      // When zoomed in, 1 finger pans around video frame
      _gestureMode = _PlayerGestureMode.panZoomed;
      final size = MediaQuery.of(context).size;
      final maxPanX = (size.width * (_scale - 1.0)) / 2;
      final maxPanY = (size.height * (_scale - 1.0)) / 2;
      final newPan = _panOffset + details.focalPointDelta;

      setState(() {
        _panOffset = Offset(
          newPan.dx.clamp(-maxPanX, maxPanX),
          newPan.dy.clamp(-maxPanY, maxPanY),
        );
      });
      return;
    }

    // Normal scale (<= 1.05): single-finger gestures (Seek, Brightness, Volume)
    if (_gestureMode == _PlayerGestureMode.none) {
      _accumulatedDelta += details.focalPointDelta;
      if (_accumulatedDelta.distance < 8.0) return; // Prevent jitter before gesture direction locked

      if (_accumulatedDelta.dx.abs() > _accumulatedDelta.dy.abs()) {
        _gestureMode = _PlayerGestureMode.seeking;
        _dragStartPosition = _mediaService.player.state.position;
        _targetSeekPosition = _dragStartPosition;
        _dragAccumulatedDx = 0.0;
      } else {
        final screenWidth = MediaQuery.of(context).size.width;
        if (_startFocalPoint.dx < screenWidth * 0.5) {
          _gestureMode = _PlayerGestureMode.brightness;
          _isAdjustingBrightness = true;
          _isAdjustingVolume = false;
        } else {
          _gestureMode = _PlayerGestureMode.volume;
          _isAdjustingVolume = true;
          _isAdjustingBrightness = false;
        }
        setState(() {});
      }
    }

    if (_gestureMode == _PlayerGestureMode.seeking) {
      _dragAccumulatedDx += details.focalPointDelta.dx;
      final deltaSec = (_dragAccumulatedDx * 0.35).round();
      final totalDuration = _mediaService.player.state.duration;
      final newPosSec = (_dragStartPosition.inSeconds + deltaSec).clamp(
        0,
        totalDuration.inSeconds > 0 ? totalDuration.inSeconds : 0,
      );
      _targetSeekPosition = Duration(seconds: newPosSec);
      _mediaService.player.seek(_targetSeekPosition);
    } else if (_gestureMode == _PlayerGestureMode.brightness) {
      final screenHeight = MediaQuery.of(context).size.height;
      final deltaFraction = -details.focalPointDelta.dy / (screenHeight * 0.7);
      final newBrightness = (_brightness + deltaFraction).clamp(0.1, 1.0);
      setState(() {
        _brightness = newBrightness;
      });
    } else if (_gestureMode == _PlayerGestureMode.volume) {
      final screenHeight = MediaQuery.of(context).size.height;
      final deltaFraction = -details.focalPointDelta.dy / (screenHeight * 0.7);
      final newVolume = (_volume + (deltaFraction * 100.0)).clamp(0.0, 100.0);
      setState(() {
        _volume = newVolume;
      });
      _mediaService.player.setVolume(newVolume);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_scale <= 1.05) {
      setState(() {
        _scale = 1.0;
        _panOffset = Offset.zero;
      });
    }

    if (_gestureMode == _PlayerGestureMode.pinchZoom) {
      _zoomHudTimer?.cancel();
      _zoomHudTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showZoomHud = false);
      });
      _startHideTimer();
    } else if (_gestureMode == _PlayerGestureMode.seeking) {
      _mediaService.player.seek(_targetSeekPosition);
      _startHideTimer();
    } else if (_gestureMode == _PlayerGestureMode.brightness || _gestureMode == _PlayerGestureMode.volume) {
      _hideVerticalHudTimer?.cancel();
      _hideVerticalHudTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() {
            _isAdjustingBrightness = false;
            _isAdjustingVolume = false;
          });
          _startHideTimer();
        }
      });
    } else {
      _startHideTimer();
    }

    _gestureMode = _PlayerGestureMode.none;
  }

  // Delete Video Actions with identical Apple confirmation popup
  void _confirmDeleteCurrentVideo() {
    if (_playlist.isEmpty || _currentIndex >= _playlist.length) return;
    final currentNode = _playlist[_currentIndex];

    final isRemote = widget.vfs is AeroLinkVfs ||
        (widget.vfs != null && widget.vfs is! LocalVfs) ||
        _currentPlaybackUri.startsWith('http://') ||
        _currentPlaybackUri.startsWith('https://');

    if (isRemote) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          dismissDirection: DismissDirection.down,
          duration: const Duration(seconds: 3),
          content: const Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_circle, color: AppleColors.systemOrange, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Cannot modify remote files. AeroLink storage is read-only.'),
              ),
            ],
          ),
        ),
      );
      return;
    }

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
    LogService.instance.info('PLAYER', 'Delete requested for "${node.name}" (moveToTrash: $moveToTrash)');
    // Completely stop playback and release media player decoder resources
    await _mediaService.stop();
    await Future.delayed(const Duration(milliseconds: 100));
    _hasDeletedAny = true;

    try {
      final vfsProvider = widget.vfs ?? LocalVfs();
      await vfsProvider.delete(node.path, moveToTrash: moveToTrash);
      LogService.instance.info('PLAYER', 'Successfully deleted "${node.name}" from storage');

      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            dismissDirection: DismissDirection.down,
            duration: const Duration(seconds: 4),
            content: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                }
              },
              onVerticalDragUpdate: (details) {
                if (details.delta.dy > 3) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                }
              },
              child: Text(
                moveToTrash
                    ? '"${node.name}" moved to Recycle Bin'
                    : '"${node.name}" permanently deleted',
              ),
            ),
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
    _fitHudTimer?.cancel();
    _zoomHudTimer?.cancel();
    _completedSubscription?.cancel();
    _positionSubscription?.cancel();
    _videoParamsSubscription?.cancel();
    _resumeBannerTimer?.cancel();
    _seekRippleTimer?.cancel();

    _mediaService.onMediaNext = null;
    _mediaService.onMediaPrevious = null;

    // Persist position upon exit
    PlaybackHistoryService.instance.savePosition(
      _currentPlaybackUri,
      _mediaService.player.state.position,
      _mediaService.player.state.duration,
    );

    _mediaService.dispose();

    // Restore edge-to-edge UI and unlock all orientations for tablets and phones
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);

    super.dispose();
  }

  Future<void> _checkSavedPlaybackPosition() async {
    final saved = await PlaybackHistoryService.instance.getSavedPosition(_currentPlaybackUri);
    if (saved > 15 && mounted) {
      setState(() {
        _savedResumeSeconds = saved;
        _showResumeBanner = true;
      });
      _resumeBannerTimer?.cancel();
      _resumeBannerTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _showResumeBanner = false);
      });
    }
  }

  void _resumeFromSavedPosition() {
    _resumeBannerTimer?.cancel();
    if (_savedResumeSeconds > 0) {
      _mediaService.seek(Duration(seconds: _savedResumeSeconds));
      HapticFeedback.mediumImpact();
    }
    setState(() => _showResumeBanner = false);
  }

  void _dismissResumeBanner() {
    _resumeBannerTimer?.cancel();
    PlaybackHistoryService.instance.clearPosition(_currentPlaybackUri);
    setState(() => _showResumeBanner = false);
  }

  void _onDoubleTapDown(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dx = details.localPosition.dx;
    final currentPos = _mediaService.player.state.position;
    final totalDuration = _mediaService.player.state.duration;

    // Double-tap while zoomed in instantly resets zoom back to 100%
    if (_scale > 1.05) {
      setState(() {
        _scale = 1.0;
        _panOffset = Offset.zero;
        _showZoomHud = true;
      });
      _zoomHudTimer?.cancel();
      _zoomHudTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _showZoomHud = false);
      });
      HapticFeedback.mediumImpact();
      return;
    }

    if (dx < screenWidth * 0.35) {
      // Seek Backward 10s
      final target = currentPos - const Duration(seconds: 10);
      _mediaService.seek(target < Duration.zero ? Duration.zero : target);
      HapticFeedback.lightImpact();

      _seekRippleTimer?.cancel();
      setState(() {
        _showLeftSeekRipple = true;
        _showRightSeekRipple = false;
      });
      _seekRippleTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showLeftSeekRipple = false);
      });
    } else if (dx > screenWidth * 0.65) {
      // Seek Forward 10s
      final target = currentPos + const Duration(seconds: 10);
      _mediaService.seek(totalDuration.inSeconds > 0 && target > totalDuration ? totalDuration : target);
      HapticFeedback.lightImpact();

      _seekRippleTimer?.cancel();
      setState(() {
        _showRightSeekRipple = true;
        _showLeftSeekRipple = false;
      });
      _seekRippleTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showRightSeekRipple = false);
      });
    } else {
      // Center Double-Tap: Play/Pause Toggle
      _mediaService.playOrPause();
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _enterPipMode() async {
    try {
      setState(() {
        _showControls = false;
        _scale = 1.0;
        _panOffset = Offset.zero;
      });
      const channel = MethodChannel('com.aerofiles.app/storage');
      final entered = await channel.invokeMethod<bool>('enterPipMode');
      if (entered != true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PiP mode not supported on this device')),
        );
      }
    } catch (e) {
      debugPrint('enterPipMode error: $e');
    }
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
    final audioTracks = player.state.tracks.audio;
    final subtitleTracks = player.state.tracks.subtitle;
    final selectedAudio = player.state.track.audio;
    final selectedSubtitle = player.state.track.subtitle;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isAudio ? 'Audio Tracks' : 'Subtitles',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (!isAudio) ...[
                          ListTile(
                            leading: Icon(
                              selectedSubtitle.id == 'no'
                                  ? CupertinoIcons.checkmark_circle_fill
                                  : CupertinoIcons.circle,
                              color: selectedSubtitle.id == 'no'
                                  ? AppleColors.systemBlue
                                  : AppleColors.textTertiary,
                            ),
                            title: const Text('Off (Disable Subtitles)'),
                            onTap: () {
                              _mediaService.setSubtitleTrack(SubtitleTrack.no());
                              Navigator.pop(ctx);
                              setState(() {});
                            },
                          ),
                          ListTile(
                            leading: Icon(
                              selectedSubtitle.id == 'auto'
                                  ? CupertinoIcons.checkmark_circle_fill
                                  : CupertinoIcons.circle,
                              color: selectedSubtitle.id == 'auto'
                                  ? AppleColors.systemBlue
                                  : AppleColors.textTertiary,
                            ),
                            title: const Text('Auto (Default Stream)'),
                            onTap: () {
                              _mediaService.setSubtitleTrack(SubtitleTrack.auto());
                              Navigator.pop(ctx);
                              setState(() {});
                            },
                          ),
                          const Divider(height: 1, indent: 56),
                        ],
                        if (isAudio) ...[
                          ListTile(
                            leading: Icon(
                              selectedAudio.id == 'auto'
                                  ? CupertinoIcons.checkmark_circle_fill
                                  : CupertinoIcons.circle,
                              color: selectedAudio.id == 'auto'
                                  ? AppleColors.systemBlue
                                  : AppleColors.textTertiary,
                            ),
                            title: const Text('Auto (Default Audio)'),
                            onTap: () {
                              _mediaService.setAudioTrack(AudioTrack.auto());
                              Navigator.pop(ctx);
                              setState(() {});
                            },
                          ),
                          const Divider(height: 1, indent: 56),
                        ],
                        ...(isAudio ? audioTracks : subtitleTracks).map((track) {
                          if (track.id == 'auto' || track.id == 'no') return const SizedBox.shrink();

                          final isSelected = isAudio
                              ? selectedAudio.id == track.id
                              : selectedSubtitle.id == track.id;

                          String label = track.title ?? '';
                          if (label.isEmpty && track.language != null && track.language!.isNotEmpty) {
                            label = track.language!.toUpperCase();
                          }
                          if (label.isEmpty) {
                            label = 'Track ${track.id}';
                          }

                          String? details;
                          if (isAudio && track is AudioTrack) {
                            final channels = track.channels ?? (track.channelscount != null ? '${track.channelscount} ch' : null);
                            final codec = track.codec;
                            if (channels != null || codec != null) {
                              details = [codec, channels].where((e) => e != null).join(' • ');
                            }
                          }

                          return ListTile(
                            leading: Icon(
                              isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                              color: isSelected ? AppleColors.systemBlue : AppleColors.textTertiary,
                            ),
                            title: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                            subtitle: details != null ? Text(details, style: const TextStyle(fontSize: 12, color: AppleColors.textSecondary)) : null,
                            onTap: () {
                              if (isAudio) {
                                _mediaService.setAudioTrack(track as AudioTrack);
                              } else {
                                _mediaService.setSubtitleTrack(track as SubtitleTrack);
                              }
                              Navigator.pop(ctx);
                              setState(() {});
                            },
                          );
                        }),
                        if (!isAudio) ...[
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(CupertinoIcons.folder_badge_plus, color: AppleColors.systemBlue),
                            title: const Text('Load Subtitles from Folder...'),
                            subtitle: const Text('Detect .srt, .vtt, .ass files in folder'),
                            onTap: () {
                              Navigator.pop(ctx);
                              _detectAndPickSubtitles();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _detectAndPickSubtitles() async {
    try {
      final currentFile = File(_currentPlaybackUri);
      final parentDir = currentFile.parent;
      if (await parentDir.exists()) {
        final subs = <File>[];
        for (final entity in parentDir.listSync()) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (ext == '.srt' || ext == '.vtt' || ext == '.ass' || ext == '.sub') {
              subs.add(entity);
            }
          }
        }

        if (!mounted) return;

        if (subs.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No subtitle files (.srt, .vtt, .ass) found in this folder')),
          );
          return;
        }

        showCupertinoModalPopup(
          context: context,
          builder: (ctx) => CupertinoActionSheet(
            title: const Text('Available Subtitle Files'),
            message: const Text('Select a subtitle file to load'),
            actions: [
              ...subs.map((f) => CupertinoActionSheetAction(
                onPressed: () {
                  _mediaService.setSubtitleTrack(SubtitleTrack.uri(f.path, title: p.basename(f.path)));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Loaded subtitle: ${p.basename(f.path)}')),
                  );
                },
                child: Text(p.basename(f.path)),
              )),
            ],
            cancelButton: CupertinoActionSheetAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to detect subtitles: $e');
    }
  }

  void _showSpeedSelector() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Playback Speed'),
        actions: [
          for (final s in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _playbackSpeed = s);
                _mediaService.setRate(s);
              },
              child: Text(
                '${s}x${_playbackSpeed == s ? " ✓" : ""}',
                style: TextStyle(
                  color: _playbackSpeed == s ? AppleColors.systemBlue : null,
                  fontWeight: _playbackSpeed == s ? FontWeight.bold : FontWeight.normal,
                ),
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

  @override
  Widget build(BuildContext context) {
    final player = _mediaService.player;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _hasDeletedAny);
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause ||
                event.logicalKey == LogicalKeyboardKey.headsetHook ||
                event.logicalKey == LogicalKeyboardKey.space) {
              _mediaService.playOrPause();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.mediaPlay) {
              _mediaService.play();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.mediaPause) {
              _mediaService.pause();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.mediaTrackNext) {
              if (_hasNext) _playVideoAtIndex(_currentIndex + 1);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.mediaTrackPrevious) {
              if (_hasPrevious) _playVideoAtIndex(_currentIndex - 1);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTapDown: _onDoubleTapDown,
        onDoubleTap: () {},
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Video Output with Pinch-to-Zoom & Pan
            Center(
              child: ClipRect(
                child: Transform(
                  alignment: Alignment.center,
                  // ignore: deprecated_member_use
                  transform: Matrix4.identity()
                    // ignore: deprecated_member_use
                    ..translate(_panOffset.dx, _panOffset.dy)
                    // ignore: deprecated_member_use
                    ..scale(_scale),
                  child: Video(
                    controller: _mediaService.controller,
                    width: double.infinity,
                    height: double.infinity,
                    fit: _videoFit,
                    controls: NoVideoControls,
                  ),
                ),
              ),
            ),

            // Video Loading / Buffering Spinner
            StreamBuilder<bool>(
              stream: _mediaService.player.stream.buffering,
              builder: (context, buffSnap) {
                final isBuffering = buffSnap.data ?? false;
                if (!isBuffering && !_isSwitchingVideo) return const SizedBox.shrink();
                return const Center(
                  child: CupertinoActivityIndicator(radius: 20, color: Colors.white),
                );
              },
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

            // Pinch-to-zoom HUD Indicator Overlay
            if (_showZoomHud)
              Positioned(
                top: 72,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xD9000000),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24, width: 0.8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _scale > 1.05 ? CupertinoIcons.zoom_in : CupertinoIcons.zoom_out,
                          color: AppleColors.systemBlue,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _scale <= 1.02 ? 'Zoom: 100%' : 'Zoom: ${(_scale * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Aspect Ratio / Fit HUD Indicator
            if (_showFitHudIndicator)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _videoFit == BoxFit.contain
                            ? Icons.aspect_ratio
                            : _videoFit == BoxFit.cover
                                ? CupertinoIcons.arrow_up_left_arrow_down_right
                                : CupertinoIcons.arrow_left_right,
                        color: AppleColors.systemBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _fitLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Double-Tap Left Seek Ripple (-10s)
            if (_showLeftSeekRipple)
              Positioned(
                left: 48,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xB3000000),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.gobackward_10, color: Colors.white, size: 36),
                          SizedBox(height: 6),
                          Text('-10s', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Double-Tap Right Seek Ripple (+10s)
            if (_showRightSeekRipple)
              Positioned(
                right: 48,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xB3000000),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.goforward_10, color: Colors.white, size: 36),
                          SizedBox(height: 6),
                          Text('+10s', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Resume Playback Floating Banner (Positioned smoothly above bottom controls to avoid top header overlap)
            if (_showResumeBanner && _savedResumeSeconds > 0)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                bottom: _showControls
                    ? MediaQuery.of(context).padding.bottom + 92
                    : MediaQuery.of(context).padding.bottom + 28,
                left: 20,
                right: 20,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xE61C1C1E),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.play_circle_fill, color: AppleColors.systemBlue, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Resume Playback',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Resume from ${_formatDuration(Duration(seconds: _savedResumeSeconds))}?',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _resumeFromSavedPosition,
                            style: TextButton.styleFrom(
                              backgroundColor: AppleColors.systemBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(CupertinoIcons.xmark, color: Colors.white54, size: 18),
                            tooltip: 'Dismiss',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _dismissResumeBanner,
                          ),
                        ],
                      ),
                    ),
                  ),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 600;
                      final isRemote = widget.vfs is AeroLinkVfs ||
                          (widget.vfs != null && widget.vfs is! LocalVfs) ||
                          _currentPlaybackUri.startsWith('http://') ||
                          _currentPlaybackUri.startsWith('https://');

                      return Row(
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                          // Aspect Ratio / Fit Mode Toggle Button
                          IconButton(
                            icon: Icon(
                              _videoFit == BoxFit.contain
                                  ? Icons.aspect_ratio
                                  : _videoFit == BoxFit.cover
                                      ? CupertinoIcons.arrow_up_left_arrow_down_right
                                      : CupertinoIcons.arrow_left_right,
                              color: Colors.white,
                            ),
                            tooltip: 'Aspect Ratio: $_fitLabel',
                            onPressed: _toggleVideoFit,
                          ),
                          if (!isCompact) ...[
                            // Wide screen / Landscape mode: Show all icon buttons
                            IconButton(
                              icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white),
                              tooltip: 'Picture-in-Picture',
                              onPressed: _enterPipMode,
                            ),
                            IconButton(
                              icon: const Icon(CupertinoIcons.captions_bubble, color: Colors.white),
                              tooltip: 'Subtitles',
                              onPressed: () => _showTrackSheet(isAudio: false),
                            ),
                            IconButton(
                              icon: const Icon(CupertinoIcons.speaker_2, color: Colors.white),
                              tooltip: 'Audio Tracks',
                              onPressed: () => _showTrackSheet(isAudio: true),
                            ),
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
                            IconButton(
                              icon: Icon(
                                CupertinoIcons.trash,
                                color: isRemote ? Colors.white38 : Colors.white,
                              ),
                              tooltip: isRemote ? 'Remote files cannot be deleted' : 'Delete Video',
                              onPressed: _confirmDeleteCurrentVideo,
                            ),
                          ] else ...[
                            // Compact phone / Portrait: Clean "More" Menu preventing layout squashing
                            PopupMenuButton<String>(
                              icon: const Icon(CupertinoIcons.ellipsis_circle, color: Colors.white),
                              tooltip: 'More options',
                              color: AppleColors.darkElevated,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              onSelected: (val) {
                                switch (val) {
                                  case 'pip':
                                    _enterPipMode();
                                    break;
                                  case 'subtitles':
                                    _showTrackSheet(isAudio: false);
                                    break;
                                  case 'audio':
                                    _showTrackSheet(isAudio: true);
                                    break;
                                  case 'speed':
                                    _showSpeedSelector();
                                    break;
                                  case 'delete':
                                    _confirmDeleteCurrentVideo();
                                    break;
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'pip',
                                  child: Row(
                                    children: [
                                      Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 20),
                                      SizedBox(width: 12),
                                      Text('Picture-in-Picture', style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'subtitles',
                                  child: Row(
                                    children: [
                                      Icon(CupertinoIcons.captions_bubble, color: Colors.white, size: 20),
                                      SizedBox(width: 12),
                                      Text('Subtitles', style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'audio',
                                  child: Row(
                                    children: [
                                      Icon(CupertinoIcons.speaker_2, color: Colors.white, size: 20),
                                      SizedBox(width: 12),
                                      Text('Audio Tracks', style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'speed',
                                  child: Row(
                                    children: [
                                      const Icon(CupertinoIcons.speedometer, color: Colors.white, size: 20),
                                      const SizedBox(width: 12),
                                      Text('Speed (${_playbackSpeed}x)', style: const TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.trash,
                                        color: isRemote ? Colors.grey : AppleColors.systemRed,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        isRemote ? 'Delete (Read-only)' : 'Delete Video',
                                        style: TextStyle(
                                          color: isRemote ? Colors.grey : AppleColors.systemRed,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      );
                    },
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
    ),
  );
}
}
