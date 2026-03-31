package com.rethinkos.trackos.paymentnotifications

import android.app.Activity
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONObject

private const val DB_NAME = "trackos_payment_notifications.db"
private const val DB_VERSION = 1
private const val TABLE = "payment_notifications"
private const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"

class PaymentNotificationDbHelper(context: Context) :
    SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                record_key       TEXT    NOT NULL,
                package_name     TEXT    NOT NULL,
                notification_key TEXT    NOT NULL,
                posted_at_ms     INTEGER NOT NULL,
                received_at_ms   INTEGER NOT NULL,
                title            TEXT    NOT NULL,
                text             TEXT    NOT NULL,
                big_text         TEXT,
                ticker_text      TEXT,
                source_metadata  TEXT,
                synced           INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE UNIQUE INDEX idx_pn_record_key ON $TABLE(record_key)")
        db.execSQL("CREATE INDEX idx_pn_sync ON $TABLE(synced, posted_at_ms)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // v1 only
    }
}

private val PAYMENT_KEYWORDS = listOf(
    "收款", "付款", "支付", "转账", "到账", "交易", "红包", "退款", "成功",
)

class PaymentNotificationListenerService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        if (sbn.packageName != ALIPAY_PACKAGE) return

        val extras = sbn.notification?.extras ?: return
        val rawTitle = extras.getCharSequence("android.title")?.toString()?.trim().orEmpty()
        val rawText = extras.getCharSequence("android.text")?.toString()?.trim().orEmpty()
        val bigText = extras.getCharSequence("android.bigText")?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        val tickerText = sbn.notification?.tickerText?.toString()?.trim()?.takeIf { it.isNotEmpty() }

        val combinedText = listOf(rawTitle, rawText, bigText, tickerText)
            .filterNotNull()
            .filter { it.isNotBlank() }
            .joinToString(" ")
        if (combinedText.isBlank()) return
        if (PAYMENT_KEYWORDS.none { combinedText.contains(it) }) return

        val title = if (rawTitle.isNotBlank()) rawTitle else rawText.ifBlank { tickerText ?: bigText ?: return }
        val text = if (rawText.isNotBlank()) rawText else bigText ?: tickerText ?: title
        val notificationKey = sbn.key ?: "${sbn.id}:${sbn.packageName}"
        val postedAt = sbn.postTime
        val receivedAt = System.currentTimeMillis()
        val recordKey = "${sbn.packageName}:$notificationKey:$postedAt"
        val sourceMetadata = JSONObject()
            .put("id", sbn.id)
            .put("tag", sbn.tag)
            .put("isOngoing", sbn.isOngoing)
            .put("isClearable", sbn.isClearable)
            .put("postTime", sbn.postTime)
            .put("packageName", sbn.packageName)
            .toString()

        val db = PaymentNotificationDbHelper(applicationContext).writableDatabase
        try {
            val values = ContentValues().apply {
                put("record_key", recordKey)
                put("package_name", sbn.packageName)
                put("notification_key", notificationKey)
                put("posted_at_ms", postedAt)
                put("received_at_ms", receivedAt)
                put("title", title)
                put("text", text)
                put("big_text", bigText)
                put("ticker_text", tickerText)
                put("source_metadata", sourceMetadata)
                put("synced", 0)
            }
            db.insertWithOnConflict(TABLE, null, values, SQLiteDatabase.CONFLICT_IGNORE)
        } finally {
            db.close()
        }
    }
}

class PaymentNotificationsPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(
            binding.binaryMessenger,
            "com.rethinkos.trackos/payment_notifications",
        )
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

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

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "hasNotificationAccess" -> result.success(hasNotificationAccess())
            "openNotificationAccessSettings" -> {
                val targetActivity = activity
                if (targetActivity != null) {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    targetActivity.startActivity(intent)
                }
                result.success(null)
            }
            "countPendingPaymentNotifications" -> result.success(countRecords(onlyUnsynced = true))
            "countAllPaymentNotifications" -> result.success(countRecords(onlyUnsynced = false))
            "queryUnsyncedPaymentNotifications" -> {
                val limit = (call.argument<Number>("limit") ?: 200).toInt().coerceAtLeast(1)
                result.success(queryUnsynced(limit))
            }
            "markPaymentNotificationsSynced" -> {
                @Suppress("UNCHECKED_CAST")
                val recordKeys = call.argument<List<String>>("recordKeys") ?: emptyList()
                markSynced(recordKeys)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun hasNotificationAccess(): Boolean {
        val flat = Settings.Secure.getString(
            appContext.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val componentName = ComponentName(
            appContext,
            PaymentNotificationListenerService::class.java,
        ).flattenToString()
        return flat.split(':').any { it == componentName }
    }

    private fun countRecords(onlyUnsynced: Boolean): Int {
        val sql = if (onlyUnsynced) {
            "SELECT COUNT(*) FROM $TABLE WHERE synced = 0"
        } else {
            "SELECT COUNT(*) FROM $TABLE"
        }
        val db = PaymentNotificationDbHelper(appContext).readableDatabase
        try {
            db.rawQuery(sql, null).use { cursor ->
                return if (cursor.moveToFirst()) cursor.getInt(0) else 0
            }
        } finally {
            db.close()
        }
    }

    private fun queryUnsynced(limit: Int): List<Map<String, Any?>> {
        val db = PaymentNotificationDbHelper(appContext).readableDatabase
        try {
            db.query(
                TABLE,
                null,
                "synced = 0",
                null,
                null,
                null,
                "posted_at_ms ASC",
                limit.toString(),
            ).use { cursor ->
                val records = mutableListOf<Map<String, Any?>>()
                while (cursor.moveToNext()) {
                    records += mapOf(
                        "recordKey" to cursor.getString(cursor.getColumnIndexOrThrow("record_key")),
                        "packageName" to cursor.getString(cursor.getColumnIndexOrThrow("package_name")),
                        "notificationKey" to cursor.getString(cursor.getColumnIndexOrThrow("notification_key")),
                        "postedAtMs" to cursor.getLong(cursor.getColumnIndexOrThrow("posted_at_ms")),
                        "receivedAtMs" to cursor.getLong(cursor.getColumnIndexOrThrow("received_at_ms")),
                        "title" to cursor.getString(cursor.getColumnIndexOrThrow("title")),
                        "text" to cursor.getString(cursor.getColumnIndexOrThrow("text")),
                        "bigText" to cursor.getString(cursor.getColumnIndexOrThrow("big_text")),
                        "tickerText" to cursor.getString(cursor.getColumnIndexOrThrow("ticker_text")),
                        "sourceMetadata" to cursor.getString(cursor.getColumnIndexOrThrow("source_metadata")),
                    )
                }
                return records
            }
        } finally {
            db.close()
        }
    }

    private fun markSynced(recordKeys: List<String>) {
        if (recordKeys.isEmpty()) return
        val db = PaymentNotificationDbHelper(appContext).writableDatabase
        try {
            val placeholders = recordKeys.joinToString(",") { "?" }
            db.execSQL(
                "UPDATE $TABLE SET synced = 1 WHERE record_key IN ($placeholders)",
                recordKeys.toTypedArray(),
            )
        } finally {
            db.close()
        }
    }
}
