package com.aerofiles.app.aerofiles

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.media.ThumbnailUtils
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.util.Size
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.aerofiles.app/storage"
    private val thumbnailExecutor = Executors.newFixedThreadPool(4)
    private var notificationManager: NotificationManager? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val TRANSFER_CHANNEL_ID = "aerofiles_transfers"
    private val TRANSFER_NOTIFICATION_ID = 2001

    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var focusChangeListener: AudioManager.OnAudioFocusChangeListener? = null
    private var becomingNoisyReceiver: BroadcastReceiver? = null
    private var methodChannel: MethodChannel? = null
    private var videoMethodChannel: MethodChannel? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var mediaSession: MediaSession? = null
    private var videoEditorHelper: VideoEditorHelper? = null

    private fun setupMediaSession() {
        if (mediaSession == null) {
            mediaSession = MediaSession(this, "AeroFilesMediaSession").apply {
                setCallback(object : MediaSession.Callback() {
                    override fun onPlay() {
                        runOnUiThread {
                            methodChannel?.invokeMethod("onMediaPlay", null)
                        }
                    }

                    override fun onPause() {
                        runOnUiThread {
                            methodChannel?.invokeMethod("onMediaPause", null)
                        }
                    }

                    override fun onSkipToNext() {
                        runOnUiThread {
                            methodChannel?.invokeMethod("onMediaNext", null)
                        }
                    }

                    override fun onSkipToPrevious() {
                        runOnUiThread {
                            methodChannel?.invokeMethod("onMediaPrevious", null)
                        }
                    }

                    override fun onFastForward() {
                        runOnUiThread {
                            methodChannel?.invokeMethod("onMediaNext", null)
                        }
                    }

                    override fun onRewind() {
                        runOnUiThread {
                            methodChannel?.invokeMethod("onMediaPrevious", null)
                        }
                    }

                    override fun onStop() {
                        runOnUiThread {
                            methodChannel?.invokeMethod("onMediaPause", null)
                        }
                    }

                    override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                        val event = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
                        }
                        if (event != null && event.action == android.view.KeyEvent.ACTION_DOWN) {
                            when (event.keyCode) {
                                android.view.KeyEvent.KEYCODE_HEADSETHOOK,
                                android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                                    runOnUiThread {
                                        methodChannel?.invokeMethod("onMediaPlayPause", null)
                                    }
                                    return true
                                }
                                android.view.KeyEvent.KEYCODE_MEDIA_PLAY -> {
                                    runOnUiThread {
                                        methodChannel?.invokeMethod("onMediaPlay", null)
                                    }
                                    return true
                                }
                                android.view.KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                                    runOnUiThread {
                                        methodChannel?.invokeMethod("onMediaPause", null)
                                    }
                                    return true
                                }
                                android.view.KeyEvent.KEYCODE_MEDIA_NEXT,
                                android.view.KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
                                android.view.KeyEvent.KEYCODE_MEDIA_STEP_FORWARD -> {
                                    runOnUiThread {
                                        methodChannel?.invokeMethod("onMediaNext", null)
                                    }
                                    return true
                                }
                                android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS,
                                android.view.KeyEvent.KEYCODE_MEDIA_REWIND,
                                android.view.KeyEvent.KEYCODE_MEDIA_STEP_BACKWARD -> {
                                    runOnUiThread {
                                        methodChannel?.invokeMethod("onMediaPrevious", null)
                                    }
                                    return true
                                }
                            }
                        }
                        return super.onMediaButtonEvent(mediaButtonIntent)
                    }
                })
                setFlags(
                    MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
                )
            }
        }
    }

    private fun updateMediaSessionPlaybackState(isPlaying: Boolean) {
        try {
            setupMediaSession()
            val actions = PlaybackState.ACTION_PLAY or
                    PlaybackState.ACTION_PAUSE or
                    PlaybackState.ACTION_PLAY_PAUSE or
                    PlaybackState.ACTION_SKIP_TO_NEXT or
                    PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackState.ACTION_FAST_FORWARD or
                    PlaybackState.ACTION_REWIND or
                    PlaybackState.ACTION_STOP

            val state = if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
            val playbackState = PlaybackState.Builder()
                .setActions(actions)
                .setState(state, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1.0f)
                .build()

            mediaSession?.setPlaybackState(playbackState)
            mediaSession?.isActive = true
        } catch (_: Throwable) {}
    }

    private fun releaseMediaSession() {
        try {
            mediaSession?.isActive = false
            mediaSession?.release()
            mediaSession = null
        } catch (_: Throwable) {}
    }

    private fun acquireMulticastLock() {
        try {
            if (multicastLock == null) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                multicastLock = wifiManager?.createMulticastLock("AeroFiles::AeroLinkMulticastLock")?.apply {
                    setReferenceCounted(true)
                }
            }
            if (multicastLock?.isHeld != true) {
                multicastLock?.acquire()
            }
        } catch (_: Throwable) {}
    }

    private fun releaseMulticastLock() {
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        } catch (_: Throwable) {}
    }

    private fun setupAudioFocus() {
        setupMediaSession()
        updateMediaSessionPlaybackState(true)

        if (audioManager == null) {
            audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        }

        if (focusChangeListener == null) {
            focusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
                when (focusChange) {
                    AudioManager.AUDIOFOCUS_LOSS,
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                        runOnUiThread {
                            methodChannel?.invokeMethod("onAudioFocusLost", null)
                        }
                    }
                    AudioManager.AUDIOFOCUS_GAIN -> {
                        runOnUiThread {
                            methodChannel?.invokeMethod("onAudioFocusGained", null)
                        }
                    }
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val playbackAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build()

            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(playbackAttributes)
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener(focusChangeListener!!)
                .build()

            audioManager?.requestAudioFocus(audioFocusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager?.requestAudioFocus(
                focusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            )
        }

        registerBecomingNoisyReceiver()
    }

    private fun abandonAudioFocus() {
        updateMediaSessionPlaybackState(false)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
                audioManager?.abandonAudioFocusRequest(audioFocusRequest!!)
                audioFocusRequest = null
            } else if (focusChangeListener != null) {
                @Suppress("DEPRECATION")
                audioManager?.abandonAudioFocus(focusChangeListener)
            }
        } catch (_: Throwable) {}

        unregisterBecomingNoisyReceiver()
    }

    private fun registerBecomingNoisyReceiver() {
        if (becomingNoisyReceiver == null) {
            becomingNoisyReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    val action = intent?.action
                    if (action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                        runOnUiThread {
                            methodChannel?.invokeMethod("onAudioBecomingNoisy", null)
                        }
                    } else if (action == BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED ||
                               action == BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED) {
                        val state = intent.getIntExtra(BluetoothProfile.EXTRA_STATE, BluetoothProfile.STATE_CONNECTED)
                        if (state == BluetoothProfile.STATE_DISCONNECTED || state == BluetoothProfile.STATE_DISCONNECTING) {
                            runOnUiThread {
                                methodChannel?.invokeMethod("onAudioBecomingNoisy", null)
                            }
                        }
                    }
                }
            }

            val filter = IntentFilter().apply {
                addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
                addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
                addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(becomingNoisyReceiver, filter, Context.RECEIVER_EXPORTED)
                } else {
                    registerReceiver(becomingNoisyReceiver, filter)
                }
            } catch (_: Throwable) {}
        }
    }

    private fun unregisterBecomingNoisyReceiver() {
        if (becomingNoisyReceiver != null) {
            try {
                unregisterReceiver(becomingNoisyReceiver)
            } catch (_: Throwable) {}
            becomingNoisyReceiver = null
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                TRANSFER_CHANNEL_ID,
                "File Transfers",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Progress notifications for background file copying, moving, and downloads"
                setShowBadge(false)
            }
            notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager?.createNotificationChannel(channel)
        } else {
            notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        }
    }

    private fun updateTransferNotification(title: String, content: String, progress: Int, max: Int) {
        if (notificationManager == null) createNotificationChannel()

        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AeroFiles::TransferWakeLock")
            wakeLock?.acquire(20 * 60 * 1000L)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(applicationContext, TRANSFER_CHANNEL_ID)
        } else {
            Notification.Builder(applicationContext)
        }

        builder.setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)

        if (max > 0) {
            builder.setProgress(max, progress, false)
        } else {
            builder.setProgress(0, 0, true)
        }

        notificationManager?.notify(TRANSFER_NOTIFICATION_ID, builder.build())
    }

    private fun stopTransferNotification() {
        notificationManager?.cancel(TRANSFER_NOTIFICATION_ID)
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Throwable) {}
        wakeLock = null
    }

    private fun isMpegTs(file: File): Boolean {
        try {
            if (!file.exists() || file.length() < 377) return false
            java.io.FileInputStream(file).use { fis ->
                val buf = ByteArray(1024)
                val read = fis.read(buf)
                if (read >= 377) {
                    for (i in 0..(read - 377)) {
                        if (buf[i] == 0x47.toByte() &&
                            buf[i + 188] == 0x47.toByte() &&
                            buf[i + 376] == 0x47.toByte()) {
                            return true
                        }
                    }
                }
            }
        } catch (_: Throwable) {}
        return false
    }

    private fun md5(input: String): String {
        return try {
            val md = java.security.MessageDigest.getInstance("MD5")
            val digest = md.digest(input.toByteArray(Charsets.UTF_8))
            digest.joinToString("") { "%02x".format(it) }
        } catch (_: Throwable) {
            input.hashCode().toString()
        }
    }

    private fun trimThumbnailDiskCache(thumbDir: File) {
        try {
            val files = thumbDir.listFiles() ?: return
            val maxFiles = 1500
            val maxBytes = 60L * 1024 * 1024 // 60 MB

            var totalBytes = 0L
            for (f in files) {
                totalBytes += f.length()
            }

            if (files.size > maxFiles || totalBytes > maxBytes) {
                val sorted = files.sortedBy { it.lastModified() }
                var currentBytes = totalBytes
                var currentCount = files.size
                for (f in sorted) {
                    if (currentCount <= maxFiles * 0.8 && currentBytes <= maxBytes * 0.8) break
                    val len = f.length()
                    if (f.delete()) {
                        currentBytes -= len
                        currentCount--
                    }
                }
            }
        } catch (_: Throwable) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestAudioFocus" -> {
                    setupAudioFocus()
                    result.success(true)
                }
                "abandonAudioFocus" -> {
                    abandonAudioFocus()
                    result.success(true)
                }
                "updatePlaybackState" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    updateMediaSessionPlaybackState(isPlaying)
                    result.success(true)
                }
                "acquireMulticastLock" -> {
                    acquireMulticastLock()
                    result.success(true)
                }
                "releaseMulticastLock" -> {
                    releaseMulticastLock()
                    result.success(true)
                }
                "getStorageStats" -> {
                    try {
                        val path = call.argument<String>("path") ?: Environment.getExternalStorageDirectory().path
                        val stat = StatFs(path)
                        val blockSize = stat.blockSizeLong
                        val totalBlocks = stat.blockCountLong
                        val availableBlocks = stat.availableBlocksLong

                        val totalBytes = totalBlocks * blockSize
                        val freeBytes = availableBlocks * blockSize
                        val usedBytes = totalBytes - freeBytes

                        val map = mapOf(
                            "totalBytes" to totalBytes,
                            "usedBytes" to usedBytes,
                            "freeBytes" to freeBytes
                        )
                        result.success(map)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message ?: "Failed to get storage stats", null)
                    }
                }
                "scanFile" -> {
                    try {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null, null)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message ?: "Failed to scan file", null)
                    }
                }
                "openWith" -> {
                    val path = call.argument<String>("path")
                    var mimeType = call.argument<String>("mimeType")
                    if (path.isNullOrEmpty()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("NOT_FOUND", "File does not exist: $path", null)
                            return@setMethodCallHandler
                        }
                        if (mimeType.isNullOrEmpty() || mimeType == "application/octet-stream") {
                            val ext = file.extension.lowercase()
                            mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
                        }
                        val uri = FileProvider.getUriForFile(
                            applicationContext,
                            "${applicationContext.packageName}.fileProvider.com.crazecoder.openfile",
                            file
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        val chooser = Intent.createChooser(intent, "Open with").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message ?: "Failed to open chooser", null)
                    }
                }
                "enterPipMode" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val params = android.app.PictureInPictureParams.Builder()
                                .setAspectRatio(android.util.Rational(16, 9))
                                .build()
                            val entered = enterPictureInPictureMode(params)
                            result.success(entered)
                        } catch (e: Exception) {
                            result.error("PIP_ERROR", e.message ?: "Failed to enter PiP mode", null)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "updateTransferNotification" -> {
                    val title = call.argument<String>("title") ?: "Transferring Files"
                    val content = call.argument<String>("content") ?: "In progress..."
                    val progress = call.argument<Int>("progress") ?: 0
                    val max = call.argument<Int>("max") ?: 100
                    updateTransferNotification(title, content, progress, max)
                    result.success(true)
                }
                "stopTransferNotification" -> {
                    stopTransferNotification()
                    result.success(true)
                }
                "trimVideo" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    val startMs = (call.argument<Number>("startMs"))?.toLong() ?: 0L
                    val endMs = (call.argument<Number>("endMs"))?.toLong() ?: 0L

                    if (inputPath.isNullOrEmpty() || outputPath.isNullOrEmpty() || endMs <= startMs) {
                        result.error("INVALID_ARGS", "Invalid trim arguments", null)
                        return@setMethodCallHandler
                    }

                    if (videoEditorHelper == null) {
                        videoEditorHelper = VideoEditorHelper(applicationContext)
                    }

                    val isReplied = java.util.concurrent.atomic.AtomicBoolean(false)
                    fun safeSuccess(data: Any?) {
                        if (isReplied.compareAndSet(false, true)) {
                            runOnUiThread {
                                stopTransferNotification()
                                result.success(data)
                            }
                        }
                    }
                    fun safeError(code: String, message: String?) {
                        if (isReplied.compareAndSet(false, true)) {
                            runOnUiThread {
                                stopTransferNotification()
                                result.error(code, message, null)
                            }
                        }
                    }

                    var lastNotifiedP = -1
                    updateTransferNotification("Trimming Video", "Rendering trimmed clip...", 0, 100)

                    videoEditorHelper?.trimVideo(
                        inputPath,
                        outputPath,
                        startMs,
                        endMs,
                        onProgress = { progress ->
                            runOnUiThread {
                                methodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to progress
                                ))
                                videoMethodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to progress
                                ))
                                if (progress != lastNotifiedP) {
                                    lastNotifiedP = progress
                                    updateTransferNotification("Trimming Video", "Rendering: $progress%", progress, 100)
                                }
                            }
                        },
                        onComplete = { outPath ->
                            runOnUiThread {
                                methodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to 100
                                ))
                                videoMethodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to 100
                                ))
                                safeSuccess(outPath)
                            }
                        },
                        onError = { error ->
                            safeError("TRIM_ERROR", error)
                        }
                    )
                }
                "mergeVideos" -> {
                    val inputPaths = call.argument<List<String>>("inputPaths")
                    val outputPath = call.argument<String>("outputPath")

                    if (inputPaths.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                        result.error("INVALID_ARGS", "Invalid merge arguments", null)
                        return@setMethodCallHandler
                    }

                    if (videoEditorHelper == null) {
                        videoEditorHelper = VideoEditorHelper(applicationContext)
                    }

                    val isReplied = java.util.concurrent.atomic.AtomicBoolean(false)
                    fun safeSuccess(data: Any?) {
                        if (isReplied.compareAndSet(false, true)) {
                            runOnUiThread {
                                stopTransferNotification()
                                result.success(data)
                            }
                        }
                    }
                    fun safeError(code: String, message: String?) {
                        if (isReplied.compareAndSet(false, true)) {
                            runOnUiThread {
                                stopTransferNotification()
                                result.error(code, message, null)
                            }
                        }
                    }

                    var lastNotifiedP = -1
                    updateTransferNotification("Merging Videos", "Combining ${inputPaths.size} clips...", 0, 100)

                    videoEditorHelper?.mergeVideos(
                        inputPaths,
                        outputPath,
                        onProgress = { progress ->
                            runOnUiThread {
                                methodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to progress
                                ))
                                videoMethodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to progress
                                ))
                                if (progress != lastNotifiedP) {
                                    lastNotifiedP = progress
                                    updateTransferNotification("Merging Videos", "Rendering: $progress%", progress, 100)
                                }
                            }
                        },
                        onComplete = { outPath ->
                            runOnUiThread {
                                methodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to 100
                                ))
                                videoMethodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to 100
                                ))
                                safeSuccess(outPath)
                            }
                        },
                        onError = { error ->
                            safeError("MERGE_ERROR", error)
                        }
                    )
                }
                "cancelVideoProcess" -> {
                    videoEditorHelper?.cancel()
                    stopTransferNotification()
                    result.success(true)
                }
                "getVideoMetadata" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                        return@setMethodCallHandler
                    }
                    if (videoEditorHelper == null) {
                        videoEditorHelper = VideoEditorHelper(applicationContext)
                    }
                    val meta = videoEditorHelper?.getVideoMetadata(path) ?: emptyMap<String, Any>()
                    result.success(meta)
                }
                "getVideoThumbnail" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    val file = File(path)
                    if (!file.exists() || !file.canRead()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    thumbnailExecutor.execute {
                        val thumbDir = File(applicationContext.cacheDir, "thumbnails").apply {
                            if (!exists()) mkdirs()
                        }
                        val lastModified = file.lastModified()
                        val cacheKey = "${md5(file.absolutePath)}_${lastModified}.jpg"
                        val cacheFile = File(thumbDir, cacheKey)

                        // ⚡ Instant Disk-Cache Hit: return cached thumbnail immediately without decoding
                        if (cacheFile.exists() && cacheFile.length() > 0) {
                            try {
                                val cachedBytes = cacheFile.readBytes()
                                cacheFile.setLastModified(System.currentTimeMillis())
                                runOnUiThread { result.success(cachedBytes) }
                                return@execute
                            } catch (_: Throwable) {}
                        }

                        var bitmap: Bitmap? = null
                        var retriever: MediaMetadataRetriever? = null
                        var fis: java.io.FileInputStream? = null
                        var tempLink: File? = null
                        try {
                            val isTransportStream = isMpegTs(file) ||
                                file.name.contains(".digital", ignoreCase = true) ||
                                file.name.contains(".mms", ignoreCase = true) ||
                                file.extension.equals("ts", ignoreCase = true)

                            // For transport streams (even if disguised as .mp4 by downloaders),
                            // create a zero-copy .ts symlink so Android demuxes it as MPEG-TS:
                            if (isTransportStream) {
                                try {
                                    val linkFile = File(applicationContext.cacheDir, "th_${System.nanoTime()}_${Thread.currentThread().id}.ts")
                                    android.system.Os.symlink(file.absolutePath, linkFile.absolutePath)
                                    tempLink = linkFile

                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                        try {
                                            bitmap = ThumbnailUtils.createVideoThumbnail(linkFile, Size(320, 320), null)
                                        } catch (_: Throwable) {}
                                    }

                                    if (bitmap == null) {
                                        retriever = MediaMetadataRetriever()
                                        retriever.setDataSource(linkFile.absolutePath)
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                            try {
                                                bitmap = retriever.getFrameAtIndex(0)
                                            } catch (_: Throwable) {}
                                        }
                                        if (bitmap == null) {
                                            bitmap = retriever.frameAtTime
                                                ?: retriever.getFrameAtTime(-1)
                                                ?: retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST)
                                                ?: retriever.getFrameAtTime(1000000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                        }
                                    }
                                } catch (_: Throwable) {}
                            }

                            // Standard container processing
                            if (bitmap == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                try {
                                    bitmap = ThumbnailUtils.createVideoThumbnail(file, Size(320, 320), null)
                                } catch (_: Throwable) {}
                            }

                            if (bitmap == null) {
                                try {
                                    retriever?.release()
                                    retriever = MediaMetadataRetriever()
                                    retriever.setDataSource(file.absolutePath)
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                        try {
                                            bitmap = retriever.getFrameAtIndex(0)
                                        } catch (_: Throwable) {}
                                    }
                                    if (bitmap == null) {
                                        bitmap = retriever.frameAtTime
                                            ?: retriever.getFrameAtTime(-1)
                                            ?: retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST)
                                            ?: retriever.getFrameAtTime(1000000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                    }
                                } catch (_: Throwable) {}
                            }

                            if (bitmap == null) {
                                try {
                                    fis = java.io.FileInputStream(file)
                                    retriever?.release()
                                    retriever = MediaMetadataRetriever()
                                    retriever.setDataSource(fis.fd)
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                        try {
                                            bitmap = retriever.getFrameAtIndex(0)
                                        } catch (_: Throwable) {}
                                    }
                                    if (bitmap == null) {
                                        bitmap = retriever.frameAtTime
                                            ?: retriever.getFrameAtTime(-1)
                                            ?: retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST)
                                            ?: retriever.getFrameAtTime(1000000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                    }
                                } catch (_: Throwable) {
                                    try {
                                        retriever?.release()
                                        retriever = MediaMetadataRetriever()
                                        retriever.setDataSource(path)
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                            try {
                                                bitmap = retriever.getFrameAtIndex(0)
                                            } catch (_: Throwable) {}
                                        }
                                        if (bitmap == null) {
                                            bitmap = retriever.frameAtTime
                                                ?: retriever.getFrameAtTime(-1)
                                                ?: retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST)
                                        }
                                    } catch (_: Throwable) {}
                                }
                            }

                            if (bitmap != null) {
                                val maxDim = 320
                                val width = bitmap.width
                                val height = bitmap.height
                                val scale = if (width > height) maxDim.toFloat() / width else maxDim.toFloat() / height
                                val scaledBitmap = if (scale < 1.0f) {
                                    Bitmap.createScaledBitmap(
                                        bitmap,
                                        (width * scale).toInt().coerceAtLeast(1),
                                        (height * scale).toInt().coerceAtLeast(1),
                                        true
                                    )
                                } else {
                                    bitmap
                                }

                                val stream = ByteArrayOutputStream()
                                scaledBitmap.compress(Bitmap.CompressFormat.JPEG, 75, stream)
                                val bytes = stream.toByteArray()
                                if (scaledBitmap != bitmap) {
                                    scaledBitmap.recycle()
                                }
                                bitmap.recycle()

                                // Save to persistent disk cache
                                try {
                                    cacheFile.writeBytes(bytes)
                                    trimThumbnailDiskCache(thumbDir)
                                } catch (_: Throwable) {}

                                runOnUiThread { result.success(bytes) }
                            } else {
                                runOnUiThread { result.success(null) }
                            }
                        } catch (_: Throwable) {
                            runOnUiThread { result.success(null) }
                        } finally {
                            try {
                                retriever?.release()
                            } catch (_: Throwable) {}
                            try {
                                fis?.close()
                            } catch (_: Throwable) {}
                            try {
                                tempLink?.delete()
                            } catch (_: Throwable) {}
                        }
                    }
                }
                "clearThumbnailCache" -> {
                    thumbnailExecutor.execute {
                        try {
                            val thumbDir = File(applicationContext.cacheDir, "thumbnails")
                            if (thumbDir.exists()) {
                                thumbDir.deleteRecursively()
                                thumbDir.mkdirs()
                            }
                        } catch (_: Throwable) {}
                        runOnUiThread { result.success(true) }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        videoMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.aerofiles.app/video_editor")
        videoMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "trimVideo" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    val startMs = (call.argument<Number>("startMs"))?.toLong() ?: 0L
                    val endMs = (call.argument<Number>("endMs"))?.toLong() ?: 0L

                    if (inputPath.isNullOrEmpty() || outputPath.isNullOrEmpty() || endMs <= startMs) {
                        result.error("INVALID_ARGS", "Invalid trim arguments", null)
                        return@setMethodCallHandler
                    }

                    if (videoEditorHelper == null) {
                        videoEditorHelper = VideoEditorHelper(applicationContext)
                    }

                    val isReplied = java.util.concurrent.atomic.AtomicBoolean(false)
                    fun safeSuccess(data: Any?) {
                        if (isReplied.compareAndSet(false, true)) {
                            runOnUiThread {
                                stopTransferNotification()
                                result.success(data)
                            }
                        }
                    }
                    fun safeError(code: String, message: String?) {
                        if (isReplied.compareAndSet(false, true)) {
                            runOnUiThread {
                                stopTransferNotification()
                                result.error(code, message, null)
                            }
                        }
                    }

                    var lastNotifiedP = -1
                    updateTransferNotification("Trimming Video", "Rendering trimmed clip...", 0, 100)

                    videoEditorHelper?.trimVideo(
                        inputPath,
                        outputPath,
                        startMs,
                        endMs,
                        onProgress = { progress ->
                            runOnUiThread {
                                videoMethodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to progress
                                ))
                                methodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to progress
                                ))
                                if (progress != lastNotifiedP) {
                                    lastNotifiedP = progress
                                    updateTransferNotification("Trimming Video", "Rendering: $progress%", progress, 100)
                                }
                            }
                        },
                        onComplete = { outPath ->
                            runOnUiThread {
                                videoMethodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to 100
                                ))
                                methodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to 100
                                ))
                                safeSuccess(outPath)
                            }
                        },
                        onError = { error ->
                            safeError("TRIM_ERROR", error)
                        }
                    )
                }
                "mergeVideos" -> {
                    val inputPaths = call.argument<List<String>>("inputPaths")
                    val outputPath = call.argument<String>("outputPath")

                    if (inputPaths.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                        result.error("INVALID_ARGS", "Invalid merge arguments", null)
                        return@setMethodCallHandler
                    }

                    if (videoEditorHelper == null) {
                        videoEditorHelper = VideoEditorHelper(applicationContext)
                    }

                    val isReplied = java.util.concurrent.atomic.AtomicBoolean(false)
                    fun safeSuccess(data: Any?) {
                        if (isReplied.compareAndSet(false, true)) {
                            runOnUiThread {
                                stopTransferNotification()
                                result.success(data)
                            }
                        }
                    }
                    fun safeError(code: String, message: String?) {
                        if (isReplied.compareAndSet(false, true)) {
                            runOnUiThread {
                                stopTransferNotification()
                                result.error(code, message, null)
                            }
                        }
                    }

                    var lastNotifiedP = -1
                    updateTransferNotification("Merging Videos", "Combining ${inputPaths.size} clips...", 0, 100)

                    videoEditorHelper?.mergeVideos(
                        inputPaths,
                        outputPath,
                        onProgress = { progress ->
                            runOnUiThread {
                                videoMethodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to progress
                                ))
                                methodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to progress
                                ))
                                if (progress != lastNotifiedP) {
                                    lastNotifiedP = progress
                                    updateTransferNotification("Merging Videos", "Rendering: $progress%", progress, 100)
                                }
                            }
                        },
                        onComplete = { outPath ->
                            runOnUiThread {
                                videoMethodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to 100
                                ))
                                methodChannel?.invokeMethod("onVideoProcessProgress", mapOf(
                                    "progress" to 100
                                ))
                                safeSuccess(outPath)
                            }
                        },
                        onError = { error ->
                            safeError("MERGE_ERROR", error)
                        }
                    )
                }
                "cancelVideoProcess" -> {
                    videoEditorHelper?.cancel()
                    stopTransferNotification()
                    result.success(true)
                }
                "getVideoMetadata" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                        return@setMethodCallHandler
                    }
                    if (videoEditorHelper == null) {
                        videoEditorHelper = VideoEditorHelper(applicationContext)
                    }
                    val meta = videoEditorHelper?.getVideoMetadata(path) ?: emptyMap<String, Any>()
                    result.success(meta)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        abandonAudioFocus()
        releaseMediaSession()
        videoEditorHelper?.cancel()
        stopTransferNotification()
        super.onDestroy()
    }

    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (event.action == android.view.KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                android.view.KeyEvent.KEYCODE_HEADSETHOOK,
                android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                    runOnUiThread {
                        methodChannel?.invokeMethod("onMediaPlayPause", null)
                    }
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_PLAY -> {
                    runOnUiThread {
                        methodChannel?.invokeMethod("onMediaPlay", null)
                    }
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                    runOnUiThread {
                        methodChannel?.invokeMethod("onMediaPause", null)
                    }
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_NEXT -> {
                    runOnUiThread {
                        methodChannel?.invokeMethod("onMediaNext", null)
                    }
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS -> {
                    runOnUiThread {
                        methodChannel?.invokeMethod("onMediaPrevious", null)
                    }
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }
}
