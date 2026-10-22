import 'dart:convert';

import '../database_helper.dart';

class NotificationCategoryQueries {
  static Future<Map<String, int>> getCategoryCounts(
    List<String> categories,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT category, category_labels, COUNT(*) AS notification_count
      FROM notifications
      GROUP BY category, category_labels
      ''');
    final counts = {for (final category in categories) category: 0};

    for (final row in rows) {
      final category = row['category'] as String? ?? '';
      final labels = _decodeLabels(row['category_labels'] as String?);
      final notificationCount = row['notification_count'] as int;
      if (labels.isEmpty) {
        if (counts.containsKey(category)) {
          counts[category] = counts[category]! + notificationCount;
        } else if (category == 'Bank' &&
            counts.containsKey('Banking & Payments')) {
          counts['Banking & Payments'] =
              counts['Banking & Payments']! + notificationCount;
        }
        continue;
      }

      for (final label in labels) {
        if (counts.containsKey(label)) {
          counts[label] = counts[label]! + notificationCount;
        }
      }
    }
    return counts;
  }

  static Future<List<Map<String, dynamic>>> getNotificationsForCategory(
    String category, {
    int limit = 200,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final legacyBankMatch = category == 'Banking & Payments'
        ? ' OR category = ?'
        : '';
    final where = 'category_labels LIKE ? OR category = ?$legacyBankMatch';
    final whereArgs = <Object?>['%"$category"%', category];
    if (legacyBankMatch.isNotEmpty) whereArgs.add('Bank');

    return db.query(
      'notifications',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  static List<String> decodeLabels(String? value) => _decodeLabels(value);

  static List<String> _decodeLabels(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } on FormatException {
      return const [];
    }
    return const [];
  }
}
