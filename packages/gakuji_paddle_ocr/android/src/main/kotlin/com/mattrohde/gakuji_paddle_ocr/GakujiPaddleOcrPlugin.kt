package com.mattrohde.gakuji_paddle_ocr

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import com.paddle.ocr.EngineConfig
import com.paddle.ocr.PaddleOCR
import com.paddle.ocr.PaddleOCRConfig
import com.paddle.ocr.model.OCRResult
import com.paddle.ocr.util.OpenCVUtils
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max

class GakujiPaddleOcrPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var applicationContext: Context
    private lateinit var channel: MethodChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val initializationMutex = Mutex()

    @Volatile
    private var paddleOcr: PaddleOCR? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(
            binding.binaryMessenger,
            "com.mattrohde.gakuji/paddle_ocr",
        )
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        val current = paddleOcr
        paddleOcr = null
        if (current != null) {
            scope.launch {
                runCatching { current.release() }
                scope.cancel()
            }
        } else {
            scope.cancel()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "recognizeLocalizedColumn" -> recognizeLocalizedColumn(call, result)
            "recognizeLocalizedColumns" -> recognizeLocalizedColumns(call, result)
            else -> result.notImplemented()
        }
    }

    private fun recognizeLocalizedColumn(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val imagePath = call.argument<String>("imagePath")
        if (imagePath.isNullOrBlank()) {
            result.error("invalid_argument", "imagePath is required.", null)
            return
        }

        scope.launch {
            try {
                val imageFile = File(imagePath)
                if (!imageFile.isFile) {
                    result.error("invalid_image", "OCR crop does not exist.", null)
                    return@launch
                }

                val imageBytes = withContext(Dispatchers.IO) { imageFile.readBytes() }
                if (imageBytes.isEmpty()) {
                    result.error("invalid_image", "OCR crop is empty.", null)
                    return@launch
                }

                val ocr = getOrCreatePaddleOcr()
                val run = ocr.recognize(imageBytes)
                val selected = selectBestResult(run.results)

                if (selected == null || selected.text.isBlank()) {
                    result.success(null)
                    return@launch
                }

                result.success(
                    mapOf(
                        "text" to selected.text,
                        "confidence" to selected.confidence.toDouble(),
                        "detectedItemCount" to run.results.size,
                        "detectionTimeMs" to run.detectionTimeMs,
                        "recognitionTimeMs" to run.recognitionTimeMs,
                        "totalTimeMs" to run.totalTimeMs,
                    ),
                )
            } catch (error: MissingAssetsException) {
                result.error("paddle_assets_missing", error.message, null)
            } catch (error: Throwable) {
                result.error(
                    "paddle_unavailable",
                    error.message ?: error.javaClass.simpleName,
                    null,
                )
            }
        }
    }

    private fun recognizeLocalizedColumns(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val imagePath = call.argument<String>("imagePath")
        val imageWidth = (call.argument<Number>("imageWidth"))?.toDouble()
        val imageHeight = (call.argument<Number>("imageHeight"))?.toDouble()
        val columns = call.argument<List<*>>("columns")

        if (imagePath.isNullOrBlank() ||
            imageWidth == null || imageWidth <= 0.0 ||
            imageHeight == null || imageHeight <= 0.0 ||
            columns.isNullOrEmpty()
        ) {
            result.error(
                "invalid_argument",
                "imagePath, imageWidth, imageHeight, and columns are required.",
                null,
            )
            return
        }

        scope.launch {
            try {
                val batchStartNs = System.nanoTime()
                val ocr = getOrCreatePaddleOcr()

                val response = withContext(Dispatchers.Default) {
                    val decodeStartNs = System.nanoTime()
                    val decoded = BitmapFactory.decodeFile(imagePath)
                        ?: throw IllegalArgumentException("Could not decode source image.")
                    val sourceBitmap = orientBitmapForExif(decoded, imagePath)
                    if (sourceBitmap !== decoded) {
                        decoded.recycle()
                    }
                    val sourceDecodeTimeMs = nanosToMillis(System.nanoTime() - decodeStartNs)

                    val scaleX = sourceBitmap.width.toDouble() / imageWidth
                    val scaleY = sourceBitmap.height.toDouble() / imageHeight
                    val output = ArrayList<Map<String, Any?>>(columns.size)

                    try {
                        for (rawColumn in columns) {
                            val column = rawColumn as? Map<*, *> ?: continue
                            val requestId = (column["requestId"] as? Number)?.toInt() ?: continue
                            val left = (column["left"] as? Number)?.toDouble() ?: continue
                            val top = (column["top"] as? Number)?.toDouble() ?: continue
                            val right = (column["right"] as? Number)?.toDouble() ?: continue
                            val bottom = (column["bottom"] as? Number)?.toDouble() ?: continue

                            val pixelLeft = floor(left * scaleX)
                                .toInt()
                                .coerceIn(0, max(0, sourceBitmap.width - 1))
                            val pixelTop = floor(top * scaleY)
                                .toInt()
                                .coerceIn(0, max(0, sourceBitmap.height - 1))
                            val pixelRight = ceil(right * scaleX)
                                .toInt()
                                .coerceIn(pixelLeft + 1, sourceBitmap.width)
                            val pixelBottom = ceil(bottom * scaleY)
                                .toInt()
                                .coerceIn(pixelTop + 1, sourceBitmap.height)
                            val cropWidth = pixelRight - pixelLeft
                            val cropHeight = pixelBottom - pixelTop

                            if (cropWidth <= 1 || cropHeight <= 1) {
                                continue
                            }

                            var crop: Bitmap? = null
                            try {
                                crop = Bitmap.createBitmap(
                                    sourceBitmap,
                                    pixelLeft,
                                    pixelTop,
                                    cropWidth,
                                    cropHeight,
                                )
                                val run = ocr.recognize(crop)
                                val selected = selectBestResult(run.results)

                                if (selected != null && selected.text.isNotBlank()) {
                                    output.add(
                                        mapOf(
                                            "requestId" to requestId,
                                            "text" to selected.text,
                                            "confidence" to selected.confidence.toDouble(),
                                            "detectedItemCount" to run.results.size,
                                            "detectionTimeMs" to run.detectionTimeMs,
                                            "recognitionTimeMs" to run.recognitionTimeMs,
                                            "totalTimeMs" to run.totalTimeMs,
                                            "cropWidth" to cropWidth,
                                            "cropHeight" to cropHeight,
                                        ),
                                    )
                                }
                            } finally {
                                if (crop != null && crop !== sourceBitmap && !crop.isRecycled) {
                                    crop.recycle()
                                }
                            }
                        }
                    } finally {
                        if (!sourceBitmap.isRecycled) sourceBitmap.recycle()
                    }

                    mapOf(
                        "results" to output,
                        "sourceDecodeTimeMs" to sourceDecodeTimeMs,
                        "batchWallTimeMs" to nanosToMillis(System.nanoTime() - batchStartNs),
                    )
                }

                result.success(response)
            } catch (error: MissingAssetsException) {
                result.error("paddle_assets_missing", error.message, null)
            } catch (error: Throwable) {
                result.error(
                    "paddle_unavailable",
                    error.message ?: error.javaClass.simpleName,
                    null,
                )
            }
        }
    }

    private suspend fun getOrCreatePaddleOcr(): PaddleOCR {
        paddleOcr?.let { return it }

        return initializationMutex.withLock {
            paddleOcr?.let { return@withLock it }

            ensureModelAssetsExist()

            if (!OpenCVUtils.init(applicationContext)) {
                throw IllegalStateException("OpenCV could not be initialized.")
            }

            val created = PaddleOCR.create(
                context = applicationContext,
                config = PaddleOCRConfig(
                    detThresh = 0.30f,
                    detBoxThresh = 0.60f,
                    recScoreThresh = 0.0f,
                    // This only batches recognition of boxes already found by
                    // the same detector. It does not change model weights,
                    // crop pixels, thresholds, or recognition scoring.
                    recBatchSize = 4,
                ),
                engineConfig = EngineConfig(numThreads = 4),
                detModelAssetPath = "models/det/inference.onnx",
                recModelAssetPath = "models/rec/inference.onnx",
                recConfigAssetPath = "models/rec/inference.yml",
            )
            paddleOcr = created
            created
        }
    }

    private fun ensureModelAssetsExist() {
        val required = listOf(
            "models/det/inference.onnx",
            "models/rec/inference.onnx",
            "models/rec/inference.yml",
        )

        val missing = required.filterNot { assetPath ->
            runCatching {
                applicationContext.assets.open(assetPath).use { stream ->
                    stream.read() >= -1
                }
                true
            }.getOrDefault(false)
        }

        if (missing.isNotEmpty()) {
            throw MissingAssetsException(
                "Missing PaddleOCR assets: ${missing.joinToString()}. " +
                    "Run tools/install_paddle_android.ps1 from the Gakuji root.",
            )
        }
    }

    private fun orientBitmapForExif(bitmap: Bitmap, imagePath: String): Bitmap {
        val orientation = runCatching {
            ExifInterface(imagePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            else -> return bitmap
        }

        return Bitmap.createBitmap(
            bitmap,
            0,
            0,
            bitmap.width,
            bitmap.height,
            matrix,
            true,
        )
    }

    private fun selectBestResult(results: List<OCRResult>): OCRResult? {
        return results
            .filter { japaneseRatio(it.text) >= 0.60 }
            .maxWithOrNull(
                compareBy<OCRResult>(
                    { boxHeight(it) },
                    { boxArea(it) },
                    { it.confidence },
                    { it.text.length },
                ),
            )
            ?: results.maxByOrNull { it.confidence }
    }

    private fun japaneseRatio(text: String): Double {
        val compact = text.filterNot { it.isWhitespace() }
        if (compact.isEmpty()) return 0.0

        val japanese = compact.count { character ->
            val code = character.code
            code in 0x3040..0x309F ||
                code in 0x30A0..0x30FF ||
                code in 0x3400..0x4DBF ||
                code in 0x4E00..0x9FFF ||
                code in 0xF900..0xFAFF ||
                character in "々〆ヶー。、！？・「」『』（）"
        }
        return japanese.toDouble() / compact.length.toDouble()
    }

    private fun boxHeight(result: OCRResult): Float {
        val ys = result.box.points.map { it.y }
        if (ys.isEmpty()) return 0f
        return max(0f, (ys.maxOrNull() ?: 0f) - (ys.minOrNull() ?: 0f))
    }

    private fun boxArea(result: OCRResult): Float {
        val xs = result.box.points.map { it.x }
        val ys = result.box.points.map { it.y }
        if (xs.isEmpty() || ys.isEmpty()) return 0f
        val width = max(0f, (xs.maxOrNull() ?: 0f) - (xs.minOrNull() ?: 0f))
        val height = max(0f, (ys.maxOrNull() ?: 0f) - (ys.minOrNull() ?: 0f))
        return width * height
    }

    private fun nanosToMillis(nanos: Long): Long = nanos / 1_000_000L

    private class MissingAssetsException(message: String) : IllegalStateException(message)
}
