import '../database_helper.dart';

/// Deterministic SQL financial query engine for Prism Engine.
/// All math is done in SQLite – zero LLM hallucination, sub-millisecond results.
class FinancialQueries {
  /// Returns the total DEBIT spend in a given timestamp range.
  static Future<double> getDebitInRange({
    required int startTimestamp,
    required int endTimestamp,
    String? category,
  }) async {
    final db = await DatabaseHelper.instance.database;
    String sql =
        'SELECT SUM(amount) as total FROM notifications WHERE txn_type = "DEBIT" AND timestamp BETWEEN ? AND ?';
    List<dynamic> args = [startTimestamp, endTimestamp];

    if (category != null && category != 'All') {
      sql += ' AND category = ?';
      args.add(category);
    }

    final res = await db.rawQuery(sql, args);
    return (res.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Returns the total CREDIT amount received in a given timestamp range.
  static Future<double> getCreditInRange({
    required int startTimestamp,
    required int endTimestamp,
    String? category,
  }) async {
    final db = await DatabaseHelper.instance.database;
    String sql =
        'SELECT SUM(amount) as total FROM notifications WHERE txn_type = "CREDIT" AND timestamp BETWEEN ? AND ?';
    List<dynamic> args = [startTimestamp, endTimestamp];

    if (category != null && category != 'All') {
      sql += ' AND category = ?';
      args.add(category);
    }

    final res = await db.rawQuery(sql, args);
    return (res.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Returns the day-by-day spending totals for the current month (for chart).
  static Future<Map<int, double>> getDailySpend({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.rawQuery('''
      SELECT 
        CAST(strftime('%d', datetime(timestamp / 1000, 'unixepoch', 'localtime')) AS INTEGER) as day,
        SUM(amount) as total 
      FROM notifications 
      WHERE txn_type = "DEBIT" AND timestamp BETWEEN ? AND ?
      GROUP BY day
      ORDER BY day
    ''', [startTimestamp, endTimestamp]);

    final Map<int, double> map = {};
    for (final row in res) {
      map[row['day'] as int] = (row['total'] as num?)?.toDouble() ?? 0.0;
    }
    return map;
  }

  /// Category breakdown for pie/bar chart.
  static Future<Map<String, double>> getCategoryBreakdown(
      int startTimestamp, int endTimestamp) async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.rawQuery('''
      SELECT category, SUM(amount) as total 
      FROM notifications 
      WHERE txn_type = "DEBIT" AND timestamp BETWEEN ? AND ?
      GROUP BY category
      ORDER BY total DESC
    ''', [startTimestamp, endTimestamp]);

    final Map<String, double> map = {};
    for (final row in res) {
      map[row['category'] as String] = (row['total'] as num?)?.toDouble() ?? 0.0;
    }
    return map;
  }

  /// Fetches the most recent bank transactions.
  static Future<List<Map<String, dynamic>>> getRecentTransactions({
    int limit = 30,
    String? type, // 'DEBIT', 'CREDIT', or null for all
  }) async {
    final db = await DatabaseHelper.instance.database;
    String where = 'amount IS NOT NULL AND txn_type IS NOT NULL';
    List<dynamic> whereArgs = [];

    if (type != null) {
      where += ' AND txn_type = ?';
      whereArgs.add(type);
    }

    return await db.query(
      'notifications',
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }
}
