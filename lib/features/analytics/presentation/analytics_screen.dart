import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/database/queries/analytics_queries.dart';
import '../../../core/theme/app_colors.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late DateTime _month;
  late Future<AnalyticsSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _snapshot = AnalyticsQueries.load(_month);
  }

  void _changeMonth(int offset) {
    setState(() {
      _month = DateTime(_month.year, _month.month + offset);
      _snapshot = AnalyticsQueries.load(_month);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            onPressed: () =>
                setState(() => _snapshot = AnalyticsQueries.load(_month)),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh analytics',
          ),
        ],
      ),
      body: FutureBuilder<AnalyticsSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load analytics.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.credit),
            );
          }
          return _AnalyticsBody(
            data: snapshot.data!,
            onPreviousMonth: () => _changeMonth(-1),
            onNextMonth: () => _changeMonth(1),
            onRefresh: () async {
              if (!mounted) return;
              setState(() => _snapshot = AnalyticsQueries.load(_month));
              await _snapshot;
            },
          );
        },
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  final AnalyticsSnapshot data;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final Future<void> Function() onRefresh;

  const _AnalyticsBody({
    required this.data,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    final monthLabel = DateFormat('MMM yyyy').format(data.month);
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.credit,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _MonthSelector(
            label: monthLabel,
            onPrevious: onPreviousMonth,
            onNext: onNextMonth,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Total Spent',
                  value: money.format(data.spent),
                  color: AppColors.debit,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: 'Received',
                  value: money.format(data.received),
                  color: AppColors.credit,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: 'Net Savings',
                  value: money.format(data.savings),
                  color: data.savings >= 0 ? AppColors.credit : AppColors.debit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Monthly Overview',
            subtitle: 'Expenses and income trend',
            child: SizedBox(height: 190, child: _MonthlyChart(data: data)),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Spending by Category',
            subtitle: data.unclassified > 0
                ? '${data.unclassifiedPercent.toStringAsFixed(0)}% remains unclassified'
                : 'All captured spending has a category',
            child: SizedBox(height: 230, child: _CategoryChart(data: data)),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Daily Spending',
            subtitle: 'Tap a day to compare your spending pattern',
            child: SizedBox(height: 185, child: _DailyChart(data: data)),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Top Merchants',
            subtitle: 'Highest spending merchants this month',
            child: _MerchantList(data: data, money: money),
          ),
          const SizedBox(height: 14),
          _InsightPanel(data: data, money: money),
        ],
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _MonthSelector({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Overview',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_month_rounded,
                size: 14,
                color: AppColors.credit,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  final AnalyticsSnapshot data;
  const _MonthlyChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxValue = data.monthlyTrend.fold<double>(
      0,
      (max, item) => item.spent > max ? item.spent : max,
    );
    final interval = maxValue <= 0 ? 1000.0 : maxValue / 3;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxValue <= 0 ? 3000 : maxValue * 1.25,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: interval,
              getTitlesWidget: (value, meta) => Text(
                _compact(value),
                style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.monthlyTrend.length) {
                  return const SizedBox.shrink();
                }
                return Text(
                  DateFormat('MMM').format(data.monthlyTrend[index].month),
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textMuted,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          _line(
            data.monthlyTrend
                .asMap()
                .entries
                .map((entry) => FlSpot(entry.key.toDouble(), entry.value.spent))
                .toList(),
            AppColors.debit,
          ),
          _line(
            data.monthlyTrend
                .asMap()
                .entries
                .map(
                  (entry) => FlSpot(entry.key.toDouble(), entry.value.received),
                )
                .toList(),
            AppColors.credit,
          ),
        ],
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) => LineChartBarData(
    spots: spots,
    isCurved: true,
    color: color,
    barWidth: 2.5,
    dotData: const FlDotData(show: false),
    belowBarData: BarAreaData(show: true, color: color.withAlpha(18)),
  );
}

class _CategoryChart extends StatelessWidget {
  final AnalyticsSnapshot data;
  const _CategoryChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.categories.isEmpty) {
      return const Center(
        child: Text(
          'No spending data for this month',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    final colors = [
      AppColors.debit,
      const Color(0xFFFFC43D),
      const Color(0xFF3B9CFF),
      AppColors.credit,
      AppColors.aiVioletLight,
      const Color(0xFFE879F9),
      AppColors.textMuted,
    ];
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 38,
              sections: data.categories.take(7).toList().asMap().entries.map((
                entry,
              ) {
                final item = entry.value;
                return PieChartSectionData(
                  value: item.amount,
                  color: colors[entry.key % colors.length],
                  radius: 30,
                  showTitle: false,
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 7,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: data.categories.take(7).toList().asMap().entries.map((
              entry,
            ) {
              final item = entry.value;
              final percent = data.spent == 0
                  ? 0
                  : item.amount / data.spent * 100;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors[entry.key % colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '${percent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _money(item.amount),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DailyChart extends StatelessWidget {
  final AnalyticsSnapshot data;
  const _DailyChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final days = DateTime(data.month.year, data.month.month + 1, 0).day;
    final maxValue = data.dailySpend.values.fold<double>(0, mathMax);
    return BarChart(
      BarChartData(
        maxY: maxValue <= 0 ? 1000 : maxValue * 1.2,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: days > 15 ? 5 : 1,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
              ),
            ),
          ),
        ),
        barGroups: List.generate(
          days,
          (index) => BarChartGroupData(
            x: index + 1,
            barRods: [
              BarChartRodData(
                toY: data.dailySpend[index + 1] ?? 0,
                color: AppColors.aiVioletLight,
                width: 5,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MerchantList extends StatelessWidget {
  final AnalyticsSnapshot data;
  final NumberFormat money;

  const _MerchantList({required this.data, required this.money});

  @override
  Widget build(BuildContext context) {
    if (data.merchants.isEmpty) {
      return const Text(
        'Merchant names will appear as notifications provide them.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      );
    }
    return Column(
      children: data.merchants.map((merchant) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.aiContainer,
                child: Text(
                  merchant.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.aiVioletLight,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${merchant.transactionCount} transactions',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '-${money.format(merchant.amount)}',
                style: const TextStyle(
                  color: AppColors.debitLight,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _InsightPanel extends StatelessWidget {
  final AnalyticsSnapshot data;
  final NumberFormat money;

  const _InsightPanel({required this.data, required this.money});

  @override
  Widget build(BuildContext context) {
    final top = data.categories.isEmpty ? null : data.categories.first;
    final previous = data.monthlyTrend.length > 1
        ? data.monthlyTrend[data.monthlyTrend.length - 2]
        : null;
    final change = previous == null || previous.spent == 0
        ? null
        : ((data.spent - previous.spent) / previous.spent) * 100;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.aiContainer, AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.aiViolet.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.aiVioletLight,
                size: 18,
              ),
              SizedBox(width: 7),
              Text(
                'Spending Insights',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            top == null
                ? 'Capture a few transactions to unlock personalized insights.'
                : '${top.name} is your largest category at ${money.format(top.amount)} (${(top.amount / data.spent * 100).toStringAsFixed(0)}% of spending).',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (change != null) ...[
            const SizedBox(height: 6),
            Text(
              '${change >= 0 ? 'Up' : 'Down'} ${change.abs().toStringAsFixed(0)}% compared with last month.',
              style: TextStyle(
                fontSize: 12,
                color: change >= 0
                    ? AppColors.debitLight
                    : AppColors.creditLight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _money(double value) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
).format(value);
String _compact(double value) => value >= 1000
    ? '${(value / 1000).toStringAsFixed(1)}K'
    : value.toStringAsFixed(0);
double mathMax(double a, double b) => a > b ? a : b;
