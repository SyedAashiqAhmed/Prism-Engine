import 'dart:math' as math;

import '../database_helper.dart';

class AnalyticsCategory {
  final String name;
  final double amount;
  final int transactionCount;

  const AnalyticsCategory({
    required this.name,
    required this.amount,
    required this.transactionCount,
  });
}

class AnalyticsMerchant {
  final String name;
  final double amount;
  final int transactionCount;

  const AnalyticsMerchant({
    required this.name,
    required this.amount,
    required this.transactionCount,
  });
}

class AnalyticsMonth {
  final DateTime month;
  final double spent;
  final double received;

  const AnalyticsMonth({
    required this.month,
    required this.spent,
    required this.received,
  });
}

class AnalyticsSnapshot {
  final DateTime month;
  final double spent;
  final double received;
  final double unclassified;
  final List<AnalyticsCategory> categories;
  final List<AnalyticsMerchant> merchants;
  final Map<int, double> dailySpend;
  final List<AnalyticsMonth> monthlyTrend;

  const AnalyticsSnapshot({
    required this.month,
    required this.spent,
    required this.received,
    required this.unclassified,
    required this.categories,
    required this.merchants,
    required this.dailySpend,
    required this.monthlyTrend,
  });

  double get savings => received - spent;

  double get categorizedSpend => spent - unclassified;

  double get unclassifiedPercent =>
      spent == 0 ? 0 : (unclassified / spent) * 100;
}

class AnalyticsQueries {
  static Future<AnalyticsSnapshot> load(DateTime month) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final previousStart = DateTime(month.year, month.month - 5);
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'notifications',
      columns: [
        'amount',
        'txn_type',
        'timestamp',
        'merchant',
        'title',
        'text',
        'category',
      ],
      where: 'amount IS NOT NULL AND timestamp >= ? AND timestamp < ?',
      whereArgs: [
        previousStart.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
    );

    final currentRows = rows.where((row) {
      final timestamp = (row['timestamp'] as num?)?.toInt() ?? 0;
      return timestamp >= start.millisecondsSinceEpoch &&
          timestamp < end.millisecondsSinceEpoch;
    }).toList();

    final categoryTotals = <String, _MutableTotal>{};
    final merchantTotals = <String, _MutableTotal>{};
    final dailyTotals = <int, double>{};
    var spent = 0.0;
    var received = 0.0;
    var unclassified = 0.0;

    for (final row in currentRows) {
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final type = row['txn_type'] as String? ?? '';
      final timestamp = (row['timestamp'] as num?)?.toInt() ?? 0;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final isDebit = type == 'DEBIT';
      if (isDebit) {
        spent += amount;
        dailyTotals[date.day] = (dailyTotals[date.day] ?? 0) + amount;
      } else if (type == 'CREDIT') {
        received += amount;
      } else {
        continue;
      }

      if (!isDebit) continue;
      final category = SpendingCategoryClassifier.classify(row);
      final total = categoryTotals.putIfAbsent(category, () => _MutableTotal());
      total.amount += amount;
      total.count++;
      if (category == SpendingCategoryClassifier.unclassified) {
        unclassified += amount;
      }

      final merchant = _merchantName(row);
      if (merchant != null) {
        final merchantTotal = merchantTotals.putIfAbsent(
          merchant,
          () => _MutableTotal(),
        );
        merchantTotal.amount += amount;
        merchantTotal.count++;
      }
    }

    final trend = <AnalyticsMonth>[];
    for (var index = 5; index >= 0; index--) {
      final trendMonth = DateTime(month.year, month.month - index);
      final trendStart = trendMonth.millisecondsSinceEpoch;
      final trendEnd = DateTime(
        trendMonth.year,
        trendMonth.month + 1,
      ).millisecondsSinceEpoch;
      var trendSpent = 0.0;
      var trendReceived = 0.0;
      for (final row in rows) {
        final timestamp = (row['timestamp'] as num?)?.toInt() ?? 0;
        if (timestamp < trendStart || timestamp >= trendEnd) continue;
        final amount = (row['amount'] as num?)?.toDouble() ?? 0;
        if (row['txn_type'] == 'DEBIT') {
          trendSpent += amount;
        } else if (row['txn_type'] == 'CREDIT') {
          trendReceived += amount;
        }
      }
      trend.add(
        AnalyticsMonth(
          month: trendMonth,
          spent: trendSpent,
          received: trendReceived,
        ),
      );
    }

    final categories =
        categoryTotals.entries
            .map(
              (entry) => AnalyticsCategory(
                name: entry.key,
                amount: entry.value.amount,
                transactionCount: entry.value.count,
              ),
            )
            .where((category) => category.amount > 0)
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    final merchants =
        merchantTotals.entries
            .map(
              (entry) => AnalyticsMerchant(
                name: entry.key,
                amount: entry.value.amount,
                transactionCount: entry.value.count,
              ),
            )
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    return AnalyticsSnapshot(
      month: start,
      spent: spent,
      received: received,
      unclassified: unclassified,
      categories: categories,
      merchants: merchants.take(6).toList(),
      dailySpend: dailyTotals,
      monthlyTrend: trend,
    );
  }

  static String? _merchantName(Map<String, dynamic> row) {
    final raw = (row['merchant'] as String?)?.trim();
    if (raw != null && raw.isNotEmpty) return _titleCase(raw);
    final text = [
      row['title'] as String? ?? '',
      row['text'] as String? ?? '',
    ].join(' ').toLowerCase();
    for (final merchant in SpendingCategoryClassifier.merchantNames) {
      if (text.contains(merchant.toLowerCase())) return _titleCase(merchant);
    }
    return null;
  }

  static String _titleCase(String value) => value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

class SpendingCategoryClassifier {
  static const unclassified = 'Other';

  static const merchantNames = [
    'Swiggy',
    'Zomato',
    'Dominos',
    'Pizza Hut',
    'McDonalds',
    'KFC',
    'Starbucks',
    'Blinkit',
    'Zepto',
    'BigBasket',
    'Amazon',
    'Flipkart',
    'Myntra',
    'Meesho',
    'Ajio',
    'Netflix',
    'Spotify',
    'YouTube Premium',
    'Amazon Prime',
    'Hotstar',
    'Disney+',
    'Uber',
    'Ola',
    'Rapido',
    'BookMyShow',
    'Apollo',
    'Pharmacy',
  ];

  static String classify(Map<String, dynamic> row) {
    final text = [
      row['merchant'] as String? ?? '',
      row['title'] as String? ?? '',
      row['text'] as String? ?? '',
      row['category'] as String? ?? '',
    ].join(' ').toLowerCase();

    if (_matches(text, [
      'swiggy',
      'zomato',
      'domino',
      'pizza hut',
      'mcdonald',
      'kfc',
      'starbucks',
      'restaurant',
      'cafe',
      'food order',
      'food delivery',
      'dining',
    ])) {
      return 'Food & Dining';
    }
    if (_matches(text, [
      'blinkit',
      'zepto',
      'bigbasket',
      'instamart',
      'dmart',
      'grocery',
      'supermarket',
    ])) {
      return 'Groceries';
    }
    if (_matches(text, [
      'netflix',
      'spotify',
      'youtube premium',
      'amazon prime',
      'hotstar',
      'disney+',
      'subscription',
      'recurring payment',
      'auto debit',
      'mandate',
    ])) {
      return 'Subscriptions';
    }
    if (_matches(text, [
      'electricity',
      'water bill',
      'gas bill',
      'broadband',
      'wifi',
      'mobile recharge',
      'dth',
      'utility',
      'bill payment',
    ])) {
      return 'Bills & Utilities';
    }
    if (_matches(text, [
      'amazon',
      'flipkart',
      'myntra',
      'meesho',
      'ajio',
      'shopping',
      'clothing',
      'electronics',
      'purchase',
    ])) {
      return 'Shopping';
    }
    if (_matches(text, [
      'uber',
      'ola',
      'rapido',
      'metro',
      'bus',
      'train',
      'flight',
      'airline',
      'fuel',
      'petrol',
      'diesel',
      'parking',
      'toll',
      'cab',
    ])) {
      return 'Transport';
    }
    if (_matches(text, [
      'hospital',
      'clinic',
      'pharmacy',
      'medicine',
      'doctor',
      'apollo',
      'medical',
      'diagnostic',
      'lab test',
    ])) {
      return 'Healthcare';
    }
    if (_matches(text, [
      'bookmyshow',
      'movie',
      'cinema',
      'gaming',
      'playstation',
      'steam',
      'concert',
      'event',
    ])) {
      return 'Entertainment';
    }
    if (_matches(text, [
      'gym',
      'fitness',
      'salon',
      'barber',
      'spa',
      'wellness',
    ])) {
      return 'Personal Care';
    }
    if (_matches(text, [
      'emi',
      'loan',
      'credit card payment',
      'bank charge',
      'service charge',
      'processing fee',
      'investment',
      'mutual fund',
    ])) {
      return 'Financial';
    }
    return unclassified;
  }

  static bool _matches(String text, List<String> terms) =>
      terms.any(text.contains);
}

class _MutableTotal {
  double amount = 0;
  int count = 0;
}

double analyticsMax(double value, double fallback) => math.max(value, fallback);
