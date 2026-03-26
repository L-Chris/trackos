package com.rethinkos.trackos

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Flutter plugin that exposes UsageStats APIs via MethodChannel.
 *
 * Declared as a proper Flutter plugin (path dependency in pubspec.yaml) so
 * that the Flutter build system includes it in GeneratedPluginRegistrant
 * automatically — for EVERY FlutterEngine, including the one created by
 * flutter_background_service.
 */
class UsageStatsPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var activity: Activity? = null

    // ── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.rethinkos.trackos/usage")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // ── ActivityAware ────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // ── MethodCallHandler ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "hasUsageStatsPermission" -> result.success(hasUsageStatsPermission())
            "openUsageAccessSettings" -> {
                val act = activity
                if (act != null) {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    act.startActivity(intent)
                }
                result.success(null)
            }
            "queryUsageSummaries" -> {
                val startMs = (call.argument<Number>("startMs") ?: 0L).toLong()
                val endMs = (call.argument<Number>("endMs")
                    ?: System.currentTimeMillis()).toLong()
                result.success(queryUsageSummaries(startMs, endMs))
            }
            "queryUsageEvents" -> {
                val startMs = (call.argument<Number>("startMs") ?: 0L).toLong()
                val endMs = (call.argument<Number>("endMs")
                    ?: System.currentTimeMillis()).toLong()
                result.success(queryUsageEvents(startMs, endMs))
            }
            else -> result.notImplemented()
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = appContext.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            appContext.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun queryUsageSummaries(startMs: Long, endMs: Long): List<Map<String, Any?>> {
        if (!hasUsageStatsPermission()) return emptyList()
        if (startMs >= endMs) return emptyList()

        val usageStatsManager =
            appContext.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val packageManager = appContext.packageManager
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, startMs, endMs
        )

        return stats
            .asSequence()
            .filter { it.totalTimeInForeground > 0L }
            .map { stat ->
                val label = runCatching {
                    val info = packageManager.getApplicationInfo(stat.packageName, 0)
                    packageManager.getApplicationLabel(info).toString()
                }.getOrDefault(stat.packageName)

                mapOf(
                    "packageName" to stat.packageName,
                    "appName" to label,
                    "windowStartMs" to startMs,
                    "windowEndMs" to endMs,
                    "foregroundTimeMs" to stat.totalTimeInForeground,
                    "lastUsedMs" to stat.lastTimeUsed,
                )
            }
            .toList()
    }

    private fun queryUsageEvents(startMs: Long, endMs: Long): List<Map<String, Any?>> {
        if (!hasUsageStatsPermission()) return emptyList()
        if (startMs >= endMs) return emptyList()

        val usageStatsManager =
            appContext.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val usageEvents = usageStatsManager.queryEvents(startMs, endMs)
        val event = UsageEvents.Event()
        val records = mutableListOf<Map<String, Any?>>()

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            val normalizedType = normalizeEventType(event.eventType) ?: continue
            val packageName = event.packageName?.takeIf { it.isNotBlank() }
            val className = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                event.className?.takeIf { it.isNotBlank() }
            } else {
                null
            }
            val timeStamp = event.timeStamp
            val recordKey = listOf(
                normalizedType,
                timeStamp.toString(),
                packageName ?: "",
                className ?: "",
            ).joinToString(":")

            records += mapOf(
                "recordKey" to recordKey,
                "eventType" to normalizedType,
                "packageName" to packageName,
                "className" to className,
                "occurredAtMs" to timeStamp,
                "source" to "android_usage_events",
                "metadata" to null,
            )
        }

        return records
    }

    private fun normalizeEventType(eventType: Int): String? {
        return when (eventType) {
            UsageEvents.Event.ACTIVITY_RESUMED -> "ACTIVITY_RESUMED"
            UsageEvents.Event.ACTIVITY_PAUSED -> "ACTIVITY_PAUSED"
            UsageEvents.Event.MOVE_TO_FOREGROUND -> "MOVE_TO_FOREGROUND"
            UsageEvents.Event.MOVE_TO_BACKGROUND -> "MOVE_TO_BACKGROUND"
            UsageEvents.Event.SCREEN_INTERACTIVE -> "SCREEN_INTERACTIVE"
            UsageEvents.Event.SCREEN_NON_INTERACTIVE -> "SCREEN_NON_INTERACTIVE"
            UsageEvents.Event.KEYGUARD_SHOWN -> "KEYGUARD_SHOWN"
            UsageEvents.Event.KEYGUARD_HIDDEN -> "KEYGUARD_HIDDEN"
            else -> null
        }
    }
}

