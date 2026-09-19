import '../../../core/database/database_helper.dart';

/// Service responsible for multi-channel deduplication and transaction reconciliation.
/// Prevents duplicate counting when both a UPI app push notification (e.g. GPay/PhonePe)
/// and a bank SMS arrive for the same transaction within a 10-minute sliding window.
class DedupService {
  static const int defaultWindowMs = 10 * 60 * 1000; // 10 minutes

  /// Returns true if this event is a duplicate of a transaction in the sliding window.
  /// If it is a duplicate, enriches the existing record with merchant info if previously missing.
  static Future<bool> isDuplicateAndReconcile({
    required double amount,
    required String type,
    required int timestamp,
    String? merchant,
    String category = 'Bank',
    int windowMs = defaultWindowMs,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final existing = await db.query(
      'notifications',
      where: 'category = ? AND txn_type = ? AND amount = ? AND timestamp BETWEEN ? AND ?',
      whereArgs: [
        category,
        type,
        amount,
        timestamp - windowMs,
        timestamp + windowMs,
      ],
    );

    if (existing.isNotEmpty) {
      // Duplicate detected!
      final firstMatch = existing.first;
      final existingId = firstMatch['id'] as int?;
      final existingMerchant = firstMatch['merchant'] as String?;

      // If existing record was missing merchant name and new one has it, reconcile and enrich it!
      if (existingId != null &&
          merchant != null &&
          merchant.isNotEmpty &&
          (existingMerchant == null || existingMerchant.isEmpty)) {
        await db.update(
          'notifications',
          {'merchant': merchant},
          where: 'id = ?',
          whereArgs: [existingId],
        );
      }

      return true; // Dropped duplicate
    }

    return false; // Unique new transaction
  }
}
