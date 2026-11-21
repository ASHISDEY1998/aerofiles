enum ProtocolType {
  smb,
  webdav,
  ftp,
  sftp,
  gdrive,
  onedrive,
  dropbox,
}

class NetworkConnection {
  final String id;
  final String name;
  final ProtocolType protocol;
  final String host;
  final int port;
  final String path;
  final String username;
  final String password;
  final bool isAnonymous;
  final DateTime lastConnected;

  const NetworkConnection({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    this.path = '/',
    this.username = '',
    this.password = '',
    this.isAnonymous = false,
    required this.lastConnected,
  });

  String get protocolName {
    switch (protocol) {
      case ProtocolType.smb:
        return 'SMB / Windows Share';
      case ProtocolType.webdav:
        return 'WebDAV';
      case ProtocolType.ftp:
        return 'FTP';
      case ProtocolType.sftp:
        return 'SFTP (SSH)';
      case ProtocolType.gdrive:
        return 'Google Drive';
      case ProtocolType.onedrive:
        return 'OneDrive';
      case ProtocolType.dropbox:
        return 'Dropbox';
    }
  }

  static int defaultPortFor(ProtocolType protocol) {
    switch (protocol) {
      case ProtocolType.smb:
        return 445;
      case ProtocolType.webdav:
        return 443;
      case ProtocolType.ftp:
        return 21;
      case ProtocolType.sftp:
        return 22;
      default:
        return 80;
    }
  }

  String get cleanSharePath {
    var p = path.trim();
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'protocol': protocol.index,
      'host': host,
      'port': port,
      'path': path,
      'username': username,
      'password': password,
      'isAnonymous': isAnonymous,
      'lastConnected': lastConnected.toIso8601String(),
    };
  }

  factory NetworkConnection.fromJson(Map<String, dynamic> json) {
    return NetworkConnection(
      id: json['id'] as String,
      name: json['name'] as String,
      protocol: ProtocolType.values[json['protocol'] as int],
      host: json['host'] as String,
      port: json['port'] as int,
      path: json['path'] as String? ?? '/',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      isAnonymous: json['isAnonymous'] as bool? ?? false,
      lastConnected: DateTime.parse(json['lastConnected'] as String),
    );
  }
}
