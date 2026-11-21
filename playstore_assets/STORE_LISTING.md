# Google Play Store Listing & Publishing Kit for AeroFiles

---

## 1. App Metadata (Main Store Listing)

* **App Name (Title - Max 30 chars):**  
  `AeroFiles: File Manager & NAS`

* **Short Description (Max 80 chars):**  
  `Fast file manager with SMB home server streaming, video player & recycle bin.`

* **Full Description (Max 4000 chars):**
```text
AeroFiles is a modern, high-performance file manager and universal media player designed with Apple's clean OLED aesthetic. Easily browse, manage, and transfer files across your internal storage and local network home servers.

KEY FEATURES:

1. UNIVERSAL MEDIA PLAYER (POWERED BY LIBMPV)
• Play virtually all video formats directly inside the app: MP4, MKV, AVI, MOV, FLV, WMV, WebM, TS, and more.
• Hardware-accelerated decoding supporting HEVC (H.265 10-bit HDR), AV1, VP9, and H.264.
• Embedded & external subtitle support (ASS, SSA, SRT, VTT).
• Direct byte-range seeking with zero local downloading over Wi-Fi.

2. HOME NAS & NETWORK STORAGE (SMB / WEBDAV / SFTP)
• Streamless connection to Windows Shares, Samba (SMB 2/3), CasaOS, ZimaOS, Synology, TrueNAS, and Nextcloud.
• Browse multi-terabyte network hard drives, copy, move, and organize files between your phone and your server.
• Automatic LAN Scanner to discover servers on your local network.
• "Access from PC" feature: Manage phone files wirelessly from any computer browser.

3. SMART LOCAL STORAGE & VISUAL ANALYZER
• Accurate storage gauge showing real-time disk usage and available capacity.
• Visual multi-color segregated donut chart breaking down Videos, Images, Audio, Documents, and Apps.
• Large file finder (> 25 MB) and temporary junk detection to free up device space.

4. RECYCLE BIN & DATA PROTECTION
• Safe deletion: Move items to the Recycle Bin with 1-tap instant restoration back to their original path.
• Configurable delete preferences: Choose between permanent deletion or moving to Recycle Bin.
• Full Android MediaStore synchronization.

5. APPLE-STYLED OLED DARK & LIGHT THEMES
• Ultra-fast Cupertino UI with pure #000000 OLED Dark Mode and crisp Light Mode.
• Batch multi-selection, file compression, sorting, and search across all directories.

AeroFiles respects your privacy: no tracking, no invasive ads, and no external cloud servers required. All network transfers happen strictly within your local network.
```

---

## 2. All Files Access (`MANAGE_EXTERNAL_STORAGE`) Declaration

Google Play requires a declaration for file manager apps that access external storage. Use these exact answers:

* **Core Purpose:** Select **File management**
* **Why does your app need the All Files Access permission?**
  > "AeroFiles is a core file management application that enables users to browse, organize, move, copy, search, and delete files across their entire device storage, SD cards, and local network servers (SMB/NAS). It includes a file Recycle Bin with restore capabilities, storage analysis for large files, and file transfer to home servers, requiring access to files outside of app-specific directories."

* **Video Link (if requested by Google):**
  A brief 30-60 second screen recording showing:
  1. Browsing internal storage.
  2. Deleting a file to Recycle Bin and restoring it.
  3. Transferring a file to an SMB network share.

---

## 3. Store Listing Graphic Assets

The required images have been prepared to Google Play specifications:

* **App Icon (512 x 512 px PNG, no alpha):**  
  `playstore_assets/icon_512x512.png`

* **Feature Graphic (1024 x 500 px PNG):**  
  `playstore_assets/feature_graphic_1024x500.png`

* **Phone Screenshots (1240 x 2772 px):**  
  1. `playstore_assets/screenshots/1_home_storage.png` (Home Storage Donut & Access)  
  2. `playstore_assets/screenshots/2_media_library.png` (Categorized Media Library)  
  3. `playstore_assets/screenshots/3_image_gallery.png` (High-Res Photo Gallery)  
  4. `playstore_assets/screenshots/4_storage_analyzer.png` (Storage Analyzer & Large Files)  
  5. `playstore_assets/screenshots/5_network_smb.png` (Home NAS SMB Drives & Folders)  
  6. `playstore_assets/screenshots/6_settings_theme.png` (Theme & Recycle Bin Preferences)

---

## 4. App Bundle for Upload

* **Signed Release App Bundle (.aab):**  
  `AeroFiles-release.aab` (or `build/app/outputs/bundle/release/app-release.aab`)  
  *Signed with your dedicated release keystore (`upload-keystore.jks`).*
