# AeroFiles Versioning & Release Specification

> **Standard:** Semantic Versioning 2.0.0 (`SemVer`) combined with ISO-8601 UTC Release Timestamp Comparison and Monotonically Incrementing Android Build Codes (`versionCode`).

---

## 📌 1. Version Format Overview

Every AeroFiles release conforms to the market-standard scheme:

```text
MAJOR.MINOR.PATCH+BUILD
(e.g., 2.0.0+16)
```

| Component | Example | Incremented When | Description |
| :--- | :---: | :--- | :--- |
| **MAJOR** (`X.0.0`) | `2.0.0` | Architectural overhauls, major redesigns, breaking protocol/VFS changes | Signifies a landmark release with extensive capability expansion (e.g., v2.0.0 introducing Safe Vault AES-256, chunked network streaming, tablet landscape two-pane view, and media parent-folder categorization). |
| **MINOR** (`2.X.0`) | `2.1.0` | New user-facing features, new protocol support, UI view enhancements | Backwards-compatible additions such as new cloud storage connectors, additional media sorting modes, or enhanced subtitle engines. |
| **PATCH** (`2.0.X`) | `2.0.1` | Bug fixes, stability patches, visual corrections, memory tuning | Backwards-compatible fixes that resolve crashes, connection timeouts, or edge-case regressions. |
| **BUILD** (`+16`) | `+16` | **Every single compilation / release build** | Monotonically incrementing positive integer (`versionCode` in Android). Strictly enforced by Google Play Console and internal package managers. |

---

## ⏱️ 2. Release Time & Date Verification Principle

### Why Version String ID Comparison Alone Is Insufficient
In production environments and open-source GitHub distribution, comparing version tags solely by alphanumeric text strings or numeric version IDs presents notable risks:
1. **Irregular Tagging & Hotfixes:** Out-of-band releases or emergency hotfix builds (e.g., `v2.0.0-hotfix` or build rebuilds) can be misinterpreted or skipped by naive string splitters.
2. **Channel Parity:** When users install beta, preview, or nightly APKs, version ID matching may fail to detect an officially published stable release.
3. **Draft & Stale Tags:** GitHub release IDs do not correlate with chronological release times.

### The Market-Standard Hybrid Model
AeroFiles implements a **Dual-Verification Update Engine** in `AppUpdateService`:

$$\text{Update Available} \iff (\text{Remote SemVer} > \text{Local SemVer}) \lor (\text{Remote SemVer} = \text{Local SemVer} \land \text{Remote Published Timestamp} > \text{Local Build Timestamp})$$

1. **Semantic Version Precedence:**
   * If remote `tag_name` has a higher major, minor, or patch component than the currently running app, an update is triggered immediately.
2. **ISO-8601 UTC Release Timestamp Comparison:**
   * When remote SemVer matches local SemVer (e.g., both identify as `2.0.0`), the engine evaluates GitHub's official `published_at` timestamp against the app's compiled `localReleaseDate`.
   * If the remote release was published after the installed binary's compilation timestamp (with a 10-minute tolerance buffer), the update is recognized as a refreshed/hotfixed release and surfaced to the user.
   * This guarantees seamless Over-The-Air (OTA) update delivery even if tag strings have not incremented.

---

## 📱 3. Architecture-Targeted Asset Delivery (ABI Matrix)

To minimize user download bandwidth and eliminate unnecessary disk usage, AeroFiles distributes targeted APKs alongside universal binaries:

| Distribution Asset | ABI / Target | Typical Size | Recommended For |
| :--- | :--- | :---: | :--- |
| `AeroFiles-arm64-v8a.apk` | `arm64-v8a` (64-bit ARM) | **~34 MB** | **99% of modern Android phones and tablets** |
| `AeroFiles-armv7.apk` | `armeabi-v7a` (32-bit ARM) | **~32 MB** | Legacy Android hardware & entry-level devices |
| `AeroFiles-x86_64.apk` | `x86_64` (64-bit Intel/AMD) | **~39 MB** | Chromebooks, Android-x86, and PC Emulators |
| `AeroFiles.apk` | Universal Fat APK (All ABIs) | **~102 MB** | Universal standalone distribution |
| `AeroFiles.aab` | Android App Bundle | **~77 MB** | Google Play Console dynamic delivery |

### In-App Auto-Update Selection
The in-app updater detects the active device ABI at runtime via `Abi.current()`:
- `Abi.androidArm64` $\rightarrow$ automatically downloads `AeroFiles-arm64-v8a.apk`.
- `Abi.androidArm` $\rightarrow$ automatically downloads `AeroFiles-armv7.apk`.
- `Abi.androidX64` $\rightarrow$ automatically downloads `AeroFiles-x86_64.apk`.
- If a matching ABI asset is unavailable, it automatically falls back to `AeroFiles.apk` (universal fat APK).

---

## 🏷️ 4. Release Workflow & Git Tagging Protocol

When preparing a new release, execute the following steps in sequence:

1. **Update `pubspec.yaml`:**
   ```yaml
   version: X.Y.Z+BUILD
   ```
2. **Update Application Version Constants:**
   * `lib/screens/settings/settings_screen.dart` (`applicationVersion: 'X.Y.Z'`)
   * `lib/screens/home_shell.dart` (`'vX.Y.Z Pro'`)
   * `lib/services/app_update_service.dart` (`localReleaseDate = DateTime.utc(...)`)
3. **Execute Verification Suite:**
   ```bash
   flutter analyze --no-fatal-infos
   flutter test
   ```
4. **Compile Release Artifacts:**
   ```bash
   flutter build apk --split-per-abi
   cd android && ./gradlew :app:assembleRelease
   cd android && ./gradlew :app:bundleRelease
   ```
5. **Git Commit, Tag & Push:**
   ```bash
   git add -A
   git commit -m "chore: Release vX.Y.Z (Build BUILD)"
   git tag vX.Y.Z
   git push origin main --tags
   ```
6. **Publish GitHub Release:**
   ```bash
   gh release create vX.Y.Z \
     releases/vX.Y.Z/AeroFiles-arm64-v8a.apk \
     releases/vX.Y.Z/AeroFiles-armv7.apk \
     releases/vX.Y.Z/AeroFiles-x86_64.apk \
     releases/vX.Y.Z/AeroFiles.apk \
     releases/vX.Y.Z/AeroFiles.aab \
     --title "AeroFiles vX.Y.Z: <Release Title>" \
     --notes "<Release Notes>"
   ```

---

## 📅 5. Release Roadmap & Milestones

* **v1.0.x (Foundation Series):** Core file manager, SMB/SFTP network streaming, built-in libmpv video playback, Recycle Bin data protection.
* **v1.0.14 (Transfer Resilience):** Chunked streaming SMB/SFTP upload, safe move, unclipped progress bubble, network auto-reconnection watcher, and file conflict resolution.
* **v2.0.0 (Pro Milestone):**
  * Tablet landscape UX defaulting to Dashboard.
  * Media Library Grid View with borderless icons-only styling.
  * Market-standard release timestamp comparison & ABI auto-selection in `AppUpdateService`.
  * Comprehensive versioning guidelines (`VERSIONING.md`).
* **v2.1.0 (Upcoming Connectivity):** WebDAV chunked sync enhancements, FTP/FTPS support, and background multi-threaded hash calculations.
