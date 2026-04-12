package com.rethinkos.trackos.screenshot

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream

class ScreenshotPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var mediaProjection: MediaProjection? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val REQUEST_CODE = 9876

    // ── FlutterPlugin ─────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.rethinkos.trackos/screenshot")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        mediaProjection?.stop()
        mediaProjection = null
    }

    // ── ActivityAware ─────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activity = null
        activityBinding = null
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activity = null
        activityBinding = null
    }

    // ── MethodCallHandler ─────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> requestPermission(result)
            "takeScreenshot"    -> takeScreenshot(result)
            "openDirectory"     -> {
                val path = call.argument<String>("path") ?: run {
                    result.error("NO_PATH", "path is required", null)
                    return
                }
                openDirectory(path, result)
            }
            else -> result.notImplemented()
        }
    }

    // ── Permission request ────────────────────────────────────────────────────

    private fun requestPermission(result: MethodChannel.Result) {
        // Already have a valid projection token — no need to ask again.
        if (mediaProjection != null) {
            result.success(true)
            return
        }
        val act = activity ?: run {
            result.error("NO_ACTIVITY", "No foreground activity available", null)
            return
        }
        pendingPermissionResult = result
        val manager = act.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        act.startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val pending = pendingPermissionResult ?: return false
        pendingPermissionResult = null

        return if (resultCode == Activity.RESULT_OK && data != null) {
            val manager = appContext.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = manager.getMediaProjection(resultCode, data)
            pending.success(true)
            true
        } else {
            pending.success(false)
            true
        }
    }

    // ── Open directory ────────────────────────────────────────────────────────

    private fun openDirectory(path: String, result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Build a Documents-UI content URI for the path so the system
                // file manager opens at the correct location.
                val externalRoot = "/storage/emulated/0/"
                val relative = if (path.startsWith(externalRoot))
                    "primary:" + path.removePrefix(externalRoot)
                else null

                if (relative != null) {
                    val docUri = android.provider.DocumentsContract.buildDocumentUri(
                        "com.android.externalstorage.documents", relative
                    )
                    val intent = android.content.Intent(
                        android.content.Intent.ACTION_OPEN_DOCUMENT_TREE
                    ).apply {
                        putExtra(android.provider.DocumentsContract.EXTRA_INITIAL_URI, docUri)
                        addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    appContext.startActivity(intent)
                    result.success(null)
                    return
                }
            }
            // Fallback: generic resource/folder intent (works with most file managers)
            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                setDataAndType(android.net.Uri.fromFile(java.io.File(path)), "resource/folder")
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            appContext.startActivity(
                android.content.Intent.createChooser(intent, "打开文件夹").apply {
                    addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            result.success(null)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message, null)
        }
    }

    // ── Screenshot capture ────────────────────────────────────────────────────

    private fun takeScreenshot(result: MethodChannel.Result) {
        val mp = mediaProjection ?: run {
            result.error(
                "NO_PROJECTION",
                "MediaProjection not initialised. Call requestPermission() first.",
                null
            )
            return
        }

        // Resolve display dimensions.
        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val width: Int
        val height: Int
        val density: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            width = bounds.width()
            height = bounds.height()
            val metrics = appContext.resources.displayMetrics
            density = metrics.densityDpi
        } else {
            @Suppress("DEPRECATION")
            val metrics = DisplayMetrics().also { wm.defaultDisplay.getRealMetrics(it) }
            width = metrics.widthPixels
            height = metrics.heightPixels
            density = metrics.densityDpi
        }

        val handlerThread = HandlerThread("ScreenshotThread")
        handlerThread.start()
        val bgHandler = Handler(handlerThread.looper)

        val imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        var virtualDisplay: VirtualDisplay? = null

        virtualDisplay = mp.createVirtualDisplay(
            "TrackOSCapture",
            width, height, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader.surface, null, bgHandler
        )

        // Poll for the first available frame (up to 3 s, checking every 100 ms).
        var attempts = 0
        bgHandler.postDelayed(object : Runnable {
            override fun run() {
                attempts++
                val image = imageReader.acquireLatestImage()
                if (image != null) {
                    try {
                        val plane = image.planes[0]
                        val buffer = plane.buffer
                        val pixelStride = plane.pixelStride
                        val rowStride = plane.rowStride
                        val rowPadding = rowStride - pixelStride * width

                        val bitmapWidth = width + rowPadding / pixelStride
                        val raw = Bitmap.createBitmap(bitmapWidth, height, Bitmap.Config.ARGB_8888)
                        raw.copyPixelsFromBuffer(buffer)
                        image.close()

                        // Crop away any row-padding columns.
                        val bmp = if (bitmapWidth != width)
                            Bitmap.createBitmap(raw, 0, 0, width, height)
                        else raw

                        val baos = ByteArrayOutputStream()
                        bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
                        val pngBytes = baos.toByteArray()

                        virtualDisplay?.release()
                        imageReader.close()
                        handlerThread.quitSafely()

                        mainHandler.post { result.success(pngBytes) }
                    } catch (e: Exception) {
                        virtualDisplay?.release()
                        imageReader.close()
                        handlerThread.quitSafely()
                        mainHandler.post {
                            result.error("CAPTURE_FAILED", e.message, null)
                        }
                    }
                } else if (attempts < 30) {
                    bgHandler.postDelayed(this, 100)
                } else {
                    virtualDisplay?.release()
                    imageReader.close()
                    handlerThread.quitSafely()
                    mainHandler.post {
                        result.error("TIMEOUT", "No frame received within 3 s", null)
                    }
                }
            }
        }, 200) // 200 ms initial delay to let the VirtualDisplay warm up
    }
}

