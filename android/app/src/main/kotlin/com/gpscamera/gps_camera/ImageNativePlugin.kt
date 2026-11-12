package com.gpscamera.gps_camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Native image helpers for GPS Camera (channel "com.gpscamera/image_native").
 *
 * - readMetadata: reads EXIF via androidx ExifInterface.
 * - writeMetadata: lossless EXIF update (ExifInterface.saveAttributes rewrites
 *   only the metadata segment; pixel data is not recompressed).
 * - encodeJpeg: encodes raw RGBA pixels to JPEG and copies metadata from a source file.
 * - stripGpsCopy: copies a file and removes all GPS tags from the copy.
 *
 * All work runs on a single background thread; results are posted on the main thread.
 */
class ImageNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private class NativeError(val code: String, message: String) : Exception(message)

    private var channel: MethodChannel? = null
    private var executor: ExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        executor = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        executor?.shutdown()
        executor = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val work: (() -> Any?) = when (call.method) {
            "readMetadata" -> { -> readMetadata(requireArg(call, "path")) }
            "writeMetadata" -> { ->
                writeMetadata(requireArg(call, "path"), call.argument<Map<String, Any?>>("values") ?: emptyMap())
                null
            }
            "encodeJpeg" -> { -> encodeJpeg(call) }
            "stripGpsCopy" -> { ->
                stripGpsCopy(requireArg(call, "sourcePath"), requireArg(call, "outputPath"))
                null
            }
            else -> {
                result.notImplemented()
                return
            }
        }
        val exec = executor
        if (exec == null || exec.isShutdown) {
            result.error("UNAVAILABLE", "Image service is not running.", null)
            return
        }
        exec.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: NativeError) {
                mainHandler.post { result.error(e.code, e.message, null) }
            } catch (e: OutOfMemoryError) {
                mainHandler.post {
                    result.error("OUT_OF_MEMORY", "Not enough memory to process this image.", null)
                }
            } catch (e: Throwable) {
                val msg = e.message ?: e.javaClass.simpleName
                val code = if (isNoSpace(e)) "NO_SPACE" else "${call.method.uppercase()}_FAILED"
                mainHandler.post { result.error(code, msg, null) }
            }
        }
    }

    private fun <T> requireArg(call: MethodCall, name: String): T =
        call.argument<T>(name) ?: throw NativeError("BAD_ARGS", "Missing argument '$name'.")

    // ------------------------------------------------------------------ read

    private fun readMetadata(path: String): Map<String, Any?> {
        val file = File(path)
        if (!file.exists()) throw NativeError("NOT_FOUND", "File not found: $path")
        val format = detectFormat(file)
        val out = HashMap<String, Any?>()
        out["format"] = format
        out["writeSupported"] = format in WRITABLE_FORMATS

        // Pixel dimensions (as stored, i.e. before applying orientation).
        try {
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, opts)
            if (opts.outWidth > 0 && opts.outHeight > 0) {
                out["imageWidth"] = opts.outWidth
                out["imageHeight"] = opts.outHeight
            }
        } catch (_: Throwable) {
        }

        val exif = try {
            ExifInterface(path)
        } catch (_: Throwable) {
            null
        } ?: return out

        fun put(key: String, tag: String) {
            val v = safeGet(exif, tag)
            if (!v.isNullOrBlank()) out[key] = v.trim()
        }
        put("dateTimeOriginal", ExifInterface.TAG_DATETIME_ORIGINAL)
        put("dateTimeDigitized", ExifInterface.TAG_DATETIME_DIGITIZED)
        put("dateTime", ExifInterface.TAG_DATETIME)
        put("offsetTimeOriginal", ExifInterface.TAG_OFFSET_TIME_ORIGINAL)
        put("offsetTime", ExifInterface.TAG_OFFSET_TIME)
        put("gpsDateStamp", ExifInterface.TAG_GPS_DATESTAMP)
        put("gpsTimeStamp", ExifInterface.TAG_GPS_TIMESTAMP)
        put("imageDescription", ExifInterface.TAG_IMAGE_DESCRIPTION)
        put("artist", ExifInterface.TAG_ARTIST)
        put("copyright", ExifInterface.TAG_COPYRIGHT)
        put("userComment", ExifInterface.TAG_USER_COMMENT)
        put("make", ExifInterface.TAG_MAKE)
        put("model", ExifInterface.TAG_MODEL)
        put("software", ExifInterface.TAG_SOFTWARE)

        try {
            exif.latLong?.let {
                out["gpsLatitude"] = it[0]
                out["gpsLongitude"] = it[1]
            }
        } catch (_: Throwable) {
        }
        try {
            if (exif.getAttribute(ExifInterface.TAG_GPS_ALTITUDE) != null) {
                val alt = exif.getAltitude(Double.NaN)
                if (!alt.isNaN()) out["gpsAltitude"] = alt
            }
        } catch (_: Throwable) {
        }
        try {
            val o = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_UNDEFINED)
            if (o != ExifInterface.ORIENTATION_UNDEFINED) out["orientation"] = o
        } catch (_: Throwable) {
        }
        if (!out.containsKey("imageWidth")) {
            val w = exif.getAttributeInt(ExifInterface.TAG_IMAGE_WIDTH, 0)
            val h = exif.getAttributeInt(ExifInterface.TAG_IMAGE_LENGTH, 0)
            if (w > 0 && h > 0) {
                out["imageWidth"] = w
                out["imageHeight"] = h
            }
        }

        val raw = LinkedHashMap<String, String>()
        for (tag in ALL_TAGS) {
            if (tag in RAW_SKIP_TAGS) continue
            val v = safeGet(exif, tag) ?: continue
            val clean = v.replace("\u0000", "").trim()
            if (clean.isEmpty()) continue
            raw[tag] = if (clean.length > 300) clean.substring(0, 300) + "…" else clean
        }
        out["rawTags"] = raw
        return out
    }

    private fun safeGet(exif: ExifInterface, tag: String): String? = try {
        exif.getAttribute(tag)
    } catch (_: Throwable) {
        null
    }

    // ------------------------------------------------------------------ write

    private fun writeMetadata(path: String, values: Map<String, Any?>) {
        val file = File(path)
        if (!file.exists()) throw NativeError("NOT_FOUND", "File not found: $path")
        val format = detectFormat(file)
        if (format !in WRITABLE_FORMATS) {
            throw NativeError(
                "UNSUPPORTED_FORMAT",
                "EXIF writing is not supported for ${format.uppercase()} files on Android " +
                    "(supported: JPEG, PNG, WebP)."
            )
        }
        val exif = ExifInterface(path)

        if (values.containsKey("gpsLatitude") || values.containsKey("gpsLongitude")) {
            val lat = (values["gpsLatitude"] as? Number)?.toDouble()
            val lon = (values["gpsLongitude"] as? Number)?.toDouble()
            if (lat != null && lon != null) {
                if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
                    throw NativeError("BAD_ARGS", "Coordinates out of range.")
                }
                exif.setLatLong(lat, lon)
            } else {
                exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE, null)
                exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, null)
                exif.setAttribute(ExifInterface.TAG_GPS_LONGITUDE, null)
                exif.setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, null)
            }
        }

        if (values.containsKey("gpsAltitude")) {
            val alt = (values["gpsAltitude"] as? Number)?.toDouble()
            if (alt != null) {
                exif.setAltitude(alt)
            } else {
                exif.setAttribute(ExifInterface.TAG_GPS_ALTITUDE, null)
                exif.setAttribute(ExifInterface.TAG_GPS_ALTITUDE_REF, null)
            }
        }

        for ((key, tag) in STRING_KEYS) {
            if (!values.containsKey(key)) continue
            var v = values[key] as? String
            if (v != null && v.isBlank()) v = null
            when (key) {
                // ExifInterface expects "HH:mm:ss" and converts it to the rational triple.
                "gpsTimeStamp" -> if (v != null) {
                    val m = Regex("^(\\d{1,2}):(\\d{2}):(\\d{2})").find(v)
                        ?: throw NativeError("BAD_ARGS", "GPS time must be HH:mm:ss.")
                    v = "%02d:%s:%s".format(m.groupValues[1].toInt(), m.groupValues[2], m.groupValues[3])
                }
                // UserComment is an UNDEFINED field that must start with an 8-byte charset code.
                "userComment" -> if (v != null) v = "ASCII\u0000\u0000\u0000$v"
            }
            exif.setAttribute(tag, v)
        }

        try {
            exif.saveAttributes()
        } catch (e: IOException) {
            if (isNoSpace(e)) throw NativeError("NO_SPACE", "Not enough storage space to save metadata.")
            throw NativeError("WRITE_FAILED", e.message ?: "Could not save metadata.")
        } catch (e: UnsupportedOperationException) {
            throw NativeError("UNSUPPORTED_FORMAT", e.message ?: "This file format does not support EXIF writing.")
        }
    }

    // ------------------------------------------------------------------ encode

    private fun encodeJpeg(call: MethodCall): Map<String, Any?> {
        val rgba: ByteArray = requireArg(call, "rgba")
        val width: Int = requireArg(call, "width")
        val height: Int = requireArg(call, "height")
        val quality: Int = call.argument<Int>("quality") ?: 92
        val outputPath: String = requireArg(call, "outputPath")
        val sourcePath: String? = call.argument<String>("metadataSourcePath")
        val resetOrientation: Boolean = call.argument<Boolean>("resetOrientation") ?: true

        if (width <= 0 || height <= 0 || rgba.size < width.toLong() * height * 4) {
            throw NativeError("BAD_ARGS", "Pixel buffer does not match ${width}x$height.")
        }

        val out = File(outputPath)
        out.parentFile?.mkdirs()
        val tmp = File(outputPath + ".tmp")
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgba, 0, width * height * 4))
            FileOutputStream(tmp).use { fos ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), fos)) {
                    throw NativeError("ENCODE_FAILED", "JPEG encoding failed.")
                }
                fos.fd.sync()
            }
        } catch (e: IOException) {
            tmp.delete()
            if (isNoSpace(e)) throw NativeError("NO_SPACE", "Not enough storage space to save the photo.")
            throw e
        } finally {
            bitmap.recycle()
        }

        // Copy metadata from the source image into the new JPEG.
        if (sourcePath != null && File(sourcePath).exists()) {
            try {
                val src = ExifInterface(sourcePath)
                val dst = ExifInterface(tmp.absolutePath)
                for (tag in ALL_TAGS) {
                    if (tag in COPY_SKIP_TAGS) continue
                    val v = safeGet(src, tag) ?: continue
                    try {
                        dst.setAttribute(tag, v)
                    } catch (_: Throwable) {
                    }
                }
                val orientation = if (resetOrientation) {
                    ExifInterface.ORIENTATION_NORMAL
                } else {
                    src.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                }
                dst.setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
                dst.setAttribute(ExifInterface.TAG_PIXEL_X_DIMENSION, width.toString())
                dst.setAttribute(ExifInterface.TAG_PIXEL_Y_DIMENSION, height.toString())
                dst.saveAttributes()
            } catch (e: IOException) {
                if (isNoSpace(e)) {
                    tmp.delete()
                    throw NativeError("NO_SPACE", "Not enough storage space to save the photo.")
                }
                // Metadata copy failure leaves a valid JPEG; Dart verifies metadata afterwards.
            } catch (_: Throwable) {
            }
        }

        if (out.exists()) out.delete()
        if (!tmp.renameTo(out)) {
            tmp.copyTo(out, overwrite = true)
            tmp.delete()
        }
        return mapOf("fileSize" to out.length())
    }

    // ------------------------------------------------------------------ strip

    private fun stripGpsCopy(sourcePath: String, outputPath: String) {
        val src = File(sourcePath)
        if (!src.exists()) throw NativeError("NOT_FOUND", "File not found: $sourcePath")
        val format = detectFormat(src)
        if (format !in WRITABLE_FORMATS) {
            throw NativeError(
                "UNSUPPORTED_FORMAT",
                "Location metadata cannot be removed from ${format.uppercase()} files on Android."
            )
        }
        val out = File(outputPath)
        out.parentFile?.mkdirs()
        src.copyTo(out, overwrite = true)
        try {
            val exif = ExifInterface(out.absolutePath)
            for (tag in GPS_TAGS) exif.setAttribute(tag, null)
            exif.saveAttributes()
        } catch (e: Throwable) {
            out.delete()
            if (isNoSpace(e)) throw NativeError("NO_SPACE", "Not enough storage space.")
            throw NativeError("WRITE_FAILED", e.message ?: "Could not remove location metadata.")
        }
    }

    // ------------------------------------------------------------------ helpers

    private fun detectFormat(file: File): String {
        val header = ByteArray(16)
        val n = try {
            FileInputStream(file).use { it.read(header) }
        } catch (_: IOException) {
            -1
        }
        if (n < 12) return "unknown"
        fun b(i: Int) = header[i].toInt() and 0xFF
        fun ascii(from: Int, len: Int) = String(header, from, len, Charsets.US_ASCII)
        return when {
            b(0) == 0xFF && b(1) == 0xD8 && b(2) == 0xFF -> "jpeg"
            b(0) == 0x89 && ascii(1, 3) == "PNG" -> "png"
            ascii(0, 4) == "RIFF" && ascii(8, 4) == "WEBP" -> "webp"
            ascii(0, 4) == "GIF8" -> "gif"
            (ascii(0, 4) == "II*\u0000") || (ascii(0, 4) == "MM\u0000*") -> "tiff"
            ascii(4, 4) == "ftyp" -> when (ascii(8, 4)) {
                "heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs" -> "heic"
                "avif", "avis" -> "avif"
                else -> "heif"
            }
            else -> "unknown"
        }
    }

    private fun isNoSpace(e: Throwable): Boolean {
        var t: Throwable? = e
        while (t != null) {
            val m = t.message ?: ""
            if (m.contains("ENOSPC") || m.contains("No space left", ignoreCase = true)) return true
            t = t.cause
        }
        return false
    }

    companion object {
        const val CHANNEL = "com.gpscamera/image_native"

        private val WRITABLE_FORMATS = setOf("jpeg", "png", "webp")

        private val STRING_KEYS = linkedMapOf(
            "dateTimeOriginal" to ExifInterface.TAG_DATETIME_ORIGINAL,
            "dateTimeDigitized" to ExifInterface.TAG_DATETIME_DIGITIZED,
            "dateTime" to ExifInterface.TAG_DATETIME,
            "offsetTimeOriginal" to ExifInterface.TAG_OFFSET_TIME_ORIGINAL,
            "offsetTimeDigitized" to ExifInterface.TAG_OFFSET_TIME_DIGITIZED,
            "offsetTime" to ExifInterface.TAG_OFFSET_TIME,
            "gpsDateStamp" to ExifInterface.TAG_GPS_DATESTAMP,
            "gpsTimeStamp" to ExifInterface.TAG_GPS_TIMESTAMP,
            "imageDescription" to ExifInterface.TAG_IMAGE_DESCRIPTION,
            "artist" to ExifInterface.TAG_ARTIST,
            "copyright" to ExifInterface.TAG_COPYRIGHT,
            "userComment" to ExifInterface.TAG_USER_COMMENT,
        )

        /** (fieldName, tagValue) for every public ExifInterface.TAG_* constant. */
        private val TAG_FIELDS: List<Pair<String, String>> by lazy {
            ExifInterface::class.java.fields
                .filter { it.name.startsWith("TAG_") && it.type == String::class.java }
                .mapNotNull { f ->
                    try {
                        f.name to (f.get(null) as String)
                    } catch (_: Throwable) {
                        null
                    }
                }
                .distinctBy { it.second }
        }

        private val ALL_TAGS: List<String> by lazy { TAG_FIELDS.map { it.second } }

        private val GPS_TAGS: List<String> by lazy {
            TAG_FIELDS.filter { it.first.startsWith("TAG_GPS_") }.map { it.second }
        }

        private val SKIP_PREFIXES = listOf("TAG_RW2_", "TAG_ORF_", "TAG_DNG_", "TAG_THUMBNAIL_", "TAG_STRIP_")

        private val BINARY_OR_STRUCTURAL = setOf(
            ExifInterface.TAG_MAKER_NOTE,
            ExifInterface.TAG_XMP,
            ExifInterface.TAG_JPEG_INTERCHANGE_FORMAT,
            ExifInterface.TAG_JPEG_INTERCHANGE_FORMAT_LENGTH,
            ExifInterface.TAG_STRIP_OFFSETS,
            ExifInterface.TAG_STRIP_BYTE_COUNTS,
            ExifInterface.TAG_ROWS_PER_STRIP,
        )

        /** Tags never shown in the raw tag list. */
        private val RAW_SKIP_TAGS: Set<String> by lazy {
            BINARY_OR_STRUCTURAL + TAG_FIELDS.filter { f -> SKIP_PREFIXES.any { f.first.startsWith(it) } }
                .map { it.second }
        }

        /** Tags not copied into a newly encoded JPEG (they describe the old pixel data). */
        private val COPY_SKIP_TAGS: Set<String> by lazy {
            RAW_SKIP_TAGS + setOf(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.TAG_IMAGE_WIDTH,
                ExifInterface.TAG_IMAGE_LENGTH,
                ExifInterface.TAG_PIXEL_X_DIMENSION,
                ExifInterface.TAG_PIXEL_Y_DIMENSION,
                ExifInterface.TAG_COMPRESSION,
                ExifInterface.TAG_BITS_PER_SAMPLE,
                ExifInterface.TAG_PHOTOMETRIC_INTERPRETATION,
                ExifInterface.TAG_SAMPLES_PER_PIXEL,
                ExifInterface.TAG_PLANAR_CONFIGURATION,
                ExifInterface.TAG_NEW_SUBFILE_TYPE,
                ExifInterface.TAG_SUBFILE_TYPE,
                ExifInterface.TAG_DEFAULT_CROP_SIZE,
                ExifInterface.TAG_Y_CB_CR_SUB_SAMPLING,
                ExifInterface.TAG_Y_CB_CR_POSITIONING,
            )
        }
    }
}
