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
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale

class PrismNotificationListenerService : NotificationListenerService() {
    private lateinit var transactionStore: TransactionStore
    private lateinit var classifier: NotificationClassifier

    override fun onCreate() {
        super.onCreate()
        classifier = assets.open(CATEGORY_CONFIG_ASSET).bufferedReader().use {
            NotificationClassifier.fromJson(it.readText())
        }
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
        if (sbn.packageName == packageName ||
            sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0 ||
            sbn.notification.flags and Notification.FLAG_ONGOING_EVENT != 0
        ) {
            return
        }
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val bodyParts = buildList {
            val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            val primaryText = bigText?.takeIf { it.isNotBlank() }
                ?: text?.takeIf { it.isNotBlank() }
            if (primaryText != null) add(primaryText)
            val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            lines?.forEach { line ->
                if (!line.isNullOrBlank() && line.toString() !in this) add(line.toString())
            }
        }
        val body = bodyParts.joinToString("\n")
        if (title.isBlank() && body.isBlank()) return

        try {
            val saved = transactionStore.save(
                packageName = sbn.packageName,
                notificationKey = sbn.key,
                title = title,
                body = body,
                timestamp = sbn.postTime,
                classifier = classifier,
            )
            if (saved) {
                Log.i(TAG, "Captured notification from ${sbn.packageName}")
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
                    "Notification listener",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Prism Engine is listening")
            .setContentText("Notifications are classified and saved in the background.")
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
                    is_priority INTEGER DEFAULT 0,
                    category_labels TEXT NOT NULL DEFAULT '[]',
                    classification_scores TEXT NOT NULL DEFAULT '{}',
                    classification_version TEXT,
                    classification_confidence REAL
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

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            ensureClassificationColumns(db)
        }

        override fun onOpen(db: SQLiteDatabase) {
            super.onOpen(db)
            ensureClassificationColumns(db)
        }

        private fun ensureClassificationColumns(db: SQLiteDatabase) {
            val existing = mutableSetOf<String>()
            db.rawQuery("PRAGMA table_info(notifications)", null).use { cursor ->
                val nameColumn = cursor.getColumnIndex("name")
                while (cursor.moveToNext()) existing += cursor.getString(nameColumn)
            }
            val columns = listOf(
                "category_labels TEXT NOT NULL DEFAULT '[]'",
                "classification_scores TEXT NOT NULL DEFAULT '{}'",
                "classification_version TEXT",
                "classification_confidence REAL",
            )
            columns.forEach { definition ->
                val name = definition.substringBefore(' ')
                if (name !in existing) {
                    db.execSQL("ALTER TABLE notifications ADD COLUMN $definition")
                }
            }
        }

        fun save(
            packageName: String,
            notificationKey: String,
            title: String,
            body: String,
            timestamp: Long,
            classifier: NotificationClassifier,
        ): Boolean {
            val message = body
            val classification = classifier.classify(message)
            val transaction = TransactionParser.parse(title, body)
            val categories = classification.labels.toMutableList()
            if (transaction != null) {
                val bankingMatch = CategoryMatch(
                    id = BANKING_CATEGORY_ID,
                    name = BANKING_CATEGORY_NAME,
                    score = 1.0,
                    threshold = 1.0,
                )
                val bankingIndex = categories.indexOfFirst {
                    it.id == BANKING_CATEGORY_ID
                }
                if (bankingIndex < 0) {
                    categories += bankingMatch
                } else {
                    categories[bankingIndex] = bankingMatch
                }
            }
            categories.sortByDescending { it.score }
            val categoryLabels = JSONArray().apply {
                categories.forEach { put(it.name) }
            }.toString()
            val scores = JSONObject().apply {
                classification.scores.forEach { (id, score) -> put(id, score) }
                transaction?.let { put(BANKING_CATEGORY_ID, 1.0) }
            }.toString()
            val primaryCategory = categories.firstOrNull()?.name ?: UNCLASSIFIED_CATEGORY
            val database = writableDatabase
            database.beginTransaction()
            try {
                val duplicate = database.rawQuery(
                    """
                    SELECT id, merchant FROM notifications
                    WHERE category IN (?, ?) AND txn_type = ? AND amount = ?
                      AND timestamp BETWEEN ? AND ?
                    LIMIT 1
                    """.trimIndent(),
                    arrayOf(
                        LEGACY_BANK_CATEGORY,
                        BANKING_CATEGORY_NAME,
                        transaction?.type ?: "",
                        transaction?.amount?.toString() ?: "",
                        (timestamp - DEDUP_WINDOW_MS).toString(),
                        (timestamp + DEDUP_WINDOW_MS).toString(),
                    ),
                ).use { cursor ->
                    if (transaction != null && cursor.moveToFirst()) {
                        val existingMerchant = cursor.getString(1)
                        if (existingMerchant.isNullOrBlank() && !transaction.merchant.isNullOrBlank()) {
                            database.execSQL(
                                "UPDATE notifications SET merchant = ? WHERE id = ?",
                                arrayOf<Any?>(transaction.merchant, cursor.getLong(0)),
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

                val contentHash = MessageDigest.getInstance("SHA-256")
                    .digest(message.trim().lowercase(Locale.ROOT).toByteArray())
                    .joinToString("") { "%02x".format(it) }
                val sourceKey = "${packageName}_${notificationKey}_$contentHash"
                database.execSQL(
                    """
                    INSERT OR IGNORE INTO notifications
                    (source_key, package_name, sender_header, title, text, timestamp,
                     category, merchant, amount, txn_type, is_priority,
                     category_labels, classification_scores, classification_version,
                     classification_confidence)
                    VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)
                    """.trimIndent(),
                    arrayOf<Any?>(
                        sourceKey,
                        packageName,
                        title.ifBlank { null },
                        body,
                        timestamp,
                        primaryCategory,
                        transaction?.merchant,
                        transaction?.amount,
                        transaction?.type,
                        categoryLabels,
                        scores,
                        classification.modelVersion,
                        categories.firstOrNull()?.score,
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
            private const val DATABASE_VERSION = 2
            private const val LEGACY_BANK_CATEGORY = "Bank"
            private const val BANKING_CATEGORY_NAME = "Banking & Payments"
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
        private const val CATEGORY_CONFIG_ASSET = "notification_categories.json"
        private const val BANKING_CATEGORY_ID = "banking_payments"
        private const val BANKING_CATEGORY_NAME = "Banking & Payments"
        private const val LEGACY_BANK_CATEGORY = "Bank"
        private const val UNCLASSIFIED_CATEGORY = "Unclassified"
    }
}
