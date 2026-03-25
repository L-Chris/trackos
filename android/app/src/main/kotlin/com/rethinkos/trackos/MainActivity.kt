package com.rethinkos.trackos

import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val usageChannelName = "com.rethinkos.trackos/usage"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createForegroundNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureUsageChannel(flutterEngine)
    }

    private fun createForegroundNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "trackos_location",
                "TrackOS Location Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "前台定位追踪服务通知"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun configureUsageChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, usageChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsageStatsPermission" -> result.success(hasUsageStatsPermission())
                    "openUsageAccessSettings" -> {
                        openUsageAccessSettings()
                        result.success(null)
                    }
                    "queryUsageSummaries" -> result.success(queryUsageSummaries(call))
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName,
        )

        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageAccessSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun queryUsageSummaries(call: MethodCall): List<Map<String, Any?>> {
        if (!hasUsageStatsPermission()) {
            return emptyList()
        }

        val startMs = (call.argument<Number>("startMs") ?: 0L).toLong()
        val endMs = (call.argument<Number>("endMs") ?: System.currentTimeMillis()).toLong()
        if (startMs >= endMs) {
            return emptyList()
        }

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val packageManager = applicationContext.packageManager
        val stats = usageStatsManager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startMs, endMs)

        return stats
            .asSequence()
            .filter { it.totalTimeInForeground > 0L }
            .map { usageStat ->
                val label = runCatching {
                    val appInfo = packageManager.getApplicationInfo(usageStat.packageName, 0)
                    packageManager.getApplicationLabel(appInfo).toString()
                }.getOrDefault(usageStat.packageName)

                mapOf(
                    "packageName" to usageStat.packageName,
                    "appName" to label,
                    "windowStartMs" to startMs,
                    "windowEndMs" to endMs,
                    "foregroundTimeMs" to usageStat.totalTimeInForeground,
                    "lastUsedMs" to usageStat.lastTimeUsed,
                )
            }
            .toList()
    }
}
