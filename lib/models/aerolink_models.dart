
class AeroLinkShare {
  final String id;
  final String name;
  final String localPath;
  final DateTime addedAt;
  final bool isFile;

  AeroLinkShare({
    required this.id,
    required this.name,
    required this.localPath,
    required this.addedAt,
    this.isFile = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'localPath': localPath,
        'addedAt': addedAt.toIso8601String(),
        'isFile': isFile,
      };

  factory AeroLinkShare.fromJson(Map<String, dynamic> json) => AeroLinkShare(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        localPath: json['localPath'] as String? ?? '',
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
        isFile: (json['isFile'] as bool?) ?? false,
      );
}

class AeroLinkDevice {
  final String deviceId;
  String deviceName;
  String ip;
  int port;
  int sharesCount;
  DateTime lastSeen;
  bool isOnline;
  String? authToken;

  AeroLinkDevice({
    required this.deviceId,
    required this.deviceName,
    required this.ip,
    required this.port,
    this.sharesCount = 0,
    required this.lastSeen,
    this.isOnline = true,
    this.authToken,
  });

  bool get isPaired => authToken != null && authToken!.isNotEmpty;

  AeroLinkDevice copyWith({
    String? deviceId,
    String? deviceName,
    String? ip,
    int? port,
    int? sharesCount,
    DateTime? lastSeen,
    bool? isOnline,
    String? authToken,
  }) {
    return AeroLinkDevice(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      sharesCount: sharesCount ?? this.sharesCount,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
      authToken: authToken ?? this.authToken,
    );
  }

  String get subtitle {
    if (isOnline) {
      if (sharesCount <= 0) return 'Online • No folders shared';
      return 'Online • $sharesCount shared folder${sharesCount == 1 ? '' : 's'}';
    } else {
      final diff = DateTime.now().difference(lastSeen);
      if (diff.inMinutes < 1) return 'Device Offline • Just now';
      if (diff.inMinutes < 60) return 'Device Offline • ${diff.inMinutes}m ago';
      return 'Device Offline • ${diff.inHours}h ago';
    }
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'ip': ip,
        'port': port,
        'sharesCount': sharesCount,
        'lastSeen': lastSeen.toIso8601String(),
        'isOnline': isOnline,
        'authToken': authToken,
      };

  factory AeroLinkDevice.fromJson(Map<String, dynamic> json) => AeroLinkDevice(
        deviceId: json['deviceId'] as String? ?? '',
        deviceName: json['deviceName'] as String? ?? 'AeroFiles Device',
        ip: json['ip'] as String? ?? '',
        port: (json['port'] as int?) ?? 52831,
        sharesCount: (json['sharesCount'] as int?) ?? 0,
        lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? DateTime.now(),
        isOnline: (json['isOnline'] as bool?) ?? true,
        authToken: json['authToken'] as String?,
      );
}
