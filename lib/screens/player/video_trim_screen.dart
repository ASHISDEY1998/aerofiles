import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../models/vfs_node.dart';
import '../../services/media/video_editor_service.dart';
import '../../services/vfs/vfs_provider.dart';
import '../../theme/apple_theme.dart';
import 'video_render_progress_dialog.dart';

class VideoTrimScreen extends StatefulWidget {
  final VfsNode node;
  final VfsProvider vfs;

  const VideoTrimScreen({
    super.key,
    required this.node,
    required this.vfs,
  });

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  late final Player _player;
  late final VideoController _videoController;

  Duration _totalDuration = Duration.zero;
  Duration _startTime = Duration.zero;
  Duration _endTime = Duration.zero;
  Duration _currentPosition = Duration.zero;

  bool _isPlaying = false;
  bool _isLoading = true;
  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _playingSub;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final playbackUri = await widget.vfs.getPlaybackUri(widget.node.path);
      await _player.open(Media(playbackUri), play: false);

      _durationSub = _player.stream.duration.listen((d) {
        if (mounted && d > Duration.zero) {
          setState(() {
            _totalDuration = d;
            if (_endTime == Duration.zero || _endTime > d) {
              _endTime = d;
            }
            _isLoading = false;
          });
        }
      });

      _positionSub = _player.stream.position.listen((pos) {
        if (mounted) {
          setState(() => _currentPosition = pos);
          // Loop playback inside the trimmed range [startTime, endTime]
          if (_player.state.playing && pos >= _endTime) {
            _player.seek(_startTime);
          }
        }
      });

      _playingSub = _player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() => _isPlaying = playing);
        }
      });

      // Fetch metadata fallback in case player duration takes time
      final meta = await VideoEditorService.instance.getVideoMetadata(widget.node.path);
      if (meta != null && meta.duration > Duration.zero && mounted) {
        setState(() {
          if (_totalDuration == Duration.zero) {
            _totalDuration = meta.duration;
            _endTime = meta.duration;
            _isLoading = false;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _playingSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
    } else {
      if (_currentPosition < _startTime || _currentPosition >= _endTime) {
        _player.seek(_startTime);
      }
      _player.play();
    }
  }

  void _seekToStart() {
    _player.seek(_startTime);
  }

  void _seekToEnd() {
    _player.seek(_endTime);
  }

  Future<void> _handleExport() async {
    if (_endTime <= _startTime) {
      _showToast('Invalid trim range: End time must be greater than start time.');
      return;
    }

    _player.pause();

    // Show Apple-style action sheet to choose Save Option
    final saveOption = await showCupertinoModalPopup<VideoSaveOption>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Save Trimmed Video'),
        message: const Text('Choose whether to save as a new file or replace the original.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, VideoSaveOption.keepOriginal),
            child: const Text('Save as New File (Keep Original)'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, VideoSaveOption.replaceOriginal),
            child: const Text('Replace Original File'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx, null),
          child: const Text('Cancel'),
        ),
      ),
    );

    if (saveOption == null || !mounted) return;

    // Show Render Progress Dialog
    final result = await VideoRenderProgressDialog.show(
      context,
      title: 'Trimming Video...',
      subtitle: saveOption == VideoSaveOption.replaceOriginal
          ? 'Rendering and replacing original file'
          : 'Exporting trimmed clip to folder',
      icon: CupertinoIcons.scissors,
      task: (onProgress) => VideoEditorService.instance.trimVideo(
        inputPath: widget.node.path,
        startTime: _startTime,
        endTime: _endTime,
        saveOption: saveOption,
        onProgressUpdated: onProgress,
      ),
    );

    if (result != null && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppleColors.darkElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatPrecise(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final tenths = ((d.inMilliseconds.remainder(1000)) / 100).floor();
    final hours = d.inHours;
    if (hours > 0) {
      return '$hours:$minutes:$seconds.$tenths';
    }
    return '$minutes:$seconds.$tenths';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _totalDuration.inMilliseconds.toDouble();
    final startMs = _startTime.inMilliseconds.toDouble();
    final endMs = _endTime.inMilliseconds.toDouble();
    final trimmedDuration = _endTime > _startTime ? _endTime - _startTime : Duration.zero;

    return Scaffold(
      backgroundColor: AppleColors.pureBlack,
      appBar: AppBar(
        backgroundColor: AppleColors.pureBlack,
        elevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 22),
        ),
        title: Text(
          widget.node.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppleColors.systemBlue,
              borderRadius: BorderRadius.circular(18),
              onPressed: _isLoading ? null : _handleExport,
              child: const Text(
                'Export',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14))
            : Column(
                children: [
                  // Video Preview Section
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Video(
                              controller: _videoController,
                              controls: NoVideoControls,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        // Play / Pause Overlay Button
                        GestureDetector(
                          onTap: _togglePlayPause,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _isPlaying ? 0.0 : 0.85,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 1.5),
                              ),
                              child: const Icon(
                                CupertinoIcons.play_fill,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Trimming Control Card
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161618),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border.all(
                        color: const Color(0xFF2C2C2E),
                        width: 0.6,
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Time Information Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Start Time
                            GestureDetector(
                              onTap: _seekToStart,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'START',
                                    style: TextStyle(
                                      color: AppleColors.textTertiary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatPrecise(_startTime),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Trimmed Duration Pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppleColors.systemBlue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppleColors.systemBlue.withValues(alpha: 0.4),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(CupertinoIcons.scissors, color: AppleColors.systemBlue, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatPrecise(trimmedDuration),
                                    style: const TextStyle(
                                      color: AppleColors.systemBlue,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // End Time
                            GestureDetector(
                              onTap: _seekToEnd,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'END',
                                    style: TextStyle(
                                      color: AppleColors.textTertiary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatPrecise(_endTime),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Range Slider (Start & End Handles)
                        if (totalMs > 0)
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppleColors.systemBlue,
                              inactiveTrackColor: const Color(0xFF2C2C2E),
                              trackHeight: 6,
                              thumbColor: Colors.white,
                              overlayColor: AppleColors.systemBlue.withValues(alpha: 0.2),
                              rangeThumbShape: const RoundRangeSliderThumbShape(
                                enabledThumbRadius: 10,
                                elevation: 4,
                              ),
                              rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
                            ),
                            child: RangeSlider(
                              values: RangeValues(
                                startMs.clamp(0.0, totalMs),
                                endMs.clamp(startMs, totalMs),
                              ),
                              min: 0.0,
                              max: totalMs,
                              onChanged: (RangeValues values) {
                                final newStart = Duration(milliseconds: values.start.toInt());
                                final newEnd = Duration(milliseconds: values.end.toInt());
                                setState(() {
                                  _startTime = newStart;
                                  _endTime = newEnd;
                                });
                                // Seek to the dragged point
                                if ((values.start - startMs).abs() > (values.end - endMs).abs()) {
                                  _player.seek(newStart);
                                } else {
                                  _player.seek(newEnd);
                                }
                              },
                            ),
                          ),

                        const SizedBox(height: 12),

                        // Quick Control & Nudge Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Nudge Start -1s
                            _buildNudgeButton(
                              label: '-1s Start',
                              onTap: () {
                                final newStart = _startTime - const Duration(seconds: 1);
                                setState(() {
                                  _startTime = newStart < Duration.zero ? Duration.zero : newStart;
                                });
                                _player.seek(_startTime);
                              },
                            ),
                            // Nudge Start +1s
                            _buildNudgeButton(
                              label: '+1s Start',
                              onTap: () {
                                final newStart = _startTime + const Duration(seconds: 1);
                                if (newStart < _endTime) {
                                  setState(() => _startTime = newStart);
                                  _player.seek(_startTime);
                                }
                              },
                            ),
                            // Play / Pause Icon
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              color: const Color(0xFF2C2C2E),
                              borderRadius: BorderRadius.circular(20),
                              onPressed: _togglePlayPause,
                              child: Icon(
                                _isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            // Nudge End -1s
                            _buildNudgeButton(
                              label: '-1s End',
                              onTap: () {
                                final newEnd = _endTime - const Duration(seconds: 1);
                                if (newEnd > _startTime) {
                                  setState(() => _endTime = newEnd);
                                  _player.seek(_endTime);
                                }
                              },
                            ),
                            // Nudge End +1s
                            _buildNudgeButton(
                              label: '+1s End',
                              onTap: () {
                                final newEnd = _endTime + const Duration(seconds: 1);
                                setState(() {
                                  _endTime = newEnd > _totalDuration ? _totalDuration : newEnd;
                                });
                                _player.seek(_endTime);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildNudgeButton({required String label, required VoidCallback onTap}) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: AppleColors.systemBlue,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
