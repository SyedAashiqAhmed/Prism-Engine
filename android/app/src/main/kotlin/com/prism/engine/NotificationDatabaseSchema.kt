package com.prism.engine

internal object NotificationDatabaseSchema {
    val upgradeColumns = listOf(
        "category_labels TEXT NOT NULL DEFAULT '[]'",
        "classification_scores TEXT NOT NULL DEFAULT '{}'",
        "classification_version TEXT",
        "classification_confidence REAL",
        "account_last4 TEXT",
        "title_encrypted TEXT",
        "text_encrypted TEXT",
        "upi_reference TEXT",
    )

    fun missingColumns(existing: Set<String>): List<String> =
        upgradeColumns.filter { it.substringBefore(' ') !in existing }
}

internal object NotificationRetention {
    const val RETENTION_DAYS = 90L

    fun cutoff(nowMillis: Long): Long =
        nowMillis - RETENTION_DAYS * 24 * 60 * 60 * 1000
}
