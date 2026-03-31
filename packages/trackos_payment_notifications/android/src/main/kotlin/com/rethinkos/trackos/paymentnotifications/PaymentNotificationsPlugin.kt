package com.rethinkos.trackos.paymentnotifications

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.text.TextUtils
import android.content.ContentValues
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

// ─── SQLite helper ──────────────────────────────────────────────────────────

private const val DB_NAME = "trackos_payment_notifications.db"
private const val DB_VERSION = 1
private const val TABLE = "payment_notifications"

class PaymentNotificationDbHelper(context: Context) :
    SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE (
                id                  INTEGER PRIMARY KEY AUTOINCREMENT,
                record_key          TEXT    NOT NULL,
                package_name        TEXT    NOT NULL,
                notification_key    TEXT    NOT NULL,
                posted_at_ms        INTEGER NOT NULL,
                received_at_ms      INTEGER NOT NULL,
                title               TEXT    NOT NULL,
                text                TEXT    NOT NULL,
                big_text            TEXT,
                ticker_text         TEXT,
                source_metadata     TEXT,
                synced              INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        db.execSQL("CREATE UNIQUE INDEX idx_pn_record_key ON $TABLE(record_key)")
        db.execSQL("CREATE INDEX idx_pn_sync ON $TABLE(synced, posted_at_ms)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // v1 only — no-op
    }
}

// ─── Notification Listener Service ──────────────────────────────────────────

private val PAYMENT_KEYWORDS = listOf(
    "收款", "付款", "支付", "转账", "到账", "交易", "红包", "退款", "成功"
)

class PaymentNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        if (sbn.packageName != "com.eg.android.AlipayGphone") return

        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString() ?: return
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        val bigText = extras.getCharSequence("android.bigText")?.toString()
        val ticker = sbn.notification?.tickerText?.toString()

        val combined = listOf(title, text, bigText, ticker).filterNotNull().joinToString(" ")
        if (PAYMENT_KEYWORDS.none { combined.contains(it) }) return

        val notificationKey = sbn.key ?: "${sbn.id}:${sbn.packageName}"
        val postedAt = sbn.postTime
        val recordKey = "${sbn.packageName}:$notificationKey:$postedAt"
        val receivedAt = System.currentTimeMillis()

        val db = PaymentNotificationDbHelper(applicationContext).writableDatabase
        val cv = ContentValues().apply {
            put("record_key", recordKey)
            put("package_name", sbn.packageName)
            put("notification_key", notificationKey)
            put("posted_at_ms", postedAt)
            put("received_at_ms", receivedAt)
            put("title", title)
            put("text", text)
            put("big_text", bigText)
            put("ticker_text", ticker)
            put("source_metadata", null as String?)
            put("synced", 0)
        }
        // Ignore duplicates via unique index
        db.insertWithOnConflict(TABLE, null, cv, SQLiteDatabase.CONFLICT_IGNORE)
        db.close()
    }
}

// ─── Flutter Plugin ──────────────────────────────────────────────────────────

class PaymentNotificationsPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(
            binding.binaryMessenger,
            "com.rethinkos.trackos/payment_notifications"
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
                val act = activity
                if (act != null) {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    act.startActivity(intent)
                }
                result.success(null)
            }
            "countPendingPaymentNotifications" -> result.success(countPending())
            "queryUnsyncedPaymentNotifications" -> {
                val limit = (call.argument<Number>("limit") ?: 200).toInt()
                result.success(queryUnsynced(limit))
            }
            "markPaymentNotificationsSynced" -> {
                @Suppress("UNCHECKED_CAST")
                val keys = call.argument<List<String>>("recordKeys") ?: emptyList()
                markSynced(keys)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun hasNotificationAccess(): Boolean {
        val flat = Settings.Secure.getString(
            appContext.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        val cn = ComponentName(
            appContext,
            PaymentNotificationListenerService::class.java
        ).flattenToString()
        return flat.split(":").any { it == cn }
    }

    private fun countPending(): Int {
        val db = PaymentNotificationDbHelper(appContext).readableDatabase
        val cursor = db.rawQuery("SELECT COUNT(*) FROM $TABLE WHERE synced = 0", null)
        val count = if (cursor.moveToFirst()) cursor.getInt(0) else 0
        cursor.close()
        db.close()
        return count
    }

    private fun queryUnsynced(limit: Int): List<Map<String, Any?>> {
        val db = PaymentNotificationDbHelper(appContext).readableDatabase
        val cursor = db.query(
            TABLE,
            null,
            "synced = 0",
            null,
            null,
            null,
            "posted_at_ms ASC",
            limit.toString()
        )
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
        cursor.close()
        db.close()
        return records
    }

    private fun markSynced(recordKeys: List<String>) {
        if (recordKeys.isEmpty()) return
        val db = PaymentNotificationDbHelper(appContext).writableDatabase
        val placeholders = recordKeys.joinToString(",") { "?" }
        db.execSQL(
            "UPDATE $TABLE SET synced = 1 WHERE record_key IN ($placeholders)",
            recordKeys.toTypedArray()
        )
        db.close()
    }
}
