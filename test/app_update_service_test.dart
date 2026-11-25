import 'package:aerofiles/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateService Version & Release Date Tests', () {
    test('compareVersions accurately compares SemVer strings', () {
      expect(AppUpdateService.compareVersions('2.0.0', '1.0.14'), greaterThan(0));
      expect(AppUpdateService.compareVersions('v2.1.0', '2.0.0'), greaterThan(0));
      expect(AppUpdateService.compareVersions('2.0.1', '2.0.0'), greaterThan(0));
      expect(AppUpdateService.compareVersions('2.0.0', '2.0.0'), equals(0));
      expect(AppUpdateService.compareVersions('1.0.14', '2.0.0'), lessThan(0));
      expect(AppUpdateService.compareVersions('v2.0.0+17', '2.0.0+16'), greaterThan(0));
    });

    test('isUpdateAvailable triggers update on higher SemVer', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.1.0',
        localVersion: '2.0.0',
        localBuildNumber: '16',
        remotePublishedAt: DateTime.utc(2026, 11, 24, 12, 0, 0),
        localBuildDate: DateTime.utc(2026, 11, 24, 11, 0, 0),
      );
      expect(hasUpdate, isTrue);
    });

    test('isUpdateAvailable returns false for older remote SemVer', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v1.0.14',
        localVersion: '2.0.0',
        localBuildNumber: '16',
        remotePublishedAt: DateTime.utc(2026, 11, 24, 10, 0, 0),
        localBuildDate: DateTime.utc(2026, 11, 24, 11, 0, 0),
      );
      expect(hasUpdate, isFalse);
    });

    test('isUpdateAvailable compares by release date when SemVer identical', () {
      final localDate = DateTime.utc(2026, 11, 24, 11, 0, 0);

      // Remote published 1 hour after local release -> hotfix rebuild!
      final newerRemoteDate = DateTime.utc(2026, 11, 24, 12, 0, 0);
      final hasNewerDateUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.0.0',
        localVersion: '2.0.0',
        localBuildNumber: '16',
        remotePublishedAt: newerRemoteDate,
        localBuildDate: localDate,
      );
      expect(hasNewerDateUpdate, isTrue);

      // Remote published before local release -> already up to date
      final olderRemoteDate = DateTime.utc(2026, 11, 24, 10, 0, 0);
      final hasOlderDateUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.0.0',
        localVersion: '2.0.0',
        localBuildNumber: '16',
        remotePublishedAt: olderRemoteDate,
        localBuildDate: localDate,
      );
      expect(hasOlderDateUpdate, isFalse);
    });

    test('isUpdateAvailable returns false when versions are identical on user device', () {
      final hasUpdate = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.1',
        localVersion: '2.2.1',
        localBuildNumber: '25',
        remotePublishedAt: DateTime.utc(2026, 11, 25, 13, 0, 0),
      );
      expect(hasUpdate, isFalse);
    });

    test('isUpdateAvailable detects higher build number when SemVer is identical', () {
      final hasHigherBuild = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.1',
        localVersion: '2.2.1',
        localBuildNumber: '25',
        releaseTitle: 'AeroFiles v2.2.1 (Build 26)',
        remotePublishedAt: DateTime.utc(2026, 11, 25, 14, 0, 0),
      );
      expect(hasHigherBuild, isTrue);

      final hasSameBuild = AppUpdateService.isUpdateAvailable(
        remoteTag: 'v2.2.1',
        localVersion: '2.2.1',
        localBuildNumber: '25',
        releaseTitle: 'AeroFiles v2.2.1 (Build 25)',
        remotePublishedAt: DateTime.utc(2026, 11, 25, 14, 0, 0),
      );
      expect(hasSameBuild, isFalse);
    });
  });
}
