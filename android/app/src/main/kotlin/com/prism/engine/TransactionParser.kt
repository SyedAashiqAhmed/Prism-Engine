package com.prism.engine

import java.util.Locale

internal data class ParsedTransaction(
    val type: String,
    val amount: Double,
    val merchant: String?,
    val accountLast4: String?,
    val upiReference: String?,
)

internal object TransactionParser {
    private val balancePattern = Regex(
        """\b(?:avl\.?\s*(?:bal(?:ance)?|limit|credit)|available\s+(?:balance|limit|credit)|current\s+balance|closing\s+balance|a/c\s*bal(?:ance)?|avbl|balance|bal)\b\s*:?\s*(?:rs\.?|inr|₹)?\s*[\d,]+(?:\.\d{1,2})?""",
        RegexOption.IGNORE_CASE,
    )
    private val debitKeywords =
        """debit(?:ed)?|deducted|withdrawn|withdrawal|spent|paid|payment|purchase|sent|transfer(?:red)?|charged"""
    private val creditKeywords =
        """credit(?:ed)?(?!\s+card)|received|deposited|refund(?:ed)?|reversed?|added"""
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
    private val accountPattern = Regex(
        """(?:a/c|acct|account|card|ending)\s*(?:no\.?)?\s*[*xX]*(\d{4})""",
        RegexOption.IGNORE_CASE,
    )
    private val referencePattern = Regex(
        """(?:upi\s*(?:transaction\s*)?(?:reference|ref)|transaction\s*(?:reference|ref)|\brrn\b|\bref\b)\s*(?:no\.?|number|id)?\s*[:#.\-]?\s*(\d{8,20})\b""",
        RegexOption.IGNORE_CASE,
    )
    private val promotionalPattern = Regex(
        """\b(?:shop|offer|win|collect|diwali|sale|discount|assured cashback|up to|campaign|reward)\b""",
        RegexOption.IGNORE_CASE,
    )

    fun parse(title: String, body: String): ParsedTransaction? {
        val cleanBody = balancePattern.replace(body, " ")
        val cleanTitle = balancePattern.replace(title, " ")
        val text = listOf(cleanBody, cleanTitle).filter { it.isNotBlank() }.joinToString(" ")
        if (promotionalPattern.containsMatchIn(text) &&
            !Regex("""\b(?:debited|credited|sent|received|paid|transferred|withdrawn)\b""", RegexOption.IGNORE_CASE)
                .containsMatchIn(text)
        ) {
            return null
        }
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
        val merchant = merchantPattern.find(text)?.groupValues?.getOrNull(1)?.trim()
        val accountLast4 = accountPattern.find(text)?.groupValues?.getOrNull(1)
        val upiReference = referencePattern.find(text)?.groupValues?.getOrNull(1)
        return selected.copy(
            merchant = merchant?.takeIf { it.isNotBlank() },
            accountLast4 = accountLast4,
            upiReference = upiReference,
        )
    }

    private fun parseMatch(
        amountText: String,
        keyword: String,
        position: Int,
    ): Pair<Int, ParsedTransaction>? {
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
            accountLast4 = null,
            upiReference = null,
        )
    }
}
