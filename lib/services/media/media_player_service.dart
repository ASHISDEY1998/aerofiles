import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../log_service.dart';

class MediaPlayerService {
  static bool _initialized = false;

  static void ensureInitialized() {
    if (!_initialized) {
      MediaKit.ensureInitialized();
      _initialized = true;
    }
  }

  late final Player player;
  late final VideoController controller;

  bool _isDisposed = false;

  MediaPlayerService() {
    ensureInitialized();
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'AeroFiles Universal Player',
        bufferSize: 64 * 1024 * 1024, // 64MB buffer for smooth local & network playback
        protocolWhitelist: [
          '*',
          'file',
          'tcp',
          'tls',
          'http',
          'https',
          'crypto',
          'data',
          'smb',
          'sftp',
          'rtmp',
          'rtsp',
          'hls',
          'udp',
          'pipe',
          'fd',
          '*',
        ],
      ),
    );
    controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        hwdec: 'auto-safe',
        enableHardwareAcceleration: true,
      ),
    );

    _applySafeProperties();

    player.stream.error.listen((error) {
      LogService.instance.error('PLAYER', 'media_kit player error: $error');
    });
  }

  void _applySafeProperties() {
    try {
      final p = player.platform as dynamic;
      if (p != null) {
        p.setProperty('demuxer-lavf-probescore', '15');
        p.setProperty('demuxer-lavf-analyzeduration', '5.0');
        p.setProperty('demuxer-lavf-buffersize', '4194304');
        p.setProperty('force-seekable', 'yes');
        p.setProperty('hr-seek', 'default');
      }
    } catch (_) {}
  }

  Future<void> openMedia(String uri, {bool autoPlay = true}) async {
    try {
      LogService.instance.info('PLAYER', 'media_kit opening media uri: $uri');
      await player.open(
        Media(uri),
        play: autoPlay,
      );
      if (autoPlay) {
        await player.play();
      }
    } catch (e, st) {
      LogService.instance.error('PLAYER', 'Error opening media "$uri": $e', e, st);
    }
  }

  Future<void> play() => player.play();
  Future<void> pause() => player.pause();
  Future<void> stop() => player.stop();
  Future<void> playOrPause() => player.playOrPause();
  Future<void> seek(Duration duration) => player.seek(duration);

  Future<void> setVolume(double volume) {
    // Volume from 0.0 to 100.0
    return player.setVolume(volume.clamp(0.0, 100.0));
  }

  Future<void> setRate(double rate) {
    return player.setRate(rate.clamp(0.25, 3.0));
  }

  Future<void> setAudioTrack(AudioTrack track) {
    return player.setAudioTrack(track);
  }

  Future<void> setSubtitleTrack(SubtitleTrack track) {
    return player.setSubtitleTrack(track);
  }

  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      player.dispose();
    }
  }
}
