import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/aerolink_models.dart';
import '../log_service.dart';

class AeroLinkService {
  static final AeroLinkService instance = AeroLinkService._();
  AeroLinkService._();

  static const int discoveryPort = 52830;
  static const int defaultServerPort = 52831;

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  String _deviceId = '';
  String _deviceName = '';
  String _pairingPin = '';
  final List<AeroLinkShare> _sharedFolders = [];
  final Map<String, String> _pairedClients = {}; // clientDeviceId -> token
  final Map<String, String> _remoteAuthTokens = {}; // remoteDeviceId -> token

  final ValueNotifier<bool> isSharingActive = ValueNotifier<bool>(false);
  final ValueNotifier<List<AeroLinkDevice>> nearbyDevices = ValueNotifier<List<AeroLinkDevice>>([]);
  final ValueNotifier<bool> isScanning = ValueNotifier<bool>(false);
  final ValueNotifier<int> scanSecondsRemaining = ValueNotifier<int>(0);

  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  Timer? _beaconTimer;
  Timer? _watchdogTimer;
  Timer? _scanCountdownTimer;
  Timer? _scanPeriodicTimer;

  String get deviceId => _deviceId;
  String get deviceName => _deviceName;
  String get pairingPin => _pairingPin;
  List<AeroLinkShare> get sharedFolders => List.unmodifiable(_sharedFolders);

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();

    // 1. Device ID
    _deviceId = _prefs.getString('aerolink_device_id') ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = _generateUuid();
      await _prefs.setString('aerolink_device_id', _deviceId);
    }

    // 2. Device Name
    _deviceName = _prefs.getString('aerolink_device_name') ?? '';
    if (_deviceName.isEmpty) {
      final host = Platform.localHostname;
      _deviceName = host.isNotEmpty && host != 'localhost' ? host : 'AeroFiles Device';
      await _prefs.setString('aerolink_device_name', _deviceName);
    }

    // 3. Pairing PIN
    _pairingPin = _prefs.getString('aerolink_pairing_pin') ?? '';
    if (_pairingPin.isEmpty) {
      _pairingPin = _generatePin();
      await _prefs.setString('aerolink_pairing_pin', _pairingPin);
    }

    // 4. Shared Folders
    final sharesJson = _prefs.getString('aerolink_shares_json') ?? '';
    if (sharesJson.isNotEmpty) {
      try {
        final list = (jsonDecode(sharesJson) as List<dynamic>?) ?? [];
        _sharedFolders.clear();
        for (final item in list) {
          _sharedFolders.add(AeroLinkShare.fromJson(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    // Default shared folder if none configured
    if (_sharedFolders.isEmpty) {
      final commonPaths = ['/storage/emulated/0/Movies', '/storage/emulated/0/Download'];
      for (final cp in commonPaths) {
        if (Directory(cp).existsSync()) {
          _sharedFolders.add(
            AeroLinkShare(
              id: 'share_${DateTime.now().millisecondsSinceEpoch}',
              name: p.basename(cp),
              localPath: cp,
              addedAt: DateTime.now(),
            ),
          );
          break;
        }
      }
      _saveShares();
    }

    // 5. Auth Tokens
    final pairedJson = _prefs.getString('aerolink_paired_clients_json') ?? '';
    if (pairedJson.isNotEmpty) {
      try {
        final map = (jsonDecode(pairedJson) as Map<String, dynamic>?) ?? {};
        _pairedClients.addAll(map.map((k, v) => MapEntry(k, v.toString())));
      } catch (_) {}
    }

    final remoteTokensJson = _prefs.getString('aerolink_remote_tokens_json') ?? '';
    if (remoteTokensJson.isNotEmpty) {
      try {
        final map = (jsonDecode(remoteTokensJson) as Map<String, dynamic>?) ?? {};
        _remoteAuthTokens.addAll(map.map((k, v) => MapEntry(k, v.toString())));
      } catch (_) {}
    }

    _isInitialized = true;

    // Start background receiver for peer discovery
    await _startDiscoveryListener();
  }

  // --- Configuration ---

  Future<void> setDeviceName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _deviceName = trimmed;
    await _prefs.setString('aerolink_device_name', _deviceName);
  }

  Future<void> regeneratePin() async {
    _pairingPin = _generatePin();
    await _prefs.setString('aerolink_pairing_pin', _pairingPin);
  }

  Future<void> addShare({required String name, required String localPath}) async {
    if (!Directory(localPath).existsSync()) return;
    _sharedFolders.removeWhere((s) => s.localPath == localPath);
    _sharedFolders.add(
      AeroLinkShare(
        id: 'share_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}',
        name: name,
        localPath: localPath,
        addedAt: DateTime.now(),
      ),
    );
    await _saveShares();
  }

  Future<void> removeShare(String id) async {
    _sharedFolders.removeWhere((s) => s.id == id);
    await _saveShares();
  }

  Future<void> _saveShares() async {
    final jsonList = _sharedFolders.map((s) => s.toJson()).toList();
    await _prefs.setString('aerolink_shares_json', jsonEncode(jsonList));
  }

  // --- Start / Stop Sharing Server ---

  Future<bool> startSharing() async {
    if (isSharingActive.value) return true;
    await init();

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, defaultServerPort);
      _server!.listen(_handleHttpRequest);
      isSharingActive.value = true;

      // Start periodic UDP beacon
      _startBeaconBroadcaster();
      LogService.instance.info('AEROLINK', 'AeroLink server running on port $defaultServerPort');
      return true;
    } catch (e, st) {
      LogService.instance.error('AEROLINK', 'Failed to start AeroLink server: $e', e, st);
      isSharingActive.value = false;
      return false;
    }
  }

  Future<void> stopSharing() async {
    // Send farewell beacon before stopping
    _sendFarewellBeacon();

    _beaconTimer?.cancel();
    _beaconTimer = null;

    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }
    isSharingActive.value = false;
    LogService.instance.info('AEROLINK', 'AeroLink sharing stopped');
  }

  // --- HTTP Request Handler ---

  Future<void> _handleHttpRequest(HttpRequest request) async {
    final path = request.uri.path;
    final res = request.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Headers', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');

    if (request.method == 'OPTIONS') {
      res.statusCode = HttpStatus.ok;
      await res.close();
      return;
    }

    try {
      // 1. Ping endpoint
      if (path == '/aerolink/ping') {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({
          'status': 'ok',
          'deviceId': _deviceId,
          'deviceName': _deviceName,
          'sharesCount': _sharedFolders.length,
          'version': '2.0.0',
        }));
        await res.close();
        return;
      }

      // 2. Pair endpoint (Protected by 6-digit PIN)
      if (path == '/aerolink/pair' && request.method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final data = jsonDecode(bodyStr) as Map<String, dynamic>;
        final pin = (data['pin'] as String?)?.trim() ?? '';
        final clientDeviceId = (data['clientDeviceId'] as String?) ?? '';
        final clientDeviceName = (data['clientDeviceName'] as String?) ?? 'Remote Device';

        if (pin == _pairingPin) {
          final token = _generateUuid();
          _pairedClients[clientDeviceId] = token;
          await _prefs.setString('aerolink_paired_clients_json', jsonEncode(_pairedClients));
          LogService.instance.info('AEROLINK', 'Successfully paired client: $clientDeviceName ($clientDeviceId)');

          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({'success': true, 'token': token}));
          await res.close();
          return;
        } else {
          res.statusCode = HttpStatus.unauthorized;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({'success': false, 'error': 'Invalid Pairing PIN'}));
          await res.close();
          return;
        }
      }

      // 3. Security / Auth Verification for all resource endpoints
      final authHeader = request.headers.value('X-Aero-Auth') ?? request.uri.queryParameters['auth'] ?? '';
      if (!_isAuthorizedToken(authHeader)) {
        res.statusCode = HttpStatus.forbidden;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'error': 'Access Denied: AeroFiles Authorization Required'}));
        await res.close();
        return;
      }

      // 4. List Shared Folders
      if (path == '/aerolink/shares') {
        final list = _sharedFolders.map((s) {
          int count = 0;
          try {
            final dir = Directory(s.localPath);
            if (dir.existsSync()) count = dir.listSync().length;
          } catch (_) {}
          return {
            'id': s.id,
            'name': s.name,
            'itemCount': count,
          };
        }).toList();

        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(list));
        await res.close();
        return;
      }

      // 5. Browse inside a shared folder
      if (path == '/aerolink/browse') {
        final shareId = request.uri.queryParameters['shareId'] ?? '';
        final subpath = request.uri.queryParameters['subpath'] ?? '';

        final share = _sharedFolders.firstWhere(
          (s) => s.id == shareId || s.name == shareId,
          orElse: () => throw Exception('Share not found'),
        );

        final targetDir = Directory(p.normalize(p.join(share.localPath, subpath)));
        if (!targetDir.path.startsWith(share.localPath) || !targetDir.existsSync()) {
          res.statusCode = HttpStatus.notFound;
          res.write(jsonEncode({'error': 'Directory not found'}));
          await res.close();
          return;
        }

        final items = <Map<String, dynamic>>[];
        final entities = targetDir.listSync(followLinks: false);
        for (final e in entities) {
          try {
            final stat = e.statSync();
            final name = p.basename(e.path);
            if (name.startsWith('.')) continue; // exclude hidden
            final relPath = p.relative(e.path, from: share.localPath);
            items.add({
              'name': name,
              'path': relPath,
              'size': stat.size,
              'isDirectory': e is Directory,
              'modified': stat.modified.toIso8601String(),
            });
          } catch (_) {}
        }

        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(items));
        await res.close();
        return;
      }

      // 6. Zero-Download Stream Endpoint (Full HTTP Byte-Range support for media_kit / libmpv)
      if (path == '/aerolink/stream') {
        final shareId = request.uri.queryParameters['shareId'] ?? '';
        final relPath = request.uri.queryParameters['path'] ?? '';

        final share = _sharedFolders.firstWhere(
          (s) => s.id == shareId || s.name == shareId,
          orElse: () => throw Exception('Share not found'),
        );

        final targetFile = File(p.normalize(p.join(share.localPath, relPath)));
        if (!targetFile.path.startsWith(share.localPath) || !targetFile.existsSync()) {
          res.statusCode = HttpStatus.notFound;
          await res.close();
          return;
        }

        final fileLength = await targetFile.length();
        final mimeType = lookupMimeType(targetFile.path) ?? 'application/octet-stream';
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

        res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        res.headers.set(HttpHeaders.contentTypeHeader, mimeType);

        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          // Parse Range: bytes=start-end
          final parts = rangeHeader.substring(6).split('-');
          final start = int.tryParse(parts[0]) ?? 0;
          final end = (parts.length > 1 && parts[1].isNotEmpty)
              ? (int.tryParse(parts[1]) ?? fileLength - 1)
              : fileLength - 1;

          final rangeLength = end - start + 1;
          res.statusCode = HttpStatus.partialContent;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileLength');
          res.headers.contentLength = rangeLength;

          final stream = targetFile.openRead(start, end + 1);
          await res.addStream(stream);
          await res.close();
        } else {
          res.statusCode = HttpStatus.ok;
          res.headers.contentLength = fileLength;
          final stream = targetFile.openRead();
          await res.addStream(stream);
          await res.close();
        }
        return;
      }

      // 7. Download Endpoint
      if (path == '/aerolink/download') {
        final shareId = request.uri.queryParameters['shareId'] ?? '';
        final relPath = request.uri.queryParameters['path'] ?? '';

        final share = _sharedFolders.firstWhere((s) => s.id == shareId || s.name == shareId);
        final targetFile = File(p.normalize(p.join(share.localPath, relPath)));
        if (!targetFile.existsSync()) {
          res.statusCode = HttpStatus.notFound;
          await res.close();
          return;
        }

        final name = p.basename(targetFile.path);
        res.headers.set('Content-Disposition', 'attachment; filename="$name"');
        res.headers.contentLength = await targetFile.length();
        await res.addStream(targetFile.openRead());
        await res.close();
        return;
      }

      res.statusCode = HttpStatus.notFound;
      await res.close();
    } catch (e, st) {
      LogService.instance.error('AEROLINK', 'HTTP error on $path: $e', e, st);
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }

  bool _isAuthorizedToken(String token) {
    if (token.isEmpty) return false;
    return _pairedClients.values.contains(token);
  }

  // --- UDP Discovery & Presence Engine ---

  Future<void> _startDiscoveryListener() async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _discoverySocket!.broadcastEnabled = true;

      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket?.receive();
          if (datagram != null) {
            _processBeaconDatagram(datagram);
          }
        }
      });

      // Watchdog timer checks offline status
      _watchdogTimer?.cancel();
      _watchdogTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _checkPeerPresence();
      });

      LogService.instance.info('AEROLINK', 'Discovery listener active on port $discoveryPort');
    } catch (e) {
      LogService.instance.warn('AEROLINK', 'Could not bind discovery socket: $e');
    }
  }

  void _startBeaconBroadcaster() {
    _beaconTimer?.cancel();
    _broadcastBeacon(); // Immediate initial beacon
    _beaconTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _broadcastBeacon();
    });
  }

  String? _getSubnetBroadcast(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}.255';
    }
    return null;
  }

  Future<void> _broadcastBeacon({bool isBye = false}) async {
    try {
      final ip = await _getLocalIp();
      final packet = jsonEncode({
        'proto': 'aerolink/1.0',
        'type': 'beacon',
        'deviceId': _deviceId,
        'deviceName': _deviceName,
        'ip': ip,
        'port': defaultServerPort,
        'sharesCount': isBye ? 0 : _sharedFolders.length,
        'isOnline': !isBye,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final bytes = utf8.encode(packet);
      // 1. Global broadcast
      _discoverySocket?.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);

      // 2. Subnet targeted broadcast (e.g. 192.168.1.255)
      final subnet = _getSubnetBroadcast(ip);
      if (subnet != null && subnet != '255.255.255.255') {
        _discoverySocket?.send(bytes, InternetAddress(subnet), discoveryPort);
      }
    } catch (_) {}
  }

  void _sendFarewellBeacon() {
    _broadcastBeacon(isBye: true);
  }

  // --- Active 30-Second Discovery Scan ---

  void startScan({int durationSeconds = 30}) {
    if (isScanning.value) return;
    isScanning.value = true;
    scanSecondsRemaining.value = durationSeconds;

    LogService.instance.info('AEROLINK', 'Starting active network scan for $durationSeconds seconds');

    // Broadcast discovery query immediately
    broadcastDiscoveryQuery();

    // Re-query every 3 seconds while active
    _scanPeriodicTimer?.cancel();
    _scanPeriodicTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      broadcastDiscoveryQuery();
    });

    // 1-second countdown timer
    _scanCountdownTimer?.cancel();
    _scanCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (scanSecondsRemaining.value <= 1) {
        stopScan();
      } else {
        scanSecondsRemaining.value--;
      }
    });
  }

  void stopScan() {
    _scanCountdownTimer?.cancel();
    _scanPeriodicTimer?.cancel();
    _scanCountdownTimer = null;
    _scanPeriodicTimer = null;
    isScanning.value = false;
    scanSecondsRemaining.value = 0;
    LogService.instance.info('AEROLINK', 'AeroLink network scan stopped');
  }

  Future<void> broadcastDiscoveryQuery() async {
    try {
      final ip = await _getLocalIp();
      final packet = jsonEncode({
        'proto': 'aerolink/1.0',
        'type': 'query',
        'fromDeviceId': _deviceId,
        'fromDeviceName': _deviceName,
        'ip': ip,
        'port': defaultServerPort,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final bytes = utf8.encode(packet);
      // 1. Send query to 255.255.255.255
      _discoverySocket?.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);

      // 2. Send query to local subnet broadcast
      final subnet = _getSubnetBroadcast(ip);
      if (subnet != null && subnet != '255.255.255.255') {
        _discoverySocket?.send(bytes, InternetAddress(subnet), discoveryPort);
      }
    } catch (_) {}
  }

  Future<void> _sendDirectBeacon(InternetAddress targetAddress, int targetPort) async {
    try {
      final ip = await _getLocalIp();
      final packet = jsonEncode({
        'proto': 'aerolink/1.0',
        'type': 'beacon',
        'deviceId': _deviceId,
        'deviceName': _deviceName,
        'ip': ip,
        'port': defaultServerPort,
        'sharesCount': _sharedFolders.length,
        'isOnline': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final bytes = utf8.encode(packet);
      _discoverySocket?.send(bytes, targetAddress, targetPort);
    } catch (_) {}
  }

  void _processBeaconDatagram(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data);
      final json = jsonDecode(text) as Map<String, dynamic>;

      if (json['proto'] != 'aerolink/1.0') return;

      final type = json['type'] as String? ?? 'beacon';
      if (type == 'query') {
        // Someone on the network is scanning! If we are sharing, reply immediately directly to them (unicast)
        final fromId = json['fromDeviceId'] as String? ?? '';
        if (fromId != _deviceId && isSharingActive.value) {
          _sendDirectBeacon(datagram.address, datagram.port);
        }
        return;
      }

      final remoteId = json['deviceId'] as String? ?? '';
      if (remoteId.isEmpty || remoteId == _deviceId) return; // Ignore own beacon

      final name = json['deviceName'] as String? ?? 'AeroFiles Device';
      final ip = (json['ip'] as String?)?.isNotEmpty == true ? json['ip'] : datagram.address.address;
      final port = (json['port'] as int?) ?? defaultServerPort;
      final sharesCount = (json['sharesCount'] as int?) ?? 0;
      final isOnline = (json['isOnline'] as bool?) ?? true;

      final currentList = List<AeroLinkDevice>.from(nearbyDevices.value);
      final index = currentList.indexWhere((d) => d.deviceId == remoteId);

      if (index != -1) {
        final existing = currentList[index];
        existing.deviceName = name;
        existing.ip = ip;
        existing.port = port;
        existing.sharesCount = sharesCount;
        existing.lastSeen = DateTime.now();
        existing.isOnline = isOnline;
        existing.authToken = _remoteAuthTokens[remoteId];
      } else {
        currentList.add(
          AeroLinkDevice(
            deviceId: remoteId,
            deviceName: name,
            ip: ip,
            port: port,
            sharesCount: sharesCount,
            lastSeen: DateTime.now(),
            isOnline: isOnline,
            authToken: _remoteAuthTokens[remoteId],
          ),
        );
      }

      nearbyDevices.value = currentList;
    } catch (_) {}
  }

  void _checkPeerPresence() {
    final now = DateTime.now();
    final currentList = List<AeroLinkDevice>.from(nearbyDevices.value);
    bool changed = false;

    for (final dev in currentList) {
      // Keep devices marked online for 60 seconds of silence to prevent Wi-Fi power-save drops
      if (dev.isOnline && now.difference(dev.lastSeen).inSeconds > 60) {
        dev.isOnline = false; // Transition to "Device Offline" with device name!
        changed = true;
      }
    }

    // Prune devices offline for more than 30 minutes
    currentList.removeWhere((d) => !d.isOnline && now.difference(d.lastSeen).inMinutes > 30);

    if (changed) {
      nearbyDevices.value = currentList;
    }
  }

  // --- Client Pairing Action ---

  Future<bool> pairWithDevice(AeroLinkDevice device, String pin) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);

      final req = await client.postUrl(Uri.parse('http://${device.ip}:${device.port}/aerolink/pair'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'pin': pin.trim(),
        'clientDeviceId': _deviceId,
        'clientDeviceName': _deviceName,
      }));

      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await utf8.decodeStream(res);
        final json = jsonDecode(body) as Map<String, dynamic>;
        final token = json['token'] as String? ?? '';
        if (token.isNotEmpty) {
          _remoteAuthTokens[device.deviceId] = token;
          await _prefs.setString('aerolink_remote_tokens_json', jsonEncode(_remoteAuthTokens));
          device.authToken = token;

          final list = List<AeroLinkDevice>.from(nearbyDevices.value);
          nearbyDevices.value = list;
          client.close();
          return true;
        }
      }
      client.close();
      return false;
    } catch (e) {
      LogService.instance.warn('AEROLINK', 'Pairing failed: $e');
      return false;
    }
  }

  void unpairDevice(String deviceId) {
    _remoteAuthTokens.remove(deviceId);
    _prefs.setString('aerolink_remote_tokens_json', jsonEncode(_remoteAuthTokens));
    final list = List<AeroLinkDevice>.from(nearbyDevices.value);
    final dev = list.where((d) => d.deviceId == deviceId).firstOrNull;
    if (dev != null) dev.authToken = null;
    nearbyDevices.value = list;
  }

  void forgetDevice(String deviceId) {
    _remoteAuthTokens.remove(deviceId);
    _prefs.setString('aerolink_remote_tokens_json', jsonEncode(_remoteAuthTokens));
    final list = List<AeroLinkDevice>.from(nearbyDevices.value);
    list.removeWhere((d) => d.deviceId == deviceId);
    nearbyDevices.value = list;
  }

  Future<String> getLocalIp() => _getLocalIp();

  // --- Utilities ---

  Future<String> _getLocalIp() async {
    try {
      final info = NetworkInfo();
      final wifi = await info.getWifiIP();
      if (wifi != null && wifi.isNotEmpty) return wifi;
    } catch (_) {}

    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  String _generateUuid() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _generatePin() {
    final rand = Random.secure();
    final pinNum = 100000 + rand.nextInt(900000);
    return pinNum.toString();
  }

  void dispose() {
    _scanCountdownTimer?.cancel();
    _scanPeriodicTimer?.cancel();
    _beaconTimer?.cancel();
    _watchdogTimer?.cancel();
    _discoverySocket?.close();
    _server?.close(force: true);
  }
}
