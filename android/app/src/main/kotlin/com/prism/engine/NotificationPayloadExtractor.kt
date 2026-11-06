package com.prism.engine

import android.app.Notification
import android.os.Bundle

internal data class ExtractedNotification(
    val title: String,
    val body: String,
)

internal object NotificationPayloadExtractor {
    fun extract(extras: Bundle): ExtractedNotification {
        return extract(
            title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty(),
            bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
                ?.map { it?.toString() }
                ?: emptyList(),
        )
    }

    fun extract(
        title: String,
        bigText: String?,
        text: String?,
        lines: List<String?>,
    ): ExtractedNotification {
        val bodyParts = buildList {
            val primaryText = bigText?.takeIf { it.isNotBlank() }
                ?: text?.takeIf { it.isNotBlank() }
            if (primaryText != null) add(primaryText)
            lines.forEach { line ->
                if (!line.isNullOrBlank() && line !in this) add(line)
            }
        }
        return ExtractedNotification(title, bodyParts.joinToString("\n"))
    }
}
