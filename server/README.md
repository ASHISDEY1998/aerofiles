# 🛸 AeroFiles Home Server

An Apple-styled (`#000000` OLED Black + `#0A84FF` System Blue), high-performance private home server web app and Docker service for **CasaOS**, **ZimaOS**, Unraid, TrueNAS, Raspberry Pi, and Linux NAS servers.

Pair this with your **Android AeroFiles app** or use it standalone on **iPhone, iPad, Mac, and Windows** with **zero subscription or developer fees**.

---

## ✨ Features

- **Apple OLED Dark UI**: Pure `#000000` background with SF Pro typography and responsive cards.
- **HTTP 206 Byte-Range Streaming**: Ultra-fast video and audio streaming with instant seeking on 4K/1080p MKV, MP4, and WebM files.
- **Apple tvOS Video Player**: Custom touch-friendly overlay with scrubber slider, ±10s jump, playback speed (0.75x–2.0x), Picture-in-Picture, and fullscreen.
- **Floating Audio Player**: Seamless background playback for FLAC, MP3, WAV, and AAC music libraries.
- **Drag & Drop Upload**: High-speed LAN multi-file upload from PC or iPhone photo library directly to your NAS hard drives.
- **Live Storage Gauge**: Real-time disk usage bar (Used / Free / Total capacity).
- **iOS Safari PWA**: Save to iPhone/iPad Home Screen for a native-feeling, fullscreen standalone app that never expires and costs \$0.

---

## 🚀 1-Click Quickstart (Docker Compose)

### 1. Run with Docker Compose
Clone the repository or copy the `server/` folder to your server:

```bash
git clone https://github.com/ASHISDEY1998/aerofiles.git
cd aerofiles/server
docker compose up -d
```

### 2. Configure Storage Paths
In `docker-compose.yml`, customize your storage volume mount to match your server drives:

```yaml
volumes:
  # Map CasaOS / ZimaOS root storage:
  - /DATA:/storage:rw
  # Or map additional external hard drives:
  # - /media:/storage/media:rw
```

Then visit:
```
http://<server-ip>:8888
```
*(e.g., `http://192.168.1.41:8888`)*

---

## 🏠 CasaOS / ZimaOS Installation Guide

1. Open your **CasaOS** or **ZimaOS** dashboard (e.g., `http://192.168.1.41`).
2. Click the **+** (Install a customized app) button at the top right of the App Store.
3. Fill in the following details:
   - **App Name**: `AeroFiles`
   - **Tagline**: `High-Performance File Manager & Media Streamer`
   - **Icon URL**: `https://raw.githubusercontent.com/ASHISDEY1998/aerofiles/main/playstore_assets/icon_512x512.png`
   - **Network**: `Bridge`
   - **Port**: Host `8888` -> Container `8888`
   - **Volumes**:
     - Host: `/DATA` -> Container: `/storage`
   - **Restart**: `Always`
4. Click **Submit**. AeroFiles will now appear on your CasaOS dashboard!

---

## 📱 How to Use on iPhone & iPad (Free iOS App)

No Apple Developer account (\$99/year) or 7-day sideloading required:

1. On your iPhone or iPad, open **Safari**.
2. Navigate to your server's address:
   ```
   http://192.168.1.41:8888
   ```
3. Tap the **Share** button (box with upward arrow) in Safari.
4. Scroll down and tap **"Add to Home Screen"**.
5. Tap **"Add"**.

🎉 **AeroFiles will appear right on your iOS Home Screen** with its icon. When tapped, it launches full-screen without any Safari browser bars, looking and feeling like a native iOS app!

---

## 🤖 Connecting the Android AeroFiles App

1. Install `AeroFiles.apk` on your Android phone from [GitHub Releases](https://github.com/ASHISDEY1998/aerofiles/releases/latest).
2. Open **AeroFiles** -> Tap **Network** -> **Add Storage**.
3. Choose **SMB / Windows Share** and enter your server IP (`192.168.1.41`) to stream directly with hardware-accelerated libmpv!

---

## 🛠 Local Development (Python)

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
STORAGE_ROOT=/path/to/my/files PORT=8888 python3 app.py
```
