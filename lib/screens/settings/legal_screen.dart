import 'package:flutter/material.dart';
import '../../theme/apple_theme.dart';

enum LegalDocType { eula, privacyPolicy }

class LegalScreen extends StatelessWidget {
  final LegalDocType type;

  const LegalScreen({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEula = type == LegalDocType.eula;

    final title = isEula ? 'License Agreement (EULA)' : 'Privacy Policy';
    final content = isEula ? _eulaText : _privacyPolicyText;

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      appBar: AppBar(
        title: Text(title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SelectableText(
          content,
          style: TextStyle(
            color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ),
    );
  }

  static const String _eulaText = '''
END USER LICENSE AGREEMENT (EULA)
Last Updated: November 2026

1. Grant of License
AeroFiles grants you a revocable, non-exclusive, non-transferable, limited license to download, install, and use the application strictly in accordance with the terms of this Agreement.

2. Restrictions
You agree not to, and you will not permit others to:
a) License, sell, rent, lease, assign, distribute, transmit, host, outsource, or disclose the application to any third party.
b) Modify, make derivative works of, disassemble, decrypt, reverse compile, or reverse engineer any part of the application, except as permitted by applicable law.

3. Media Playback & Local Network Sharing
AeroFiles provides built-in media playback tools (powered by libmpv) and local network sharing protocols (SMB, WebDAV, FTP, SFTP) to manage your personal files. You are solely responsible for ensuring you have the legal right to store, share, and play any content accessed through this software.

4. Disclaimer of Warranty
AeroFiles is provided on an "AS IS" and "AS AVAILABLE" basis with all faults and without warranty of any kind. To the maximum extent permitted under applicable law, the developers disclaim all warranties, whether express, implied, statutory, or otherwise.

5. Limitation of Liability
In no event shall the developers of AeroFiles be liable for any indirect, incidental, consequential, special, or exemplary damages arising out of or in connection with your access or use of or inability to access or use the application.
''';

  static const String _privacyPolicyText = '''
PRIVACY POLICY
Last Updated: November 2026

1. Overview
AeroFiles is designed with privacy at its core. We believe your files, documents, photos, and videos belong to you and only you. AeroFiles does not collect, track, monetize, or transmit your personal data or file contents to any external servers.

2. Permissions Required & How They Are Used:
• All Files Access (MANAGE_EXTERNAL_STORAGE):
  Required strictly to allow you to browse, organize, move, copy, rename, analyze, and manage your device storage and external SD cards.
• Local Network & Wi-Fi State (INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE):
  Required strictly for the "Access from PC" local server and connecting to your personal local area network (SMB, WebDAV, FTP, SFTP) home servers. No internet analytics or remote tracking is performed.
• Foreground Service & Wake Lock:
  Used to maintain continuous local file transfers and uninterrupted media streaming.

3. Network Storage & Credentials
Any network credentials (usernames, passwords, server IP addresses) you enter for SMB or WebDAV servers are stored strictly on your local device's private storage. They are never transmitted to any third-party analytics or external cloud service.

4. Third-Party Libraries
AeroFiles utilizes trusted open-source components including Flutter, libmpv (MediaKit), and dart_smb2. None of these components harvest or export your personal information.

5. Contact Us
For questions or feedback regarding this Privacy Policy, please contact the developer via the official application support channel.
''';
}
