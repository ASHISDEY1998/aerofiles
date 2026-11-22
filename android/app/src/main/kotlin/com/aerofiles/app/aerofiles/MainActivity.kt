package com.aerofiles.app.aerofiles

import android.media.MediaScannerConnection
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aerofiles.app/storage"

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
                    } else {
                        Thread {
                            var retriever: android.media.MediaMetadataRetriever? = null
                            try {
                                retriever = android.media.MediaMetadataRetriever()
                                if (path.startsWith("http://") || path.startsWith("https://")) {
                                    retriever.setDataSource(path, HashMap<String, String>())
                                } else {
                                    retriever.setDataSource(path)
                                }
                                val bitmap = retriever.getFrameAtTime(1000000, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                    ?: retriever.frameAtTime
                                if (bitmap != null) {
                                    // Scale down for thumbnail memory efficiency
                                    val maxDim = 320
                                    val width = bitmap.width
                                    val height = bitmap.height
                                    val scale = if (width > height) maxDim.toFloat() / width else maxDim.toFloat() / height
                                    val scaledBitmap = if (scale < 1.0f) {
                                        android.graphics.Bitmap.createScaledBitmap(
                                            bitmap,
                                            (width * scale).toInt().coerceAtLeast(1),
                                            (height * scale).toInt().coerceAtLeast(1),
                                            true
                                        )
                                    } else {
                                        bitmap
                                    }

                                    val stream = java.io.ByteArrayOutputStream()
                                    scaledBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, stream)
                                    val bytes = stream.toByteArray()
                                    if (scaledBitmap != bitmap) {
                                        scaledBitmap.recycle()
                                    }
                                    bitmap.recycle()
                                    runOnUiThread { result.success(bytes) }
                                } else {
                                    runOnUiThread { result.success(null) }
                                }
                            } catch (_: Exception) {
                                runOnUiThread { result.success(null) }
                            } finally {
                                try {
                                    retriever?.release()
                                } catch (_: Exception) {}
                            }
                        }.start()
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
