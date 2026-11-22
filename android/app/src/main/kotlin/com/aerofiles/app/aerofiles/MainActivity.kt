package com.aerofiles.app.aerofiles

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.media.ThumbnailUtils
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aerofiles.app/storage"
    private val thumbnailExecutor = Executors.newFixedThreadPool(2)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
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
                        var bitmap: Bitmap? = null
                        var retriever: MediaMetadataRetriever? = null
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                try {
                                    bitmap = ThumbnailUtils.createVideoThumbnail(file, Size(320, 320), null)
                                } catch (_: Throwable) {}
                            }

                            if (bitmap == null) {
                                retriever = MediaMetadataRetriever()
                                retriever.setDataSource(path)
                                bitmap = retriever.getFrameAtTime(1000000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                    ?: retriever.frameAtTime
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
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
