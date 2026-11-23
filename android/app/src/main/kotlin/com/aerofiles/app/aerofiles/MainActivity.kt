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
    private val thumbnailExecutor = Executors.newFixedThreadPool(4)

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
                                    val linkFile = File(context.cacheDir, "th_${System.nanoTime()}_${Thread.currentThread().id}.ts")
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
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
