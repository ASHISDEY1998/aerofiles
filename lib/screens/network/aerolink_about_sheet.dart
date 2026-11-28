import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../theme/apple_theme.dart';

class AeroLinkAboutSheet extends StatelessWidget {
  const AeroLinkAboutSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showCupertinoModalPopup<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => const AeroLinkAboutSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final cardBg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final borderColor = isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA);

    return Material(
      color: Colors.transparent,
      child: DefaultTextStyle(
        style: TextStyle(
          decoration: TextDecoration.none,
          fontFamily: '.SF Pro Text',
          color: isDark ? Colors.white : AppleColors.textPrimaryLight,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
            maxWidth: 580,
          ),
          margin: EdgeInsets.only(
            left: MediaQuery.of(context).size.width > 600 ? (MediaQuery.of(context).size.width - 580) / 2 : 0,
            right: MediaQuery.of(context).size.width > 600 ? (MediaQuery.of(context).size.width - 580) / 2 : 0,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: borderColor, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
                blurRadius: 36,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // Grabber Pill
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF48484A) : const Color(0xFFD1D1D6),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),

                // Top Bar with Close
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 40),
                      Text(
                        'AeroLink Mesh',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.none,
                          color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(36, 36),
                        onPressed: () => Navigator.pop(context),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 14,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 0.5, color: Color(0xFF38383A)),

                // Scrollable Content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    children: [
                      // Hero Badge
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppleColors.systemBlue, AppleColors.systemIndigo],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppleColors.systemBlue.withValues(alpha: 0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            CupertinoIcons.folder_fill_badge_person_crop,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Center(
                        child: Text(
                          'Direct Local Mesh Network',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.4,
                            decoration: TextDecoration.none,
                            color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          'High-speed device-to-device sharing and streaming without internet or cloud servers.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            decoration: TextDecoration.none,
                            color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // What is it?
                      _buildSectionHeader('WHAT IS AEROLINK?', isDark),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: 0.5),
                        ),
                        child: Text(
                          'AeroLink Mesh creates a zero-configuration peer-to-peer network between your phones, tablets, and computers over local Wi-Fi. It streams and transfers files directly socket-to-socket at native hardware speed with no data caps and complete privacy.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            decoration: TextDecoration.none,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // When is it handy?
                      _buildSectionHeader('WHEN IS IT HANDY?', isDark),
                      _buildFeatureCard(
                        icon: CupertinoIcons.airplane,
                        iconColor: AppleColors.systemTeal,
                        title: 'Offline & Travel',
                        description: 'Share movies, photos, and files mid-flight, on camping trips, or on road trips with zero mobile data or internet access.',
                        isDark: isDark,
                        cardBg: cardBg,
                        borderColor: borderColor,
                      ),
                      const SizedBox(height: 10),
                      _buildFeatureCard(
                        icon: CupertinoIcons.bolt_fill,
                        iconColor: AppleColors.systemOrange,
                        title: 'Gigabit LAN Speed for 4K Videos',
                        description: 'Transfer 20GB+ 4K videos or raw camera libraries at full local Wi-Fi speeds (50–100+ MB/s) in seconds instead of hours of cloud uploading.',
                        isDark: isDark,
                        cardBg: cardBg,
                        borderColor: borderColor,
                      ),
                      const SizedBox(height: 10),
                      _buildFeatureCard(
                        icon: CupertinoIcons.play_circle_fill,
                        iconColor: AppleColors.systemBlue,
                        title: 'Instant Zero-Download Streaming',
                        description: 'Play movies and music stored on your tablet or PC directly on your phone without copying or downloading the file first.',
                        isDark: isDark,
                        cardBg: cardBg,
                        borderColor: borderColor,
                      ),
                      const SizedBox(height: 10),
                      _buildFeatureCard(
                        icon: CupertinoIcons.lock_shield_fill,
                        iconColor: AppleColors.systemGreen,
                        title: '100% Private & PIN-Protected',
                        description: 'Connections are protected by a 6-digit mutual pairing PIN. Files never touch third-party servers or external clouds.',
                        isDark: isDark,
                        cardBg: cardBg,
                        borderColor: borderColor,
                      ),
                      const SizedBox(height: 22),

                      // How to use
                      _buildSectionHeader('HOW IT WORKS', isDark),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: 0.5),
                        ),
                        child: Column(
                          children: [
                            _buildStepRow('1', 'Turn on AeroLink Mesh', 'Enable the toggle on both devices on the same Wi-Fi.', isDark),
                            const Divider(height: 20, thickness: 0.5, color: Color(0xFF38383A)),
                            _buildStepRow('2', 'Select Folders to Share', 'Tap "Shared Folders" to choose which folders are visible.', isDark),
                            const Divider(height: 20, thickness: 0.5, color: Color(0xFF38383A)),
                            _buildStepRow('3', 'Pair with 6-Digit PIN', 'Tap the nearby device and enter its on-screen PIN to connect.', isDark),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),

                      // Done Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          color: AppleColors.systemBlue,
                          borderRadius: BorderRadius.circular(14),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          decoration: TextDecoration.none,
          color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                    color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    decoration: TextDecoration.none,
                    color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(String number, String title, String subtitle, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppleColors.systemBlue.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
              color: AppleColors.systemBlue,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                  color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  decoration: TextDecoration.none,
                  color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
