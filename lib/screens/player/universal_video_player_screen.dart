import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../models/vfs_node.dart';
import '../../services/media/media_player_service.dart';
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
  late int _currentIndex;
  late String _currentTitle;
  late String _currentPlaybackUri;
  StreamSubscription? _completedSubscription;
  bool _isSwitchingVideo = false;

  bool _showControls = true;
  Timer? _hideTimer;
  double _playbackSpeed = 1.0;
  bool _isLandscape = true;

  // Gesture seeking (MX Player style)
  bool _isDraggingSeek = false;
  Duration _dragStartPosition = Duration.zero;
  Duration _targetSeekPosition = Duration.zero;
  int _seekDeltaSeconds = 0;
  double _dragAccumulatedDx = 0.0;
  Timer? _dismissOverlayTimer;

  @override
  void initState() {
    super.initState();
    _mediaService = MediaPlayerService();
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
      if (mounted && !_isDraggingSeek) {
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
      widget.playlist != null && _currentIndex < widget.playlist!.length - 1;

  bool get _hasPrevious =>
      widget.playlist != null && _currentIndex > 0;

  Future<void> _playVideoAtIndex(int index) async {
    if (widget.playlist == null || index < 0 || index >= widget.playlist!.length) return;

    final node = widget.playlist![index];
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

  // MX Player horizontal drag seeking
  void _onHorizontalDragStart(DragStartDetails details) {
    _hideTimer?.cancel();
    _dismissOverlayTimer?.cancel();
    _dragStartPosition = _mediaService.player.state.position;
    _targetSeekPosition = _dragStartPosition;
    _seekDeltaSeconds = 0;
    _dragAccumulatedDx = 0.0;
    setState(() {
      _isDraggingSeek = true;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _dragAccumulatedDx += details.primaryDelta ?? 0.0;

    // Sensitivity: 1 physical pixel = 0.3s seek delta
    final deltaSec = (_dragAccumulatedDx * 0.3).round();
    final totalDuration = _mediaService.player.state.duration;

    final newPosSec = (_dragStartPosition.inSeconds + deltaSec).clamp(
      0,
      totalDuration.inSeconds > 0 ? totalDuration.inSeconds : 0,
    );

    setState(() {
      _targetSeekPosition = Duration(seconds: newPosSec);
      _seekDeltaSeconds = newPosSec - _dragStartPosition.inSeconds;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _mediaService.player.seek(_targetSeekPosition);
    _dismissOverlayTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _isDraggingSeek = false;
        });
        _startHideTimer();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _dismissOverlayTimer?.cancel();
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

  String _formatDelta(int deltaSeconds) {
    final sign = deltaSeconds >= 0 ? '+' : '-';
    final dur = Duration(seconds: deltaSeconds.abs());
    return '$sign${_formatDuration(dur)}';
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
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

            // Loading spinner when switching videos
            if (_isSwitchingVideo)
              const Center(
                child: CupertinoActivityIndicator(
                  radius: 20,
                  color: AppleColors.systemBlue,
                ),
              ),

            // MX Player HUD Overlay for Horizontal Swipe Seeking
            if (_isDraggingSeek)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xDD000000),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white24, width: 1),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _seekDeltaSeconds >= 0
                                ? CupertinoIcons.forward_fill
                                : CupertinoIcons.backward_fill,
                            color: AppleColors.systemBlue,
                            size: 28,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDelta(_seekDeltaSeconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_formatDuration(_targetSeekPosition)} / ${_formatDuration(_mediaService.player.state.duration)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Mini visual seek progress bar
                      SizedBox(
                        width: 150,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: player.state.duration.inMilliseconds > 0
                                ? (_targetSeekPosition.inMilliseconds /
                                        player.state.duration.inMilliseconds)
                                    .clamp(0.0, 1.0)
                                : 0.0,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppleColors.systemBlue),
                            minHeight: 4,
                          ),
                        ),
                      ),
                    ],
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
                  child: Row(
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
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
                            if (widget.playlist != null && widget.playlist!.length > 1)
                              Text(
                                '${_currentIndex + 1} of ${widget.playlist!.length}',
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
    );
  }
}
