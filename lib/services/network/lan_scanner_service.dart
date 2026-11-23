import 'dart:async';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import '../log_service.dart';

class DiscoveredDevice {
  final String ip;
  final String hostname;
  final int port;
  final String serviceType; // SMB, SFTP, WebDAV, FTP
  final int? pingMs;

  const DiscoveredDevice({
    required this.ip,
    required this.hostname,
    required this.port,
    required this.serviceType,
    this.pingMs,
  });
}

class LanScannerService {
  final _networkInfo = NetworkInfo();

  /// Gets the current Wi-Fi IP address.
  Future<String?> getLocalIp() async {
    try {
      return await _networkInfo.getWifiIP();
    } catch (_) {
      return null;
    }
  }

  /// Scans the local network for active file sharing and storage servers.
  Future<List<DiscoveredDevice>> scanLocalNetwork({
    void Function(double progress)? onProgress,
    int hostRange = 100, // Scan top 100 subnet addresses for optimal speed
  }) async {
    final List<DiscoveredDevice> discovered = [];

    String? localIp = await getLocalIp();
    if (localIp == null || localIp.isEmpty || localIp == '127.0.0.1') {
      LogService.instance.warn('LAN_SCAN', 'No valid Wi-Fi IP found for LAN scan');
      return discovered;
    }

    final subnet = localIp.substring(0, localIp.lastIndexOf('.'));
    LogService.instance.info('LAN_SCAN', 'Scanning subnet: $subnet.1-$hostRange (local: $localIp)');

    final totalHosts = hostRange;
    int completed = 0;

    // Scan in concurrent batches of 20 to protect Android socket descriptor limits
    const batchSize = 20;
    for (int batchStart = 1; batchStart <= totalHosts; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize - 1).clamp(1, totalHosts);
      final batchFutures = <Future<void>>[];

      for (int i = batchStart; i <= batchEnd; i++) {
        final targetIp = '$subnet.$i';
        if (targetIp == localIp) {
          completed++;
          continue;
        }

        batchFutures.add(_probeHost(targetIp).then((device) {
          if (device != null) {
            discovered.add(device);
          }
          completed++;
          onProgress?.call(completed / totalHosts);
        }));
      }

      await Future.wait(batchFutures);
    }

    LogService.instance.info('LAN_SCAN', 'Scan complete. Found ${discovered.length} devices');
    return discovered;
  }

  /// Probes standard network storage ports on a host: SMB (445), SFTP (22), Synology/WebDAV (5000, 8080, 80), FTP (21).
  Future<DiscoveredDevice?> _probeHost(String ip) async {
    // 1. Check SMB (Port 445)
    final smbDevice = await _testPort(ip, 445, 'SMB (Windows/NAS/Samba)', 'SMB');
    if (smbDevice != null) return smbDevice;

    // 2. Check SFTP / SSH (Port 22)
    final sftpDevice = await _testPort(ip, 22, 'SFTP (Linux / SSH Storage)', 'SFTP');
    if (sftpDevice != null) return sftpDevice;

    // 3. Check Synology DSM / WebDAV (Port 5000)
    final synoDevice = await _testPort(ip, 5000, 'Synology NAS / WebDAV', 'WebDAV');
    if (synoDevice != null) return synoDevice;

    // 4. Check WebDAV / HTTP (Port 80)
    final webDevice = await _testPort(ip, 80, 'WebDAV / HTTP Server', 'WebDAV / HTTP');
    if (webDevice != null) return webDevice;

    // 5. Check FTP (Port 21)
    final ftpDevice = await _testPort(ip, 21, 'FTP Server', 'FTP');
    if (ftpDevice != null) return ftpDevice;

    return null;
  }

  Future<DiscoveredDevice?> _testPort(String ip, int port, String description, String serviceType) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 320),
      );
      socket.destroy();
      sw.stop();

      // Attempt reverse DNS lookup
      String resolvedHost = description;
      try {
        final hostLookup = await InternetAddress(ip).reverse().timeout(const Duration(milliseconds: 250));
        if (hostLookup.host.isNotEmpty && hostLookup.host != ip) {
          resolvedHost = '${hostLookup.host} ($serviceType)';
        }
      } catch (_) {}

      return DiscoveredDevice(
        ip: ip,
        hostname: resolvedHost,
        port: port,
        serviceType: serviceType,
        pingMs: sw.elapsedMilliseconds,
      );
    } catch (_) {
      return null;
    }
  }

  /// Quick ping check to see if a specific host and port are reachable.
  static Future<int?> pingHost(String host, int port, {int timeoutMs = 600}) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      socket.destroy();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }
}
