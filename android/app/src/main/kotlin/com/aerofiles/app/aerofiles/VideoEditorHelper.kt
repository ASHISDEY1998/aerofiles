package com.aerofiles.app.aerofiles

import android.content.Context
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import java.io.File

class VideoEditorHelper(private val context: Context) {
    private var currentTransformer: Transformer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    private var isRunning = false

    fun cancel() {
        handler.post {
            try {
                isRunning = false
                progressRunnable?.let { handler.removeCallbacks(it) }
                progressRunnable = null
                currentTransformer?.cancel()
                currentTransformer = null
            } catch (_: Throwable) {}
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
            cancel()
            isRunning = true

            try {
                val inputFile = File(inputPath)
                if (!inputFile.exists()) {
                    onError("Source file does not exist")
                    isRunning = false
                    return@post
                }

                val outputFile = File(outputPath)
                outputFile.parentFile?.mkdirs()
                if (outputFile.exists()) {
                    outputFile.delete()
                }

                val mediaItem = MediaItem.Builder()
                    .setUri(Uri.fromFile(inputFile))
                    .setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(startMs)
                            .setEndPositionMs(endMs)
                            .build()
                    )
                    .build()

                val editedItem = EditedMediaItem.Builder(mediaItem).build()
                val sequence = EditedMediaItemSequence(editedItem)
                val composition = Composition.Builder(sequence).build()

                val progressHolder = ProgressHolder()

                val transformer = Transformer.Builder(context)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                            isRunning = false
                            progressRunnable?.let { handler.removeCallbacks(it) }
                            currentTransformer = null
                            MediaScannerConnection.scanFile(context, arrayOf(outputPath), null, null)
                            onComplete(outputPath)
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            isRunning = false
                            progressRunnable?.let { handler.removeCallbacks(it) }
                            currentTransformer = null
                            try {
                                outputFile.delete()
                            } catch (_: Throwable) {}
                            onError(exportException.message ?: "Trimming failed")
                        }
                    })
                    .build()

                currentTransformer = transformer

                progressRunnable = object : Runnable {
                    override fun run() {
                        if (!isRunning || currentTransformer == null) return
                        val state = currentTransformer?.getProgress(progressHolder)
                        if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                            onProgress(progressHolder.progress)
                        }
                        if (isRunning) {
                            handler.postDelayed(this, 100)
                        }
                    }
                }
                handler.post(progressRunnable!!)

                transformer.start(composition, outputPath)
            } catch (e: Throwable) {
                isRunning = false
                progressRunnable?.let { handler.removeCallbacks(it) }
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
            cancel()
            isRunning = true

            try {
                if (inputPaths.isEmpty()) {
                    onError("No input videos provided")
                    isRunning = false
                    return@post
                }

                for (p in inputPaths) {
                    if (!File(p).exists()) {
                        onError("Source file does not exist: $p")
                        isRunning = false
                        return@post
                    }
                }

                val outputFile = File(outputPath)
                outputFile.parentFile?.mkdirs()
                if (outputFile.exists()) {
                    outputFile.delete()
                }

                val editedItems = inputPaths.map { path ->
                    val mediaItem = MediaItem.fromUri(Uri.fromFile(File(path)))
                    EditedMediaItem.Builder(mediaItem).build()
                }

                val sequence = EditedMediaItemSequence(editedItems)
                val composition = Composition.Builder(sequence).build()

                val progressHolder = ProgressHolder()

                val transformer = Transformer.Builder(context)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                            isRunning = false
                            progressRunnable?.let { handler.removeCallbacks(it) }
                            currentTransformer = null
                            MediaScannerConnection.scanFile(context, arrayOf(outputPath), null, null)
                            onComplete(outputPath)
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            isRunning = false
                            progressRunnable?.let { handler.removeCallbacks(it) }
                            currentTransformer = null
                            try {
                                outputFile.delete()
                            } catch (_: Throwable) {}
                            onError(exportException.message ?: "Merging failed")
                        }
                    })
                    .build()

                currentTransformer = transformer

                progressRunnable = object : Runnable {
                    override fun run() {
                        if (!isRunning || currentTransformer == null) return
                        val state = currentTransformer?.getProgress(progressHolder)
                        if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                            onProgress(progressHolder.progress)
                        }
                        if (isRunning) {
                            handler.postDelayed(this, 100)
                        }
                    }
                }
                handler.post(progressRunnable!!)

                transformer.start(composition, outputPath)
            } catch (e: Throwable) {
                isRunning = false
                progressRunnable?.let { handler.removeCallbacks(it) }
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
