package com.prism.engine

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.Locale

class PrismNotificationListenerService : NotificationListenerService() {
    private lateinit var transactionStore: TransactionStore

    override fun onCreate() {
        super.onCreate()
        transactionStore = TransactionStore(this)
        startListenerForeground()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "Notification listener connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.w(TAG, "Notification listener disconnected; requesting rebind")
        requestRebind(ComponentName(this, PrismNotificationListenerService::class.java))
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val body = buildString {
            append(extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty())
            if (isBlank()) {
                append(extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty())
            }
            val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            lines?.forEach { line ->
                if (!line.isNullOrBlank() && !contains(line)) {
                    if (isNotEmpty()) append('\n')
                    append(line)
                }
            }
        }
        if (title.isBlank() && body.isBlank()) return

        try {
            val saved = transactionStore.save(
                packageName = sbn.packageName,
                notificationKey = sbn.key,
                title = title,
                body = body,
                timestamp = sbn.postTime,
            )
            if (saved) {
                Log.i(TAG, "Captured ${sbn.packageName} transaction")
            }
        } catch (error: Exception) {
            Log.e(TAG, "Could not persist notification from ${sbn.packageName}", error)
        }
    }

    private fun startListenerForeground() {
        val channelId = "prism_notification_listener"
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Transaction listener",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Prism Engine is listening")
            .setContentText("Bank and payment notifications are processed in the background.")
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setShowWhen(false)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                FOREGROUND_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(FOREGROUND_NOTIFICATION_ID, notification)
        }
    }

    private class TransactionStore(context: Context) :
        SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS notifications (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_key TEXT UNIQUE,
                    package_name TEXT NOT NULL,
                    sender_header TEXT,
                    title TEXT,
                    text TEXT,
                    timestamp INTEGER NOT NULL,
                    category TEXT NOT NULL,
                    merchant TEXT,
                    amount REAL,
                    txn_type TEXT,
                    is_priority INTEGER DEFAULT 0
                )
                """.trimIndent(),
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_txn_category_time ON notifications (category, timestamp DESC)",
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_txn_amount_time ON notifications (amount, timestamp)",
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_txn_source_key ON notifications (source_key)",
            )
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

        fun save(
            packageName: String,
            notificationKey: String,
            title: String,
            body: String,
            timestamp: Long,
        ): Boolean {
            val parsed = TransactionParser.parse(title, body) ?: return false
            val database = writableDatabase
            database.beginTransaction()
            try {
                val duplicate = database.rawQuery(
                    """
                    SELECT id, merchant FROM notifications
                    WHERE category = ? AND txn_type = ? AND amount = ?
                      AND timestamp BETWEEN ? AND ?
                    LIMIT 1
                    """.trimIndent(),
                    arrayOf(
                        CATEGORY,
                        parsed.type,
                        parsed.amount.toString(),
                        (timestamp - DEDUP_WINDOW_MS).toString(),
                        (timestamp + DEDUP_WINDOW_MS).toString(),
                    ),
                ).use { cursor ->
                    if (cursor.moveToFirst()) {
                        val existingMerchant = cursor.getString(1)
                        if (existingMerchant.isNullOrBlank() && !parsed.merchant.isNullOrBlank()) {
                            database.execSQL(
                                "UPDATE notifications SET merchant = ? WHERE id = ?",
                                arrayOf(parsed.merchant, cursor.getLong(0)),
                            )
                        }
                        true
                    } else {
                        false
                    }
                }

                if (duplicate) {
                    database.setTransactionSuccessful()
                    return false
                }

                val sourceKey = "${packageName}_${notificationKey}_${timestamp}_${parsed.type}_${parsed.amount}"
                database.execSQL(
                    """
                    INSERT OR IGNORE INTO notifications
                    (source_key, package_name, sender_header, title, text, timestamp,
                     category, merchant, amount, txn_type, is_priority)
                    VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, 0)
                    """.trimIndent(),
                    arrayOf(
                        sourceKey,
                        packageName,
                        title.ifBlank { null },
                        body,
                        timestamp,
                        CATEGORY,
                        parsed.merchant,
                        parsed.amount,
                        parsed.type,
                    ),
                )
                database.setTransactionSuccessful()
                return true
            } finally {
                database.endTransaction()
            }
        }

        companion object {
            private const val DATABASE_NAME = "prism_engine.db"
            private const val DATABASE_VERSION = 1
            private const val CATEGORY = "Bank"
            private const val DEDUP_WINDOW_MS = 10 * 60 * 1000L
        }
    }

    private data class ParsedTransaction(
        val type: String,
        val amount: Double,
        val merchant: String?,
    )

    private object TransactionParser {
        private val balancePattern = Regex(
            """\b(?:avl\.?\s*(?:bal(?:ance)?|limit|credit)|available\s+(?:balance|limit|credit)|current\s+balance|closing\s+balance|a/c\s*bal(?:ance)?|avbl|balance|bal)\b\s*:?\s*(?:rs\.?|inr|₹)?\s*[\d,]+(?:\.\d{1,2})?""",
            RegexOption.IGNORE_CASE,
        )
        private val debitKeywords =
            """debit(?:ed)?|deducted|withdrawn|withdrawal|spent|paid|payment|purchase|sent|transfer(?:red)?|charged"""
        private val creditKeywords =
            """credit(?:ed)?(?!\s+card)|received|deposited|refund(?:ed)?|reversed?|added|cashback"""
        private val amountBeforeDirection = Regex(
            """(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)[^\n]{0,100}?\b($debitKeywords|$creditKeywords)\b""",
            RegexOption.IGNORE_CASE,
        )
        private val directionBeforeAmount = Regex(
            """\b($debitKeywords|$creditKeywords)\b[^\n]{0,80}?(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)""",
            RegexOption.IGNORE_CASE,
        )
        private val merchantPattern = Regex(
            """\b(?:to|at)\s+([A-Za-z][A-Za-z0-9 &._-]{1,30}?)(?=\s+(?:on|ref|upi|via|from)\b|[,.]|$)""",
            RegexOption.IGNORE_CASE,
        )

        fun parse(title: String, body: String): ParsedTransaction? {
            val cleanBody = balancePattern.replace(body, " ")
            val text = cleanBody.ifBlank { balancePattern.replace(title, " ") }
            val candidates = mutableListOf<Pair<Int, ParsedTransaction>>()

            amountBeforeDirection.findAll(text).forEach { match ->
                parseMatch(match.groupValues[1], match.groupValues[2], match.range.first)?.let {
                    candidates.add(it)
                }
            }
            directionBeforeAmount.findAll(text).forEach { match ->
                parseMatch(match.groupValues[2], match.groupValues[1], match.range.first)?.let {
                    candidates.add(it)
                }
            }

            val selected = candidates.minByOrNull { it.first }?.second ?: return null
            val merchant = merchantPattern.find(cleanBody)?.groupValues?.getOrNull(1)?.trim()
            return selected.copy(merchant = merchant?.takeIf { it.isNotBlank() })
        }

        private fun parseMatch(amountText: String, keyword: String, position: Int): Pair<Int, ParsedTransaction>? {
            val amount = amountText.replace(",", "").toDoubleOrNull() ?: return null
            if (amount <= 0.0) return null
            val normalized = keyword.lowercase(Locale.ROOT)
            val isCredit = normalized.startsWith("credit") ||
                normalized.startsWith("receiv") ||
                normalized.startsWith("deposit") ||
                normalized.startsWith("refund") ||
                normalized.startsWith("revers") ||
                normalized.startsWith("added") ||
                normalized.startsWith("cashback")
            return position to ParsedTransaction(
                type = if (isCredit) "CREDIT" else "DEBIT",
                amount = amount,
                merchant = null,
            )
        }
    }

    companion object {
        private const val TAG = "PrismNotificationListener"
        private const val FOREGROUND_NOTIFICATION_ID = 701
    }
}
