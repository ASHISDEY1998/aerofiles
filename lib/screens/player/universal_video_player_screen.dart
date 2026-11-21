import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../services/media/media_player_service.dart';
import '../../theme/apple_theme.dart';

class UniversalVideoPlayerScreen extends StatefulWidget {
  final String title;
  final String playbackUri;

  const UniversalVideoPlayerScreen({
    super.key,
    required this.title,
    required this.playbackUri,
  });

  @override
  State<UniversalVideoPlayerScreen> createState() => _UniversalVideoPlayerScreenState();
}

class _UniversalVideoPlayerScreenState extends State<UniversalVideoPlayerScreen> {
  late final MediaPlayerService _mediaService;
  bool _showControls = true;
  Timer? _hideTimer;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _mediaService = MediaPlayerService();
    _mediaService.openMedia(widget.playbackUri);
    _startHideTimer();

    // Auto rotate to landscape for immersive video
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
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

  @override
  void dispose() {
    _hideTimer?.cancel();
    _mediaService.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
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
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Subtitles
                      IconButton(
                        icon: const Icon(CupertinoIcons.captions_bubble, color: Colors.white),
                        onPressed: () => _showTrackSheet(isAudio: false),
                      ),
                      // Audio Track
                      IconButton(
                        icon: const Icon(CupertinoIcons.speaker_2, color: Colors.white),
                        onPressed: () => _showTrackSheet(isAudio: true),
                      ),
                      // Playback Speed
                      PopupMenuButton<double>(
                        icon: const Icon(CupertinoIcons.speedometer, color: Colors.white),
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

              // Center Play/Pause & Skip Controls
              Center(
                child: StreamBuilder<bool>(
                  stream: player.stream.playing,
                  builder: (context, snapshot) {
                    final isPlaying = snapshot.data ?? true;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // -10s
                        IconButton(
                          iconSize: 44,
                          icon: const Icon(CupertinoIcons.gobackward_10, color: Colors.white),
                          onPressed: () {
                            player.seek(player.state.position - const Duration(seconds: 10));
                            _startHideTimer();
                          },
                        ),
                        const SizedBox(width: 32),
                        // Play/Pause
                        Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0x66000000),
                          ),
                          child: IconButton(
                            iconSize: 64,
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
                        const SizedBox(width: 32),
                        // +10s
                        IconButton(
                          iconSize: 44,
                          icon: const Icon(CupertinoIcons.goforward_10, color: Colors.white),
                          onPressed: () {
                            player.seek(player.state.position + const Duration(seconds: 10));
                            _startHideTimer();
                          },
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
