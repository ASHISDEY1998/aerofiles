// AeroFiles Home - Client-Side App
(function() {
  let currentPath = '';
  let items = [];
  let viewMode = localStorage.getItem('aerofiles_view_mode') || 'grid';
  let activeContextItem = null;

  // DOM elements
  const fileGrid = document.getElementById('fileGrid');
  const fileList = document.getElementById('fileList');
  const breadcrumbNav = document.getElementById('breadcrumbNav');
  const itemsCount = document.getElementById('itemsCount');
  const searchInput = document.getElementById('searchInput');
  const storageName = document.getElementById('storageName');
  const storageSubtitle = document.getElementById('storageSubtitle');
  const storageBarFill = document.getElementById('storageBarFill');
  const storageUsedLabel = document.getElementById('storageUsedLabel');
  const storageFreeLabel = document.getElementById('storageFreeLabel');
  const toggleViewBtn = document.getElementById('toggleViewBtn');
  const viewIconGrid = document.getElementById('viewIconGrid');
  const viewIconList = document.getElementById('viewIconList');
  const newFolderBtn = document.getElementById('newFolderBtn');
  const uploadBtn = document.getElementById('uploadBtn');
  const fileUploadInput = document.getElementById('fileUploadInput');
  const brandBtn = document.getElementById('brandBtn');

  // Modals
  const newFolderModal = document.getElementById('newFolderModal');
  const newFolderNameInput = document.getElementById('newFolderNameInput');
  const confirmNewFolderBtn = document.getElementById('confirmNewFolderBtn');
  const cancelNewFolderBtn = document.getElementById('cancelNewFolderBtn');
  const closeNewFolderBtn = document.getElementById('closeNewFolderBtn');

  const renameModal = document.getElementById('renameModal');
  const renameInput = document.getElementById('renameInput');
  const confirmRenameBtn = document.getElementById('confirmRenameBtn');
  const cancelRenameBtn = document.getElementById('cancelRenameBtn');
  const closeRenameBtn = document.getElementById('closeRenameBtn');

  // Video Player
  const videoModal = document.getElementById('videoModal');
  const mainVideoPlayer = document.getElementById('mainVideoPlayer');
  const videoTitle = document.getElementById('videoTitle');
  const videoCurrentTime = document.getElementById('videoCurrentTime');
  const videoDuration = document.getElementById('videoDuration');
  const videoScrubber = document.getElementById('videoScrubber');
  const videoPlayPauseBtn = document.getElementById('videoPlayPauseBtn');
  const videoPlayIcon = document.getElementById('videoPlayIcon');
  const videoPauseIcon = document.getElementById('videoPauseIcon');
  const videoSkipBackBtn = document.getElementById('videoSkipBackBtn');
  const videoSkipForwardBtn = document.getElementById('videoSkipForwardBtn');
  const videoSpeedSelect = document.getElementById('videoSpeedSelect');
  const videoPipBtn = document.getElementById('videoPipBtn');
  const videoFullscreenBtn = document.getElementById('videoFullscreenBtn');
  const closeVideoBtn = document.getElementById('closeVideoBtn');

  // Audio Player
  const audioPlayerBar = document.getElementById('audioPlayerBar');
  const mainAudioPlayer = document.getElementById('mainAudioPlayer');
  const audioTrackTitle = document.getElementById('audioTrackTitle');
  const audioTrackTime = document.getElementById('audioTrackTime');
  const audioPlayPauseBtn = document.getElementById('audioPlayPauseBtn');
  const audioPlayIcon = document.getElementById('audioPlayIcon');
  const audioPauseIcon = document.getElementById('audioPauseIcon');
  const closeAudioBtn = document.getElementById('closeAudioBtn');

  // Lightbox
  const lightboxModal = document.getElementById('lightboxModal');
  const lightboxImg = document.getElementById('lightboxImg');
  const closeLightboxBtn = document.getElementById('closeLightboxBtn');

  // Dropzone & Progress
  const dropzoneOverlay = document.getElementById('dropzoneOverlay');
  const uploadProgressBox = document.getElementById('uploadProgressBox');
  const uploadProgressFill = document.getElementById('uploadProgressFill');
  const uploadPercentText = document.getElementById('uploadPercentText');
  const uploadStatusText = document.getElementById('uploadStatusText');

  // Context Menu
  const contextMenu = document.getElementById('contextMenu');
  const ctxDownload = document.getElementById('ctxDownload');
  const ctxRename = document.getElementById('ctxRename');
  const ctxDelete = document.getElementById('ctxDelete');

  // SVG Icons
  const categoryIcons = {
    folder: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path></svg>`,
    video: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="23 7 16 12 23 17 23 7"></polygon><rect x="1" y="5" width="15" height="14" rx="2" ry="2"></rect></svg>`,
    audio: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18V5l12-2v13"></path><circle cx="6" cy="18" r="3"></circle><circle cx="18" cy="16" r="3"></circle></svg>`,
    image: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><circle cx="8.5" cy="8.5" r="1.5"></circle><polyline points="21 15 16 10 5 21"></polyline></svg>`,
    document: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg>`,
    archive: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="21 8 21 21 3 21 3 8"></polyline><rect x="1" y="3" width="22" height="5"></rect><line x1="10" y1="12" x2="14" y2="12"></line></svg>`,
    android: `<svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor"><path d="M17.523 15.3414c-.5511 0-.9993-.4486-.9993-1.0007 0-.5512.4482-.9997.9993-.9997.5516 0 .9997.4485.9997.9997 0 .5521-.4481 1.0007-.9997 1.0007m-11.046 0c-.5511 0-.9993-.4486-.9993-1.0007 0-.5512.4482-.9997.9993-.9997.5516 0 .9997.4485.9997.9997 0 .5521-.4481 1.0007-.9997 1.0007m11.4045-6.02l1.996-3.457c.106-.183.044-.418-.139-.524-.183-.106-.418-.044-.524.139l-2.023 3.504c-1.57-.718-3.327-1.127-5.191-1.127-1.864 0-3.621.409-5.191 1.127L4.78 5.4794c-.106-.183-.341-.245-.524-.139-.183.106-.245.341-.139.524l1.996 3.457C2.688 11.0864 0 14.7304 0 19.0004h24c0-4.27-2.688-7.914-6.1185-9.679"/></svg>`,
    other: `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"></path><polyline points="13 2 13 9 20 9"></polyline></svg>`
  };

  function formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0) return '0:00';
    const s = Math.floor(seconds % 60);
    const m = Math.floor((seconds / 60) % 60);
    const h = Math.floor(seconds / 3600);
    const sPadded = s < 10 ? `0${s}` : `${s}`;
    if (h > 0) {
      const mPadded = m < 10 ? `0${m}` : `${m}`;
      return `${h}:${mPadded}:${sPadded}`;
    }
    return `${m}:${sPadded}`;
  }

  // Load storage usage
  async function loadStorageStats() {
    try {
      const res = await fetch('/api/storage');
      const data = await res.json();
      storageSubtitle.textContent = `${data.used_formatted} of ${data.total_formatted} used (${data.percent_used}%)`;
      storageUsedLabel.textContent = `Used: ${data.used_formatted}`;
      storageFreeLabel.textContent = `Free: ${data.free_formatted}`;
      storageBarFill.style.width = `${Math.min(data.percent_used, 100)}%`;
      if (data.percent_used > 90) {
        storageBarFill.style.background = 'linear-gradient(90deg, #ff9f0a, #ff453a)';
      } else {
        storageBarFill.style.background = 'linear-gradient(90deg, #0a84ff, #30d158)';
      }
    } catch (e) {
      console.error('Failed to load storage stats:', e);
    }
  }

  // Load directory contents
  async function loadDirectory(path = '') {
    currentPath = path;
    itemsCount.textContent = 'Scanning directory...';
    try {
      const res = await fetch(`/api/browse?path=${encodeURIComponent(path)}`);
      if (!res.ok) throw new Error('Directory fetch failed');
      const data = await res.json();
      items = data.items || [];
      renderBreadcrumbs(data.breadcrumbs || []);
      renderItems(items);
      loadStorageStats();
    } catch (e) {
      console.error('Browse error:', e);
      fileGrid.innerHTML = `<div style="grid-column: 1/-1; text-align: center; color: var(--accent-red); padding: 40px 0;">Error loading folder contents.</div>`;
      fileList.innerHTML = '';
      itemsCount.textContent = 'Error';
    }
  }

  function renderBreadcrumbs(crumbs) {
    breadcrumbNav.innerHTML = '';
    crumbs.forEach((crumb, idx) => {
      const isLast = idx === crumbs.length - 1;
      const chip = document.createElement('div');
      chip.className = `breadcrumb-item ${isLast ? 'active' : ''}`;
      chip.textContent = crumb.name;
      chip.addEventListener('click', () => {
        if (!isLast) loadDirectory(crumb.path);
      });
      breadcrumbNav.appendChild(chip);

      if (!isLast) {
        const sep = document.createElement('span');
        sep.className = 'breadcrumb-sep';
        sep.textContent = '›';
        breadcrumbNav.appendChild(sep);
      }
    });
  }

  function renderItems(list) {
    fileGrid.innerHTML = '';
    fileList.innerHTML = '';

    if (list.length === 0) {
      const emptyMsg = `<div style="grid-column: 1/-1; text-align: center; color: var(--text-secondary); padding: 60px 0;">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="margin-bottom: 12px; opacity: 0.5;">
          <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path>
        </svg>
        <p>This folder is empty</p>
      </div>`;
      fileGrid.innerHTML = emptyMsg;
      fileList.innerHTML = emptyMsg;
      itemsCount.textContent = '0 items';
      return;
    }

    const folderCount = list.filter(i => i.is_dir).length;
    const fileCount = list.length - folderCount;
    itemsCount.textContent = `${list.length} items (${folderCount} folders, ${fileCount} files)`;

    list.forEach(item => {
      // Grid Card
      const card = document.createElement('div');
      card.className = 'file-card';
      const iconHtml = categoryIcons[item.category] || categoryIcons.other;

      card.innerHTML = `
        <div class="file-card-icon ${item.category}">
          ${iconHtml}
        </div>
        <div class="file-card-info">
          <div class="file-name" title="${item.name}">${item.name}</div>
          <div class="file-details">${item.is_dir ? 'Folder' : item.size_formatted}</div>
        </div>
        <div class="file-actions-menu">
          <button class="action-dots-btn" title="Options">•••</button>
        </div>
      `;

      card.addEventListener('click', (e) => {
        if (e.target.closest('.action-dots-btn')) {
          e.stopPropagation();
          showContextMenu(e, item);
          return;
        }
        handleItemClick(item);
      });

      card.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        showContextMenu(e, item);
      });

      fileGrid.appendChild(card);

      // List Row
      const row = document.createElement('div');
      row.className = 'file-list-row';
      row.innerHTML = `
        <div class="file-list-icon file-card-icon ${item.category}">
          ${iconHtml}
        </div>
        <div class="file-list-name" title="${item.name}">${item.name}</div>
        <div class="file-list-meta">
          <span>${item.is_dir ? 'Folder' : item.size_formatted}</span>
          <button class="action-dots-btn" title="Options">•••</button>
        </div>
      `;

      row.addEventListener('click', (e) => {
        if (e.target.closest('.action-dots-btn')) {
          e.stopPropagation();
          showContextMenu(e, item);
          return;
        }
        handleItemClick(item);
      });

      row.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        showContextMenu(e, item);
      });

      fileList.appendChild(row);
    });

    applyViewMode();
  }

  function handleItemClick(item) {
    if (item.is_dir) {
      loadDirectory(item.path);
    } else if (item.category === 'video') {
      openVideoPlayer(item);
    } else if (item.category === 'audio') {
      openAudioPlayer(item);
    } else if (item.category === 'image') {
      openLightbox(item);
    } else {
      downloadItem(item);
    }
  }

  function showContextMenu(e, item) {
    activeContextItem = item;
    contextMenu.style.left = `${Math.min(e.clientX, window.innerWidth - 190)}px`;
    contextMenu.style.top = `${Math.min(e.clientY, window.innerHeight - 150)}px`;
    contextMenu.classList.add('active');
  }

  function hideContextMenu() {
    contextMenu.classList.remove('active');
  }

  window.addEventListener('click', () => hideContextMenu());

  // Video Player Logic
  function openVideoPlayer(item) {
    videoTitle.textContent = item.name;
    const streamUrl = `/api/stream?path=${encodeURIComponent(item.path)}`;
    mainVideoPlayer.src = streamUrl;
    videoModal.classList.add('active');
    mainVideoPlayer.play().catch(console.error);
    updatePlayPauseState(true);
  }

  function closeVideoPlayer() {
    mainVideoPlayer.pause();
    mainVideoPlayer.removeAttribute('src');
    mainVideoPlayer.load();
    videoModal.classList.remove('active');
  }

  function updatePlayPauseState(isPlaying) {
    if (isPlaying) {
      videoPlayIcon.style.display = 'none';
      videoPauseIcon.style.display = 'block';
    } else {
      videoPlayIcon.style.display = 'block';
      videoPauseIcon.style.display = 'none';
    }
  }

  videoPlayPauseBtn.addEventListener('click', () => {
    if (mainVideoPlayer.paused) {
      mainVideoPlayer.play();
      updatePlayPauseState(true);
    } else {
      mainVideoPlayer.pause();
      updatePlayPauseState(false);
    }
  });

  mainVideoPlayer.addEventListener('play', () => updatePlayPauseState(true));
  mainVideoPlayer.addEventListener('pause', () => updatePlayPauseState(false));

  videoSkipBackBtn.addEventListener('click', () => {
    mainVideoPlayer.currentTime = Math.max(0, mainVideoPlayer.currentTime - 10);
  });

  videoSkipForwardBtn.addEventListener('click', () => {
    mainVideoPlayer.currentTime = Math.min(mainVideoPlayer.duration, mainVideoPlayer.currentTime + 10);
  });

  videoSpeedSelect.addEventListener('change', (e) => {
    mainVideoPlayer.playbackRate = parseFloat(e.target.value);
  });

  mainVideoPlayer.addEventListener('timeupdate', () => {
    if (!mainVideoPlayer.duration) return;
    const current = mainVideoPlayer.currentTime;
    const duration = mainVideoPlayer.duration;
    videoCurrentTime.textContent = formatTime(current);
    videoDuration.textContent = formatTime(duration);
    videoScrubber.value = (current / duration) * 100;
  });

  videoScrubber.addEventListener('input', (e) => {
    if (!mainVideoPlayer.duration) return;
    const seekTo = (e.target.value / 100) * mainVideoPlayer.duration;
    mainVideoPlayer.currentTime = seekTo;
  });

  videoPipBtn.addEventListener('click', async () => {
    try {
      if (document.pictureInPictureElement) {
        await document.exitPictureInPicture();
      } else if (mainVideoPlayer.requestPictureInPicture) {
        await mainVideoPlayer.requestPictureInPicture();
      }
    } catch (e) {
      console.warn('PiP error:', e);
    }
  });

  videoFullscreenBtn.addEventListener('click', () => {
    if (document.fullscreenElement) {
      document.exitFullscreen();
    } else if (videoModal.requestFullscreen) {
      videoModal.requestFullscreen();
    } else if (mainVideoPlayer.webkitEnterFullscreen) {
      mainVideoPlayer.webkitEnterFullscreen(); // iOS Safari
    }
  });

  closeVideoBtn.addEventListener('click', closeVideoPlayer);

  // Audio Player Logic
  function openAudioPlayer(item) {
    audioTrackTitle.textContent = item.name;
    const streamUrl = `/api/stream?path=${encodeURIComponent(item.path)}`;
    mainAudioPlayer.src = streamUrl;
    audioPlayerBar.classList.add('active');
    mainAudioPlayer.play().catch(console.error);
    audioPlayIcon.style.display = 'none';
    audioPauseIcon.style.display = 'block';
  }

  audioPlayPauseBtn.addEventListener('click', () => {
    if (mainAudioPlayer.paused) {
      mainAudioPlayer.play();
      audioPlayIcon.style.display = 'none';
      audioPauseIcon.style.display = 'block';
    } else {
      mainAudioPlayer.pause();
      audioPlayIcon.style.display = 'block';
      audioPauseIcon.style.display = 'none';
    }
  });

  mainAudioPlayer.addEventListener('timeupdate', () => {
    const cur = formatTime(mainAudioPlayer.currentTime);
    const dur = formatTime(mainAudioPlayer.duration || 0);
    audioTrackTime.textContent = `${cur} / ${dur}`;
  });

  closeAudioBtn.addEventListener('click', () => {
    mainAudioPlayer.pause();
    mainAudioPlayer.src = '';
    audioPlayerBar.classList.remove('active');
  });

  // Lightbox
  function openLightbox(item) {
    lightboxImg.src = `/api/download?path=${encodeURIComponent(item.path)}`;
    lightboxModal.classList.add('active');
  }

  closeLightboxBtn.addEventListener('click', () => {
    lightboxModal.classList.remove('active');
    lightboxImg.src = '';
  });

  lightboxModal.addEventListener('click', (e) => {
    if (e.target === lightboxModal) {
      lightboxModal.classList.remove('active');
      lightboxImg.src = '';
    }
  });

  // Download
  function downloadItem(item) {
    const a = document.createElement('a');
    a.href = `/api/download?path=${encodeURIComponent(item.path)}`;
    a.download = item.name;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  }

  // Create Folder
  newFolderBtn.addEventListener('click', () => {
    newFolderNameInput.value = '';
    newFolderModal.classList.add('active');
    setTimeout(() => newFolderNameInput.focus(), 100);
  });

  function closeNewFolderModal() {
    newFolderModal.classList.remove('active');
  }

  closeNewFolderBtn.addEventListener('click', closeNewFolderModal);
  cancelNewFolderBtn.addEventListener('click', closeNewFolderModal);

  confirmNewFolderBtn.addEventListener('click', async () => {
    const name = newFolderNameInput.value.trim();
    if (!name) return;
    try {
      const formData = new FormData();
      formData.append('path', currentPath);
      formData.append('name', name);
      const res = await fetch('/api/mkdir', { method: 'POST', body: formData });
      if (!res.ok) throw new Error('Create folder failed');
      closeNewFolderModal();
      loadDirectory(currentPath);
    } catch (e) {
      alert('Failed to create folder');
    }
  });

  // Rename
  function openRenameModal(item) {
    renameInput.value = item.name;
    renameModal.classList.add('active');
    setTimeout(() => renameInput.focus(), 100);
  }

  function closeRenameModal() {
    renameModal.classList.remove('active');
  }

  closeRenameBtn.addEventListener('click', closeRenameModal);
  cancelRenameBtn.addEventListener('click', closeRenameModal);

  confirmRenameBtn.addEventListener('click', async () => {
    const newName = renameInput.value.trim();
    if (!newName || !activeContextItem) return;
    try {
      const formData = new FormData();
      formData.append('old_path', activeContextItem.path);
      formData.append('new_name', newName);
      const res = await fetch('/api/rename', { method: 'POST', body: formData });
      if (!res.ok) throw new Error('Rename failed');
      closeRenameModal();
      loadDirectory(currentPath);
    } catch (e) {
      alert('Failed to rename item');
    }
  });

  // Context Menu Actions
  ctxDownload.addEventListener('click', () => {
    if (activeContextItem) downloadItem(activeContextItem);
  });

  ctxRename.addEventListener('click', () => {
    if (activeContextItem) openRenameModal(activeContextItem);
  });

  ctxDelete.addEventListener('click', async () => {
    if (!activeContextItem) return;
    const ok = confirm(`Delete "${activeContextItem.name}" permanently?`);
    if (!ok) return;
    try {
      const res = await fetch(`/api/delete?path=${encodeURIComponent(activeContextItem.path)}`, { method: 'DELETE' });
      if (!res.ok) throw new Error('Delete failed');
      loadDirectory(currentPath);
    } catch (e) {
      alert('Failed to delete item');
    }
  });

  // Upload Logic
  uploadBtn.addEventListener('click', () => fileUploadInput.click());
  fileUploadInput.addEventListener('change', (e) => {
    if (e.target.files.length > 0) {
      uploadFiles(e.target.files);
    }
  });

  function uploadFiles(fileListToUpload) {
    const formData = new FormData();
    formData.append('target_path', currentPath);
    for (let i = 0; i < fileListToUpload.length; i++) {
      formData.append('files', fileListToUpload[i]);
    }

    uploadProgressBox.classList.add('active');
    uploadStatusText.textContent = `Uploading ${fileListToUpload.length} item(s)...`;
    uploadPercentText.textContent = '0%';
    uploadProgressFill.style.width = '0%';

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/upload', true);

    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) {
        const pct = Math.round((e.loaded / e.total) * 100);
        uploadProgressFill.style.width = `${pct}%`;
        uploadPercentText.textContent = `${pct}%`;
      }
    };

    xhr.onload = () => {
      if (xhr.status === 200) {
        uploadStatusText.textContent = 'Upload complete!';
        setTimeout(() => {
          uploadProgressBox.classList.remove('active');
          loadDirectory(currentPath);
        }, 1200);
      } else {
        uploadStatusText.textContent = 'Upload failed';
        setTimeout(() => uploadProgressBox.classList.remove('active'), 2000);
      }
    };

    xhr.onerror = () => {
      uploadStatusText.textContent = 'Network error during upload';
      setTimeout(() => uploadProgressBox.classList.remove('active'), 2000);
    };

    xhr.send(formData);
  }

  // Drag and drop
  window.addEventListener('dragover', (e) => {
    e.preventDefault();
    dropzoneOverlay.classList.add('active');
  });

  dropzoneOverlay.addEventListener('dragleave', (e) => {
    e.preventDefault();
    dropzoneOverlay.classList.remove('active');
  });

  window.addEventListener('drop', (e) => {
    e.preventDefault();
    dropzoneOverlay.classList.remove('active');
    if (e.dataTransfer && e.dataTransfer.files.length > 0) {
      uploadFiles(e.dataTransfer.files);
    }
  });

  // View Mode
  function applyViewMode() {
    if (viewMode === 'grid') {
      fileGrid.style.display = 'grid';
      fileList.style.display = 'none';
      viewIconGrid.style.display = 'block';
      viewIconList.style.display = 'none';
    } else {
      fileGrid.style.display = 'none';
      fileList.style.display = 'flex';
      viewIconGrid.style.display = 'none';
      viewIconList.style.display = 'block';
    }
  }

  toggleViewBtn.addEventListener('click', () => {
    viewMode = viewMode === 'grid' ? 'list' : 'grid';
    localStorage.setItem('aerofiles_view_mode', viewMode);
    applyViewMode();
  });

  // Search
  searchInput.addEventListener('input', (e) => {
    const q = e.target.value.toLowerCase().trim();
    if (!q) {
      renderItems(items);
      return;
    }
    const filtered = items.filter(item => item.name.toLowerCase().includes(q));
    renderItems(filtered);
  });

  brandBtn.addEventListener('click', () => loadDirectory(''));

  // Init
  loadDirectory('');
})();
