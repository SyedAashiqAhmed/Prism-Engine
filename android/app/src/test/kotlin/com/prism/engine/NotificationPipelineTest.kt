package com.prism.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationPipelineTest {
    @Test
    fun extractsBigTextBeforeTextAndAppendsUniqueLines() {
        val extracted = NotificationPayloadExtractor.extract(
            title = "Bank",
            bigText = "full",
            text = "short",
            lines = listOf("full", "line two"),
        )

        assertEquals("Bank", extracted.title)
        assertEquals("full\nline two", extracted.body)
    }

    @Test
    fun parserUsesTitleWhenBodyHasNoTransactionAndCapturesIdentity() {
        val parsed = TransactionParser.parse(
            "Paid Rs 500 to Zomato from card ending 4321",
            "Payment notification",
        )

        assertEquals("DEBIT", parsed?.type)
        assertEquals(500.0, parsed?.amount ?: 0.0, 0.0)
        assertEquals("Zomato", parsed?.merchant)
        assertEquals("4321", parsed?.accountLast4)
        assertNull(parsed?.upiReference)
    }

    @Test
    fun parserExtractsUpiReferenceFromBankFormats() {
        val parsed = TransactionParser.parse(
            "HDFC Bank",
            "Sent Rs.15.00 To BHARU CAFE. UPI transaction reference no.: 132423321351",
        )

        assertEquals("DEBIT", parsed?.type)
        assertEquals(15.0, parsed?.amount ?: 0.0, 0.0)
        assertEquals("132423321351", parsed?.upiReference)
        assertEquals("BHARU CAFE", parsed?.merchant)
    }

    @Test
    fun promotionalBankMessageIsIgnored() {
        assertNull(
            TransactionParser.parse(
                "HDFC Bank",
                "This Diwali, Shop, Collect & Win! Get assured cashback up to Rs.1,001",
            ),
        )
    }

    @Test
    fun sameAmountWithoutSharedIdentityIsNotDuplicate() {
        assertFalse(
            NotificationDeduplicator.hasMatchingIdentity(
                incomingMerchant = null,
                incomingAccount = null,
                existingMerchant = "Zomato",
                existingAccount = "4321",
            ),
        )
    }

    @Test
    fun matchingMerchantOrAccountIsDuplicate() {
        assertTrue(
            NotificationDeduplicator.hasMatchingIdentity(
                incomingMerchant = " ZOMATO ",
                incomingAccount = null,
                existingMerchant = "zomato",
                existingAccount = null,
            ),
        )
        assertTrue(
            NotificationDeduplicator.hasMatchingIdentity(
                incomingMerchant = null,
                incomingAccount = "4321",
                existingMerchant = null,
                existingAccount = "4321",
            ),
        )
    }

    @Test
    fun schemaMigrationAddsOnlyMissingColumns() {
        val missing = NotificationDatabaseSchema.missingColumns(
            setOf("category_labels", "classification_scores", "account_last4"),
        ).map { it.substringBefore(' ') }

        assertEquals(
            listOf(
                "classification_version",
                "classification_confidence",
                "title_encrypted",
                "text_encrypted",
                "upi_reference",
            ),
            missing,
        )
    }

    @Test
    fun retentionCutoffIsNinetyDays() {
        val now = 100L * 24 * 60 * 60 * 1000
        assertEquals(10L * 24 * 60 * 60 * 1000, NotificationRetention.cutoff(now))
    }
}
