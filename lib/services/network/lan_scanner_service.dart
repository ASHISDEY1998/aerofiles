import 'dart:async';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

class DiscoveredDevice {
  final String ip;
  final String hostname;
  final int port;
  final String serviceType; // SMB, WebDAV, FTP

  const DiscoveredDevice({
    required this.ip,
    required this.hostname,
    required this.port,
    required this.serviceType,
  });
}

class LanScannerService {
  final _networkInfo = NetworkInfo();

  Future<List<DiscoveredDevice>> scanLocalNetwork({
    void Function(double progress)? onProgress,
  }) async {
    final List<DiscoveredDevice> discovered = [];

    String? localIp;
    try {
      localIp = await _networkInfo.getWifiIP();
    } catch (_) {}

    if (localIp == null || localIp.isEmpty || localIp == '127.0.0.1') {
      return discovered;
    }

    final subnet = localIp.substring(0, localIp.lastIndexOf('.'));
    const totalHosts = 50; // Scan the primary 50 host pool for quick feedback
    int completed = 0;

    final futures = <Future<void>>[];

    for (int i = 1; i <= totalHosts; i++) {
      final targetIp = '$subnet.$i';
      if (targetIp == localIp) continue;

      futures.add(() async {
        // Probe SMB Port 445 first
        try {
          final socket = await Socket.connect(
            targetIp,
            445,
            timeout: const Duration(milliseconds: 350),
          );
          socket.destroy();
          discovered.add(
            DiscoveredDevice(
              ip: targetIp,
              hostname: 'SMB Share ($targetIp)',
              port: 445,
              serviceType: 'SMB',
            ),
          );
        } catch (_) {
          // Check port 80 / WebDAV
          try {
            final socket = await Socket.connect(
              targetIp,
              80,
              timeout: const Duration(milliseconds: 300),
            );
            socket.destroy();
            discovered.add(
              DiscoveredDevice(
                ip: targetIp,
                hostname: 'Web Server ($targetIp)',
                port: 80,
                serviceType: 'WebDAV / HTTP',
              ),
            );
          } catch (_) {}
        } finally {
          completed++;
          onProgress?.call(completed / totalHosts);
        }
      }());
    }

    await Future.wait(futures);
    return discovered;
  }
}
