import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/queries/financial_queries.dart';
import '../../../core/database/database_helper.dart';

/// Immutable state object for the dashboard screen.
class DashboardState {
  final double monthlyDebits;
  final double monthlyCredits;
  final double todayDebits;
  final double todayCredits;
  final Map<String, double> categoryBreakdown;
  final Map<int, double> dailySpend;
  final List<Map<String, dynamic>> recentTransactions;
  final bool isLoading;
  final int transactionCount;
  final String? errorMessage;

  const DashboardState({
    this.monthlyDebits = 0,
    this.monthlyCredits = 0,
    this.todayDebits = 0,
    this.todayCredits = 0,
    this.categoryBreakdown = const {},
    this.dailySpend = const {},
    this.recentTransactions = const [],
    this.isLoading = true,
    this.transactionCount = 0,
    this.errorMessage,
  });

  DashboardState copyWith({
    double? monthlyDebits,
    double? monthlyCredits,
    double? todayDebits,
    double? todayCredits,
    Map<String, double>? categoryBreakdown,
    Map<int, double>? dailySpend,
    List<Map<String, dynamic>>? recentTransactions,
    bool? isLoading,
    int? transactionCount,
    String? errorMessage,
  }) {
    return DashboardState(
      monthlyDebits: monthlyDebits ?? this.monthlyDebits,
      monthlyCredits: monthlyCredits ?? this.monthlyCredits,
      todayDebits: todayDebits ?? this.todayDebits,
      todayCredits: todayCredits ?? this.todayCredits,
      categoryBreakdown: categoryBreakdown ?? this.categoryBreakdown,
      dailySpend: dailySpend ?? this.dailySpend,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      isLoading: isLoading ?? this.isLoading,
      transactionCount: transactionCount ?? this.transactionCount,
      errorMessage: errorMessage,
    );
  }
}

/// Riverpod StateNotifier that drives the dashboard with live SQLite data.
class DashboardNotifier extends StateNotifier<DashboardState> {
  DashboardNotifier() : super(const DashboardState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final now = DateTime.now();
    // Start of current month at midnight
    final monthStart =
        DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    // Start of today at midnight
    final todayStart =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    // Now (inclusive upper bound)
    final nowMs = now.millisecondsSinceEpoch;

    try {
      // Run all financial queries concurrently for performance.
      final results = await Future.wait([
        FinancialQueries.getDebitInRange(
          startTimestamp: monthStart,
          endTimestamp: nowMs,
        ),
        FinancialQueries.getCreditInRange(
          startTimestamp: monthStart,
          endTimestamp: nowMs,
        ),
        FinancialQueries.getDebitInRange(
          startTimestamp: todayStart,
          endTimestamp: nowMs,
        ),
        FinancialQueries.getCreditInRange(
          startTimestamp: todayStart,
          endTimestamp: nowMs,
        ),
      ]);

      final breakdown =
          await FinancialQueries.getCategoryBreakdown(monthStart, nowMs);
      final dailySpend = await FinancialQueries.getDailySpend(
        startTimestamp: monthStart,
        endTimestamp: nowMs,
      );
      final txns = await FinancialQueries.getRecentTransactions(limit: 50);

      // Count total transactions with a valid amount and type.
      final db = await DatabaseHelper.instance.database;
      final countRes = await db.rawQuery(
          'SELECT COUNT(*) as c FROM notifications WHERE amount IS NOT NULL AND txn_type IS NOT NULL');
      final count = (countRes.first['c'] as int?) ?? 0;

      state = DashboardState(
        monthlyDebits: results[0],
        monthlyCredits: results[1],
        todayDebits: results[2],
        todayCredits: results[3],
        categoryBreakdown: breakdown,
        dailySpend: dailySpend,
        recentTransactions: txns,
        isLoading: false,
        transactionCount: count,
        errorMessage: null,
      );
    } catch (e, stackTrace) {
      // Expose the error to the UI so the user can see what went wrong
      // instead of silently failing with stale/empty data.
      final msg = 'DB error: $e';
      // ignore: avoid_print
      print('[DashboardNotifier] $msg\n$stackTrace');
      state = state.copyWith(isLoading: false, errorMessage: msg);
    }
  }

  /// Called by the notification listener to trigger a real-time UI update.
  Future<void> refresh() => load();
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>(
        (ref) => DashboardNotifier());
