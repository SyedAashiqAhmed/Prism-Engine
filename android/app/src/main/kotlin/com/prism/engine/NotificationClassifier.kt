package com.prism.engine

import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import kotlin.math.ln
import kotlin.math.sqrt

internal data class NotificationCategory(
    val id: String,
    val name: String,
    val threshold: Double,
    val description: String,
    val positiveExamples: List<String>,
    val negativeExamples: List<String>,
)

internal data class CategoryMatch(
    val id: String,
    val name: String,
    val score: Double,
    val threshold: Double,
)

internal data class ClassificationResult(
    val labels: List<CategoryMatch>,
    val scores: Map<String, Double>,
    val modelVersion: String,
) {
    val primaryCategory: String
        get() = labels.firstOrNull()?.name ?: "Unclassified"

    val confidence: Double?
        get() = labels.firstOrNull()?.score
}

/**
 * On-device TF-IDF prototype baseline. It scores notification message content
 * only; app and conversation names are deliberately not classifier inputs.
 * Scores are similarity values, not calibrated probabilities.
 */
internal class NotificationClassifier private constructor(
    private val version: String,
    categoryDefinitions: List<NotificationCategory>,
) {
    private val documentCount: Int
    private val documentFrequency: Map<String, Int>
    private val categories: List<CategoryPrototype>

    init {
        val documents = categoryDefinitions.flatMap { category ->
            listOf(category.description) + category.positiveExamples + category.negativeExamples
        }
        documentCount = documents.size
        documentFrequency = documents
            .map { text -> features(text).toSet() }
            .flatMap { it }
            .groupingBy { it }
            .eachCount()
        categories = categoryDefinitions.map { category ->
            CategoryPrototype(
                category = category,
                positiveVectors =
                    (listOf(category.description) + category.positiveExamples).map(::vectorize),
                negativeVectors = category.negativeExamples.map(::vectorize),
            )
        }
    }

    fun classify(message: String): ClassificationResult {
        val messageVector = vectorize(message)
        if (messageVector.isEmpty()) {
            return ClassificationResult(emptyList(), emptyMap(), version)
        }

        val scores = categories.associate { prototype ->
            val positive = prototype.positiveVectors.maxOfOrNull {
                cosineSimilarity(messageVector, it)
            } ?: 0.0
            val negative = prototype.negativeVectors.maxOfOrNull {
                cosineSimilarity(messageVector, it)
            } ?: 0.0
            val score = (positive - NEGATIVE_SIMILARITY_WEIGHT * negative)
                .coerceIn(0.0, 1.0)
            prototype.category.id to score
        }

        val matches = categories.mapNotNull { prototype ->
            val score = scores.getValue(prototype.category.id)
            if (score < prototype.category.threshold) {
                null
            } else {
                CategoryMatch(
                    id = prototype.category.id,
                    name = prototype.category.name,
                    score = score,
                    threshold = prototype.category.threshold,
                )
            }
        }.sortedByDescending { it.score }

        return ClassificationResult(matches, scores, version)
    }

    private fun vectorize(text: String): Map<String, Double> {
        val counts = features(text).groupingBy { it }.eachCount()
            .mapValues { (term, count) ->
                count.toDouble() * if (' ' in term) BIGRAM_WEIGHT else 1.0
            }
        if (counts.isEmpty()) return emptyMap()

        val weighted = counts.mapValues { (term, count) ->
            val documentFrequency = documentFrequency[term] ?: 0
            val inverseDocumentFrequency =
                ln((documentCount + 1.0) / (documentFrequency + 1.0)) + 1.0
            count * inverseDocumentFrequency
        }
        val norm = sqrt(weighted.values.sumOf { it * it })
        if (norm == 0.0) return emptyMap()
        return weighted.mapValues { it.value / norm }
    }

    private fun features(text: String): List<String> {
        val words = TOKEN_PATTERN.findAll(text.lowercase(Locale.ROOT))
            .map { it.value }
            .filterNot { it in STOP_WORDS }
            .toList()
        return words + words.zipWithNext().map { (first, second) -> "$first $second" }
    }

    private fun cosineSimilarity(
        first: Map<String, Double>,
        second: Map<String, Double>,
    ): Double {
        if (first.isEmpty() || second.isEmpty()) return 0.0
        return first.entries.sumOf { (term, weight) ->
            weight * (second[term] ?: 0.0)
        }.coerceIn(0.0, 1.0)
    }

    private data class CategoryPrototype(
        val category: NotificationCategory,
        val positiveVectors: List<Map<String, Double>>,
        val negativeVectors: List<Map<String, Double>>,
    )

    companion object {
        private const val BIGRAM_WEIGHT = 1.25
        private const val NEGATIVE_SIMILARITY_WEIGHT = 0.6
        private val TOKEN_PATTERN = Regex("""[\p{L}\p{N}]+""")
        private val STOP_WORDS = setOf(
            "a", "an", "and", "are", "at", "be", "been", "by", "for", "from",
            "has", "have", "i", "in", "is", "it", "of", "on", "or", "our",
            "the", "their", "to", "was", "we", "your",
        )

        fun fromJson(json: String): NotificationClassifier {
            val root = JSONObject(json)
            val version = root.getString("version")
            val categoriesJson = root.getJSONArray("categories")
            require(categoriesJson.length() > 0) { "At least one category is required" }

            val categories = (0 until categoriesJson.length()).map { index ->
                val item = categoriesJson.getJSONObject(index)
                NotificationCategory(
                    id = item.getString("id"),
                    name = item.getString("name"),
                    threshold = item.getDouble("threshold").also {
                        require(it in 0.0..1.0) { "Category threshold must be between 0 and 1" }
                    },
                    description = item.getString("description"),
                    positiveExamples = item.getStringList("positiveExamples"),
                    negativeExamples = item.getStringList("negativeExamples"),
                ).also { category ->
                    require(category.positiveExamples.isNotEmpty()) {
                        "Category ${category.id} needs positive examples"
                    }
                    require(category.negativeExamples.isNotEmpty()) {
                        "Category ${category.id} needs negative examples"
                    }
                }
            }
            require(categories.map { it.id }.distinct().size == categories.size) {
                "Category IDs must be unique"
            }
            return NotificationClassifier(version, categories)
        }

        private fun JSONObject.getStringList(key: String): List<String> {
            val values = getJSONArray(key)
            return (0 until values.length()).map { values.getString(it) }
        }
    }
}
