package com.prism.engine

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class NotificationClassifierTest {
    private lateinit var classifier: NotificationClassifier

    @Before
    fun setUp() {
        val config = File("src/main/assets/notification_categories.json").readText()
        classifier = NotificationClassifier.fromJson(config)
    }

    @Test
    fun classifiesPlacementContentWithoutGroupName() {
        val result = classifier.classify(
            "Campus recruitment drive for software engineers. Eligible students apply by Friday.",
        )

        assertTrue(
            "Expected a placement label; scores=${result.scores}",
            result.labels.any { it.id == "placement_jobs" },
        )
    }

    @Test
    fun groupNameCannotTurnGreetingIntoPlacementAlert() {
        val result = classifier.classify("Good morning everyone, have a nice day.")
        val unrelatedMessage = classifier.classify(
            "The placement group should meet for lunch today.",
        )

        assertFalse(result.labels.any { it.id == "placement_jobs" })
        assertFalse(unrelatedMessage.labels.any { it.id == "placement_jobs" })
        assertEquals("Unclassified", result.primaryCategory)
    }

    @Test
    fun detectsRelevantContentRegardlessOfSource() {
        val hiringUpdates = listOf(
            "Your interview for the analyst role is scheduled for Monday at 10 AM.",
            "You have been selected for the next round of the selection process.",
            "Congratulations, you have progressed to the next stage of our hiring process.",
            "Your application has been selected for the second round of interviews.",
            "You are shortlisted for further consideration for the open position.",
            "Recruitment update: selected candidates will receive an assessment invitation.",
            "We are pleased to invite you to interview for the software engineer position.",
        )

        hiringUpdates.forEach { message ->
            val result = classifier.classify(message)
            assertTrue(
                "Expected a placement label for '$message'; scores=${result.scores}",
                result.labels.any { it.id == "placement_jobs" },
            )
        }
    }

    @Test
    fun nextRoundWithoutHiringIntentDoesNotQualifyAsPlacement() {
        val unrelatedMessages = listOf(
            "Our team qualified for the next round of the football tournament.",
            "The next round of the quiz competition starts at 4 PM.",
            "The student council selection process begins next week.",
        )

        unrelatedMessages.forEach { message ->
            val result = classifier.classify(message)
            assertFalse(
                "Unexpected placement label for '$message'; scores=${result.scores}",
                result.labels.any { it.id == "placement_jobs" },
            )
        }
    }

    @Test
    fun independentlyAppliesThresholdsForMultipleCategories() {
        val billReminder = classifier.classify(
            "Your electricity bill payment of Rs 1200 is due Friday.",
        )
        val paidBill = classifier.classify(
            "Payment received for your electricity bill.",
        )

        assertTrue(billReminder.labels.any { it.id == "bills_due_dates" })
        assertTrue(paidBill.labels.any { it.id == "bills_due_dates" })
        assertTrue(paidBill.labels.any { it.id == "banking_payments" })
    }

    @Test
    fun rejectsGenericPromotionalMessage() {
        val result = classifier.classify(
            "Special shopping sale, buy now and get a discount on products.",
        )

        assertFalse(result.labels.any { it.id == "deliveries_orders" })
        assertEquals("Unclassified", result.primaryCategory)
    }

    @Test
    fun assignsTransactionContentToBankingCategory() {
        val result = classifier.classify(
            "Rs 500 has been debited from your bank account for a UPI payment.",
        )

        assertTrue(result.labels.any { it.id == "banking_payments" })
    }

    @Test
    fun classifiesDeliveryTravelAndAppointmentExamples() {
        assertTrue(
            classifier.classify("Your package has been dispatched and is out for delivery today.")
                .labels.any { it.id == "deliveries_orders" },
        )
        assertTrue(
            classifier.classify("Your train ticket booking is confirmed for tomorrow.")
                .labels.any { it.id == "travel_transport" },
        )
        assertTrue(
            classifier.classify("Your doctor appointment is scheduled for Tuesday at 3 PM.")
                .labels.any { it.id == "appointments_reminders" },
        )
    }

    @Test
    fun classifierScoresAreVersionedAndBounded() {
        val result = classifier.classify("Your package has been dispatched and is out for delivery today.")

        assertEquals("notification-pilot-v2", result.modelVersion)
        assertTrue(result.scores.values.all { it in 0.0..1.0 })
    }
}
