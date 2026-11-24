import 'package:flutter_test/flutter_test.dart';
import 'package:aerofiles/models/aerolink_models.dart';
import 'package:aerofiles/services/vfs/aerolink_vfs.dart';

void main() {
  group('AeroLinkShare Tests', () {
    test('AeroLinkShare serialization and deserialization', () {
      final share = AeroLinkShare(
        id: 'share_123',
        name: 'Movies',
        localPath: '/storage/emulated/0/Movies',
        addedAt: DateTime(2026, 11, 24, 12, 0, 0),
      );

      final json = share.toJson();
      expect(json['id'], 'share_123');
      expect(json['name'], 'Movies');
      expect(json['localPath'], '/storage/emulated/0/Movies');
      expect(json['addedAt'], '2026-11-24T12:00:00.000');

      final reconstructed = AeroLinkShare.fromJson(json);
      expect(reconstructed.id, share.id);
      expect(reconstructed.name, share.name);
      expect(reconstructed.localPath, share.localPath);
      expect(reconstructed.addedAt, share.addedAt);
    });
  });

  group('AeroLinkDevice Tests', () {
    test('AeroLinkDevice subtitle displays online status and folder count correctly', () {
      final onlineDeviceNoShares = AeroLinkDevice(
        deviceId: 'dev_1',
        deviceName: "Living Room TV",
        ip: '192.168.1.100',
        port: 52831,
        sharesCount: 0,
        lastSeen: DateTime.now(),
        isOnline: true,
      );
      expect(onlineDeviceNoShares.subtitle, 'Online • No folders shared');

      final onlineDeviceOneShare = onlineDeviceNoShares.copyWith(sharesCount: 1);
      expect(onlineDeviceOneShare.subtitle, 'Online • 1 shared folder');

      final onlineDeviceMultiShares = onlineDeviceNoShares.copyWith(sharesCount: 4);
      expect(onlineDeviceMultiShares.subtitle, 'Online • 4 shared folders');
    });

    test('AeroLinkDevice subtitle displays offline status with last seen elapsed time', () {
      final offlineDeviceJustNow = AeroLinkDevice(
        deviceId: 'dev_2',
        deviceName: "Bedroom Tablet",
        ip: '192.168.1.101',
        port: 52831,
        sharesCount: 2,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 30)),
        isOnline: false,
      );
      expect(offlineDeviceJustNow.subtitle, 'Device Offline • Just now');

      final offlineDeviceMinsAgo = offlineDeviceJustNow.copyWith(
        lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(offlineDeviceMinsAgo.subtitle, 'Device Offline • 5m ago');

      final offlineDeviceHoursAgo = offlineDeviceJustNow.copyWith(
        lastSeen: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(offlineDeviceHoursAgo.subtitle, 'Device Offline • 2h ago');
    });

    test('AeroLinkDevice pairing status check', () {
      final unconfirmed = AeroLinkDevice(
        deviceId: 'dev_3',
        deviceName: "Work Phone",
        ip: '192.168.1.102',
        port: 52831,
        sharesCount: 1,
        lastSeen: DateTime.now(),
        isOnline: true,
      );
      expect(unconfirmed.isPaired, isFalse);

      final paired = unconfirmed.copyWith(authToken: 'sec_token_xyz987');
      expect(paired.isPaired, isTrue);
    });
  });

  group('AeroLinkVfs Streaming & Playback URI Tests', () {
    test('AeroLinkVfs generates authenticated streaming playback URI for media kit', () async {
      final device = AeroLinkDevice(
        deviceId: 'dev_stream',
        deviceName: "Home Server",
        ip: '192.168.1.50',
        port: 52831,
        sharesCount: 2,
        lastSeen: DateTime.now(),
        isOnline: true,
        authToken: 'test_token_abc123',
      );

      final vfs = AeroLinkVfs(device: device, authToken: device.authToken!);
      expect(vfs.displayName, "Home Server");
      expect(vfs.rootPath, '/');

      final mediaUri = await vfs.getPlaybackUri('/Movies/Inception.mp4');
      expect(
        mediaUri,
        'http://192.168.1.50:52831/aerolink/stream?shareId=Movies&path=Inception.mp4&auth=test_token_abc123',
      );

      final imageUri = await vfs.getPlaybackUri('/Photos/Summer.jpg');
      expect(
        imageUri,
        'http://192.168.1.50:52831/aerolink/stream?shareId=Photos&path=Summer.jpg&auth=test_token_abc123',
      );
    });
  });
}
