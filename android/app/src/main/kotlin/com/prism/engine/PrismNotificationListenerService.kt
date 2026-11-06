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
        val extracted = NotificationPayloadExtractor.extract(sbn.notification.extras)
        val title = extracted.title
        val body = extracted.body
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

    private class TransactionStore(private val appContext: Context) :
        SQLiteOpenHelper(appContext, DATABASE_NAME, null, DATABASE_VERSION) {

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
                    classification_confidence REAL,
                    account_last4 TEXT,
                    title_encrypted TEXT,
                    text_encrypted TEXT,
                    upi_reference TEXT
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
            ensureColumns(db)
        }

        override fun onOpen(db: SQLiteDatabase) {
            super.onOpen(db)
            ensureColumns(db)
            encryptLegacyPayloads(db)
            purgeExpired(db)
        }

        private fun ensureColumns(db: SQLiteDatabase) {
            val existing = mutableSetOf<String>()
            db.rawQuery("PRAGMA table_info(notifications)", null).use { cursor ->
                val nameColumn = cursor.getColumnIndex("name")
                while (cursor.moveToNext()) existing += cursor.getString(nameColumn)
            }
            NotificationDatabaseSchema.missingColumns(existing).forEach { definition ->
                val name = definition.substringBefore(' ')
                if (name !in existing) {
                    db.execSQL("ALTER TABLE notifications ADD COLUMN $definition")
                }
            }
        }

        private fun encryptLegacyPayloads(db: SQLiteDatabase) {
            val payloads = EncryptedNotificationPayload(appContext)
            db.beginTransaction()
            try {
                db.rawQuery(
                    """
                    SELECT id, title, text, title_encrypted, text_encrypted
                    FROM notifications
                    WHERE title = ? OR text = ?
                    """.trimIndent(),
                    arrayOf(PROTECTED_TITLE, PROTECTED_TEXT),
                ).use { cursor ->
                    while (cursor.moveToNext()) {
                        val id = cursor.getLong(0)
                        val title = cursor.getString(1)
                        val text = cursor.getString(2)
                        val encryptedTitle = cursor.getString(3)
                        val encryptedText = cursor.getString(4)
                        db.execSQL(
                            """
                            UPDATE notifications
                            SET title = ?, text = ?
                            WHERE id = ?
                            """.trimIndent(),
                            arrayOf<Any?>(
                                payloads.decrypt(encryptedTitle) ?: title,
                                payloads.decrypt(encryptedText) ?: text,
                                id,
                            ),
                        )
                    }
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        }

        private fun purgeExpired(db: SQLiteDatabase) {
            db.delete(
                "notifications",
                "timestamp < ?",
                arrayOf(NotificationRetention.cutoff(System.currentTimeMillis()).toString()),
            )
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
            if (transaction == null) {
                categories.removeAll { it.id == BANKING_CATEGORY_ID }
            }
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
                val referenceDuplicate = transaction?.upiReference?.let { reference ->
                    database.rawQuery(
                        "SELECT id, merchant, account_last4 FROM notifications WHERE upi_reference = ? LIMIT 1",
                        arrayOf(reference),
                    ).use { cursor ->
                        if (!cursor.moveToFirst()) {
                            null
                        } else {
                            val duplicateId = cursor.getLong(0)
                            database.execSQL(
                                """
                                UPDATE notifications
                                SET merchant = COALESCE(NULLIF(merchant, ''), ?),
                                    account_last4 = COALESCE(NULLIF(account_last4, ''), ?)
                                WHERE id = ?
                                """.trimIndent(),
                                arrayOf<Any?>(
                                    transaction.merchant,
                                    transaction.accountLast4,
                                    duplicateId,
                                ),
                            )
                            duplicateId
                        }
                    }
                }
                if (referenceDuplicate != null) {
                    database.setTransactionSuccessful()
                    return false
                }
                val duplicate = database.rawQuery(
                    """
                    SELECT id, merchant, account_last4 FROM notifications
                    WHERE category IN (?, ?) AND txn_type = ? AND amount = ?
                      AND timestamp BETWEEN ? AND ?
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
                    if (transaction != null) {
                        val duplicateId = NotificationDeduplicator.findDuplicate(
                            cursor,
                            transaction.merchant,
                            transaction.accountLast4,
                        )
                        if (duplicateId != null) {
                            database.execSQL(
                                """
                                UPDATE notifications
                                SET merchant = COALESCE(NULLIF(merchant, ''), ?),
                                    account_last4 = COALESCE(NULLIF(account_last4, ''), ?)
                                WHERE id = ?
                                """.trimIndent(),
                                arrayOf<Any?>(
                                    transaction.merchant,
                                    transaction.accountLast4,
                                    duplicateId,
                                ),
                            )
                            true
                        } else {
                            false
                        }
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
                val payloads = EncryptedNotificationPayload(appContext)
                database.execSQL(
                    """
                    INSERT OR IGNORE INTO notifications
                    (source_key, package_name, sender_header, title, text, timestamp,
                     category, merchant, amount, txn_type, is_priority,
                     account_last4, title_encrypted, text_encrypted,
                     upi_reference,
                     category_labels, classification_scores, classification_version,
                     classification_confidence)
                    VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        transaction?.accountLast4,
                        payloads.encrypt(title),
                        payloads.encrypt(body),
                        transaction?.upiReference,
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
            private const val DATABASE_VERSION = 4
            private const val LEGACY_BANK_CATEGORY = "Bank"
            private const val BANKING_CATEGORY_NAME = "Banking & Payments"
            private const val DEDUP_WINDOW_MS = 10 * 60 * 1000L
            private const val PROTECTED_TITLE = "Protected notification"
            private const val PROTECTED_TEXT = "Protected notification content"
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
