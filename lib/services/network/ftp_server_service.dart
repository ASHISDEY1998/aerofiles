import 'dart:async';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path/path.dart' as p;

class FtpServerService {
  HttpServer? _server;
  bool _isRunning = false;
  int _port = 8080;
  String _hostIp = '127.0.0.1';
  String _rootPath = '';

  bool get isRunning => _isRunning;
  int get port => _port;
  String get hostIp => _hostIp;
  String get serverUrl => 'http://$_hostIp:$_port';

  final _networkInfo = NetworkInfo();

  Future<bool> startServer({int port = 8080, required String rootPath}) async {
    if (_isRunning) await stopServer();

    _port = port;
    _rootPath = rootPath;

    try {
      // Find local IP address
      String? wifiIp;
      try {
        wifiIp = await _networkInfo.getWifiIP();
      } catch (_) {}

      if (wifiIp == null || wifiIp.isEmpty) {
        // Fallback: enumerate network interfaces
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
          wifiIp = interfaces.first.addresses.first.address;
        } else {
          wifiIp = '127.0.0.1';
        }
      }

      _hostIp = wifiIp;

      // Bind server to all IPv4 interfaces
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _isRunning = true;

      _server!.listen(_handleRequest);
      return true;
    } catch (e) {
      _isRunning = false;
      return false;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');

    final reqPath = Uri.decodeComponent(request.uri.path);
    final targetPath = p.normalize(p.join(_rootPath, reqPath.startsWith('/') ? reqPath.substring(1) : reqPath));

    // Security check: ensure targetPath is within _rootPath
    if (!targetPath.startsWith(_rootPath)) {
      response.statusCode = HttpStatus.forbidden;
      response.write('Access Denied');
      await response.close();
      return;
    }

    final entityType = await FileSystemEntity.type(targetPath);

    if (entityType == FileSystemEntityType.directory) {
      // Serve directory listing HTML (Apple Dark Web UI for PC access!)
      final dir = Directory(targetPath);
      final items = await dir.list().toList();

      final buffer = StringBuffer();
      buffer.write('''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>AeroFiles - Wireless PC Access</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #000; color: #fff; margin: 0; padding: 24px; }
    h1 { color: #0A84FF; font-size: 24px; }
    .path { color: #8E8E93; margin-bottom: 20px; word-break: break-all; }
    table { width: 100%; border-collapse: collapse; background: #1C1C1E; border-radius: 12px; overflow: hidden; }
    th, td { text-align: left; padding: 12px 16px; border-bottom: 1px solid #2C2C2E; }
    th { background: #2C2C2E; color: #8E8E93; font-size: 13px; text-transform: uppercase; }
    a { color: #0A84FF; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .folder { font-weight: 600; color: #64D2FF; }
  </style>
</head>
<body>
  <h1>AeroFiles Web Access</h1>
  <div class="path">Location: $reqPath</div>
  <table>
    <tr><th>Name</th><th>Type</th><th>Actions</th></tr>
''');

      if (reqPath != '/' && reqPath.isNotEmpty) {
        final parent = p.dirname(reqPath);
        buffer.write('<tr><td><a href="$parent">📁 .. (Parent Directory)</a></td><td>Folder</td><td></td></tr>');
      }

      for (final item in items) {
        final name = p.basename(item.path);
        final isDir = item is Directory;
        final itemUrl = p.join(reqPath, name);
        buffer.write('''<tr>
          <td><a href="$itemUrl" class="${isDir ? 'folder' : ''}">${isDir ? '📁' : '📄'} $name</a></td>
          <td>${isDir ? 'Directory' : 'File'}</td>
          <td>${isDir ? '' : '<a href="$itemUrl" download>Download</a>'}</td>
        </tr>''');
      }

      buffer.write('''</table>
</body>
</html>''');

      response.headers.contentType = ContentType.html;
      response.write(buffer.toString());
      await response.close();
    } else if (entityType == FileSystemEntityType.file) {
      // Stream file with range support
      final file = File(targetPath);
      final length = await file.length();

      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.contentLength = length;

      final stream = file.openRead();
      await response.addStream(stream);
      await response.close();
    } else {
      response.statusCode = HttpStatus.notFound;
      response.write('Not Found');
      await response.close();
    }
  }

  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }
    _isRunning = false;
  }
}
