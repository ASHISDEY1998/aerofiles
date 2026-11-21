# AeroFiles (Apple Black & Blue CX File Explorer Clone)

A high-performance file explorer and universal media player designed with Apple's dark aesthetic (`#000000` OLED Black + `#0A84FF` Apple System Blue) and complete 1:1 feature parity with [Cx File Explorer](https://cxfileexplorer.com/).

---

## Key Features

### 1. Universal Video & Audio Engine (`libmpv` / `media_kit`)
- **Containers:** MKV, MP4, AVI, MOV, FLV, WMV, WebM, TS, M2TS, VOB, OGV, 3GP, RMVB.
- **Codecs:** H.264, HEVC / H.265 (10-bit HDR), AV1, VP9, MPEG-2, DivX/XviD, ProRes.
- **Audio Tracks & Codecs:** AC-3 (Dolby Digital), E-AC-3, TrueHD, DTS, DTS-HD, AAC, MP3, FLAC, Opus, Vorbis.
- **Subtitles:** Embedded ASS/SSA styled subtitles, SRT, PGS, VobSub, WebVTT.
- **Network Streaming:** Direct byte-range seeking over HTTP/SMB/WebDAV/SFTP without downloading the full video.

### 2. CX File Explorer Core Parity
- **Local Tab:**
  - Visual donut storage meter (Used vs. Total GB).
  - Main Storage & SD card navigation.
  - Downloads folder quick link.
  - Recycle Bin with 1-tap restore & permanent purge.
  - Storage Analysis & Cleaner (Large files, duplicate file detector, cache cleaner).
- **Library Tab:**
  - Automated media aggregation: Videos, Images, Audio, Documents, and Recent Files.
- **Network Tab:**
  - **Access from PC:** Built-in wireless HTTP/FTP server with Apple Dark Web UI.
  - **LAN Auto-Scanner:** Subnet discovery for SMB / Windows shares & WebDAV home servers.
  - Remote Connections: SMB 2/3, WebDAV (Nextcloud/Synology), SFTP, and FTP.

---

## Getting Started

### 1. Set Active Workspace
Set your workspace to:
```
/Users/ashis/.gemini/antigravity/scratch/aerofiles
```

### 2. Run the App
To run on your connected computer (macOS desktop):
```bash
cd /Users/ashis/.gemini/antigravity/scratch/aerofiles
flutter run -d macos
```

To run on an Android phone or Android TV:
```bash
flutter run -d android
```
