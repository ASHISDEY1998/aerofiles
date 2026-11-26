package com.aerofiles.app.aerofiles

import android.content.Context
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMuxer
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import java.io.File

class VideoEditorHelper(private val context: Context) {
    private var currentTransformer: Transformer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    private var isRunning = false

    private fun internalCancel() {
        try {
            isRunning = false
            progressRunnable?.let { handler.removeCallbacks(it) }
            progressRunnable = null
            currentTransformer?.cancel()
            currentTransformer = null
        } catch (_: Throwable) {}
    }

    fun cancel() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            internalCancel()
        } else {
            handler.post { internalCancel() }
        }
    }

    fun trimVideo(
        inputPath: String,
        outputPath: String,
        startMs: Long,
        endMs: Long,
        onProgress: (Int) -> Unit,
        onComplete: (String) -> Unit,
        onError: (String) -> Unit
    ) {
        handler.post {
            internalCancel()
            isRunning = true

            try {
                val inputFile = File(inputPath)
                if (!inputFile.exists()) {
                    isRunning = false
                    onError("Source file does not exist")
                    return@post
                }

                val outputFile = File(outputPath)
                outputFile.parentFile?.mkdirs()
                if (outputFile.exists()) {
                    outputFile.delete()
                }

                // Determine target dimensions from input video to ensure even dimensions
                val meta = getVideoMetadata(inputPath)
                var targetWidth = (meta["width"] as? Number)?.toInt() ?: 1280
                var targetHeight = (meta["height"] as? Number)?.toInt() ?: 720
                val rotation = (meta["rotation"] as? Number)?.toInt() ?: 0

                if (rotation == 90 || rotation == 270) {
                    val tmp = targetWidth
                    targetWidth = targetHeight
                    targetHeight = tmp
                }

                if (targetWidth <= 0) targetWidth = 1280
                if (targetHeight <= 0) targetHeight = 720
                // Ensure even dimensions required by H.264 video encoders
                if (targetWidth % 2 != 0) targetWidth -= 1
                if (targetHeight % 2 != 0) targetHeight -= 1

                val presentationEffect = Presentation.createForWidthAndHeight(
                    targetWidth,
                    targetHeight,
                    Presentation.LAYOUT_SCALE_TO_FIT
                )

                val compositionEffects = Effects(
                    emptyList(),
                    listOf(presentationEffect)
                )

                val mediaItem = MediaItem.Builder()
                    .setUri(Uri.fromFile(inputFile))
                    .setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(startMs)
                            .setEndPositionMs(endMs)
                            .setStartsAtKeyFrame(false)
                            .build()
                    )
                    .build()

                val editedItem = EditedMediaItem.Builder(mediaItem).build()
                val sequence = EditedMediaItemSequence(editedItem)
                val composition = Composition.Builder(sequence)
                    .setEffects(compositionEffects)
                    .experimentalSetForceAudioTrack(true)
                    .build()

                val progressHolder = ProgressHolder()

                val transformer = Transformer.Builder(context)
                    .setLooper(Looper.getMainLooper())
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .setMuxerFactory(InAppMuxer.Factory.Builder().build())
                    .setEncoderFactory(
                        DefaultEncoderFactory.Builder(context)
                            .setEnableFallback(true)
                            .build()
                    )
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(comp: Composition, exportResult: ExportResult) {
                            isRunning = false
                            progressRunnable?.let { handler.removeCallbacks(it) }
                            progressRunnable = null
                            currentTransformer = null
                            MediaScannerConnection.scanFile(context, arrayOf(outputPath), null, null)
                            onProgress(100)
                            onComplete(outputPath)
                        }

                        override fun onError(
                            comp: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            isRunning = false
                            progressRunnable?.let { handler.removeCallbacks(it) }
                            progressRunnable = null
                            currentTransformer = null
                            try {
                                outputFile.delete()
                            } catch (_: Throwable) {}

                            val errorDetails = buildString {
                                append(exportException.message ?: "Trimming failed")
                                exportException.cause?.let { cause ->
                                    append(": ")
                                    append(cause.message ?: cause.javaClass.simpleName)
                                }
                            }
                            onError(errorDetails)
                        }
                    })
                    .build()

                currentTransformer = transformer

                progressRunnable = object : Runnable {
                    private var lastProgress = -1
                    override fun run() {
                        if (!isRunning || currentTransformer == null) return
                        try {
                            val state = currentTransformer?.getProgress(progressHolder)
                            if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                                val p = progressHolder.progress.coerceIn(0, 100)
                                if (p != lastProgress) {
                                    lastProgress = p
                                    onProgress(p)
                                }
                            }
                        } catch (_: Throwable) {}
                        if (isRunning) {
                            handler.postDelayed(this, 150)
                        }
                    }
                }

                transformer.start(composition, outputPath)
                handler.post(progressRunnable!!)
            } catch (e: Throwable) {
                isRunning = false
                progressRunnable?.let { handler.removeCallbacks(it) }
                progressRunnable = null
                currentTransformer = null
                onError(e.message ?: "Failed to start trim")
            }
        }
    }

    fun mergeVideos(
        inputPaths: List<String>,
        outputPath: String,
        onProgress: (Int) -> Unit,
        onComplete: (String) -> Unit,
        onError: (String) -> Unit
    ) {
        handler.post {
            internalCancel()
            isRunning = true

            try {
                if (inputPaths.isEmpty()) {
                    isRunning = false
                    onError("No input videos provided")
                    return@post
                }

                for (p in inputPaths) {
                    if (!File(p).exists()) {
                        isRunning = false
                        onError("Source file does not exist: $p")
                        return@post
                    }
                }

                val outputFile = File(outputPath)
                outputFile.parentFile?.mkdirs()
                if (outputFile.exists()) {
                    outputFile.delete()
                }

                // Determine target width and height from the first video
                val firstMeta = getVideoMetadata(inputPaths.first())
                var targetWidth = (firstMeta["width"] as? Number)?.toInt() ?: 1280
                var targetHeight = (firstMeta["height"] as? Number)?.toInt() ?: 720
                val rotation = (firstMeta["rotation"] as? Number)?.toInt() ?: 0

                // If portrait via rotation metadata, swap dimensions
                if (rotation == 90 || rotation == 270) {
                    val tmp = targetWidth
                    targetWidth = targetHeight
                    targetHeight = tmp
                }

                if (targetWidth <= 0) targetWidth = 1280
                if (targetHeight <= 0) targetHeight = 720
                if (targetWidth % 2 != 0) targetWidth -= 1
                if (targetHeight % 2 != 0) targetHeight -= 1

                val presentationEffect = Presentation.createForWidthAndHeight(
                    targetWidth,
                    targetHeight,
                    Presentation.LAYOUT_SCALE_TO_FIT
                )

                val compositionEffects = Effects(
                    emptyList(),
                    listOf(presentationEffect)
                )

                val editedItems = inputPaths.map { path ->
                    val mediaItem = MediaItem.fromUri(Uri.fromFile(File(path)))
                    EditedMediaItem.Builder(mediaItem).build()
                }

                val sequence = EditedMediaItemSequence(editedItems)
                val composition = Composition.Builder(sequence)
                    .setEffects(compositionEffects)
                    .experimentalSetForceAudioTrack(true)
                    .build()

                val progressHolder = ProgressHolder()

                val transformer = Transformer.Builder(context)
                    .setLooper(Looper.getMainLooper())
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .setMuxerFactory(InAppMuxer.Factory.Builder().build())
                    .setEncoderFactory(
                        DefaultEncoderFactory.Builder(context)
                            .setEnableFallback(true)
                            .build()
                    )
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(comp: Composition, exportResult: ExportResult) {
                            isRunning = false
                            progressRunnable?.let { handler.removeCallbacks(it) }
                            progressRunnable = null
                            currentTransformer = null
                            MediaScannerConnection.scanFile(context, arrayOf(outputPath), null, null)
                            onProgress(100)
                            onComplete(outputPath)
                        }

                        override fun onError(
                            comp: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            isRunning = false
                            progressRunnable?.let { handler.removeCallbacks(it) }
                            progressRunnable = null
                            currentTransformer = null
                            try {
                                outputFile.delete()
                            } catch (_: Throwable) {}

                            val errorDetails = buildString {
                                append(exportException.message ?: "Merging failed")
                                exportException.cause?.let { cause ->
                                    append(": ")
                                    append(cause.message ?: cause.javaClass.simpleName)
                                }
                            }
                            onError(errorDetails)
                        }
                    })
                    .build()

                currentTransformer = transformer

                progressRunnable = object : Runnable {
                    private var lastProgress = -1
                    override fun run() {
                        if (!isRunning || currentTransformer == null) return
                        try {
                            val state = currentTransformer?.getProgress(progressHolder)
                            if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                                val p = progressHolder.progress.coerceIn(0, 100)
                                if (p != lastProgress) {
                                    lastProgress = p
                                    onProgress(p)
                                }
                            }
                        } catch (_: Throwable) {}
                        if (isRunning) {
                            handler.postDelayed(this, 150)
                        }
                    }
                }

                transformer.start(composition, outputPath)
                handler.post(progressRunnable!!)
            } catch (e: Throwable) {
                isRunning = false
                progressRunnable?.let { handler.removeCallbacks(it) }
                progressRunnable = null
                currentTransformer = null
                onError(e.message ?: "Failed to start merge")
            }
        }
    }

    fun getVideoMetadata(path: String): Map<String, Any> {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val widthStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val heightStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val rotationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            val durationMs = durationStr?.toLongOrNull() ?: 0L
            val width = widthStr?.toIntOrNull() ?: 0
            val height = heightStr?.toIntOrNull() ?: 0
            val rotation = rotationStr?.toIntOrNull() ?: 0
            val file = File(path)

            mapOf(
                "durationMs" to durationMs,
                "width" to width,
                "height" to height,
                "rotation" to rotation,
                "sizeBytes" to file.length()
            )
        } catch (_: Throwable) {
            mapOf(
                "durationMs" to 0L,
                "width" to 0,
                "height" to 0,
                "rotation" to 0,
                "sizeBytes" to (File(path).length())
            )
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {}
        }
    }
}
