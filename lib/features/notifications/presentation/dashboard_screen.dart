import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/queries/notification_category_queries.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/dashboard_provider.dart';
import 'category_browser_screen.dart';
import 'widgets/spend_card.dart';
import 'widgets/txn_list_tile.dart';

/// Main financial dashboard screen showing real-time credit/debit totals,
/// EOD spend summary, and recent transactions fed from the notification listener.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<Map<String, int>> _categoryCounts;
  String _filter = 'All'; // 'All', 'DEBIT', 'CREDIT'

  @override
  void initState() {
    super.initState();
    _categoryCounts = _loadCategoryCounts();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _filter = ['All', 'DEBIT', 'CREDIT'][_tabController.index];
        });
      }
    });
  }

  Future<Map<String, int>> _loadCategoryCounts() =>
      NotificationCategoryQueries.getCategoryCounts(
        notificationCategories.map((category) => category.name).toList(),
      );

  Future<void> _refreshDashboard() async {
    await ref.read(dashboardProvider.notifier).refresh();
    if (mounted) {
      setState(() => _categoryCounts = _loadCategoryCounts());
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Injects a fake bank transaction DIRECTLY into SQLite to verify
  /// the DB → Riverpod → UI pipeline works independently of the
  /// notification listener service. Also tests a CREDIT variant.
  Future<void> _injectTestTransaction() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Inject a DEBIT (simulates HDFC bank SMS)
    await DatabaseHelper.instance.insertNotification({
      'source_key': 'test_hdfc_debit_$now',
      'package_name': 'com.google.android.apps.messaging',
      'sender_header': null,
      'title': 'HDFC Bank',
      'text':
          'Rs.500.00 debited from A/c XX1234 on ${DateTime.now()}. Avl Bal Rs.10,000.00',
      'timestamp': now,
      'category': 'Bank',
      'merchant': 'Test Merchant',
      'amount': 500.0,
      'txn_type': 'DEBIT',
      'is_priority': 0,
    });

    // Inject a CREDIT (simulates HDFC bank credit SMS)
    await DatabaseHelper.instance.insertNotification({
      'source_key': 'test_hdfc_credit_$now',
      'package_name': 'com.google.android.apps.messaging',
      'sender_header': null,
      'title': 'HDFC Bank',
      'text':
          'Rs.1000.00 credited to A/c XX1234 on ${DateTime.now()}. Avl Bal Rs.11,000.00',
      'timestamp': now + 1,
      'category': 'Bank',
      'merchant': null,
      'amount': 1000.0,
      'txn_type': 'CREDIT',
      'is_priority': 0,
    });

    await ref.read(dashboardProvider.notifier).refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '✅ Test transactions injected! (₹500 DEBIT + ₹1000 CREDIT)',
          ),
          backgroundColor: AppColors.aiViolet.withAlpha(220),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Shows a confirmation dialog then deletes all transactions from SQLite.
  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear All Data?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'This will permanently delete all captured transactions from the local database. This cannot be undone.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete All',
              style: TextStyle(
                color: AppColors.debit,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      await ref.read(dashboardProvider.notifier).deleteAll();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('🗑️ All transaction data cleared.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardProvider);
    // Show error snackbar if dashboard DB load fails
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.errorMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ${state.errorMessage}'),
            backgroundColor: AppColors.debit.withAlpha(200),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
    final now = DateTime.now();
    final dateLabel = DateFormat('dd MMM yyyy').format(now);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _refreshDashboard,
        color: AppColors.credit,
        backgroundColor: AppColors.surface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ─── App Bar ───────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 126,
              pinned: true,
              backgroundColor: AppColors.background,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF10251C), AppColors.background],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 52, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Prism Engine',
                            style: TextStyle(
                              fontSize: 23,
                              height: 0.95,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'EXPENSE TRACKER',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.credit,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _LivePillWidget(),
                      IconButton(
                        onPressed: _refreshDashboard,
                        icon: const Icon(Icons.refresh_rounded, size: 19),
                        color: AppColors.background,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.credit,
                        ),
                        tooltip: 'Refresh data',
                        visualDensity: VisualDensity.compact,
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'More options',
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        onSelected: (value) {
                          if (value == 'clear') _clearAllData();
                          if (value == 'test') _injectTestTransaction();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'clear',
                            child: Text('Clear all transactions'),
                          ),
                          PopupMenuItem(
                            value: 'test',
                            child: Text('Inject test transactions'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ─── Body ──────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        size: 14,
                        color: AppColors.credit,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Spend summary cards (side by side)
                  Row(
                    children: [
                      Expanded(child: SpendCard(isDebit: true)),
                      const SizedBox(width: 12),
                      Expanded(child: SpendCard(isDebit: false)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── EOD Summary Banner ─────────────────────────────
                  _EodSummaryBanner(state: state),
                  const SizedBox(height: 20),

                  // ─── Notification Categories ────────────────────────
                  _DashboardCategorySection(
                    categoryCounts: _categoryCounts,
                    onRetry: () =>
                        setState(() => _categoryCounts = _loadCategoryCounts()),
                  ),
                  const SizedBox(height: 20),

                  // ─── Transaction Feed ───────────────────────────────
                  Row(
                    children: [
                      const Text(
                        'Transactions',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.aiContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${state.transactionCount} total',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.aiVioletLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Filter tabs
                  _FilterTabBar(controller: _tabController),
                  const SizedBox(height: 12),

                  // Transaction list
                  _TransactionList(filter: _filter, state: state),

                  const SizedBox(height: 80),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Pill Indicator
// ─────────────────────────────────────────────────────────────────────────────
class _LivePillWidget extends StatefulWidget {
  @override
  State<_LivePillWidget> createState() => _LivePillWidgetState();
}

class _LivePillWidgetState extends State<_LivePillWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.creditContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.credit.withAlpha((_anim.value * 180).round()),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.credit.withAlpha((_anim.value * 255).round()),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'LIVE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.creditLight.withAlpha(
                  (_anim.value * 255).round(),
                ),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCategorySection extends StatelessWidget {
  final Future<Map<String, int>> categoryCounts;
  final VoidCallback onRetry;

  const _DashboardCategorySection({
    required this.categoryCounts,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Text(
              'NOTIFICATION CATEGORIES',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.35,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationCategoryBrowserScreen(),
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.credit,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('See All →', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 9),
        FutureBuilder<Map<String, int>>(
          future: categoryCounts,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Could not load notification categories.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.credit,
                backgroundColor: AppColors.surfaceElevated,
              );
            }

            final counts = snapshot.data!;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: notificationCategories.length + 1,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.92,
              ),
              itemBuilder: (context, index) {
                if (index == notificationCategories.length) {
                  return _MoreCategoriesTile(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const NotificationCategoryBrowserScreen(),
                      ),
                    ),
                  );
                }

                final category = notificationCategories[index];
                return _DashboardCategoryTile(
                  category: category,
                  count: counts[category.name] ?? 0,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          NotificationCategoryDetailScreen(category: category),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _DashboardCategoryTile extends StatelessWidget {
  final NotificationCategoryDefinition category;
  final int count;
  final VoidCallback onTap;

  const _DashboardCategoryTile({
    required this.category,
    required this.count,
    required this.onTap,
  });

  String get _label => switch (category.name) {
    'Banking & Payments' => 'Banking',
    'Deliveries & Orders' => 'Orders',
    'Bills & Due Dates' => 'Bills',
    'Placement & Jobs' => 'Jobs',
    'Travel & Transport' => 'Travel',
    'Appointments & Reminders' => 'Reminders',
    _ => category.name,
  };

  @override
  Widget build(BuildContext context) {
    final tileColor = category.name == 'Unclassified'
        ? const Color(0xFF52605A)
        : category.color;
    return Material(
      color: tileColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(category.icon, color: Colors.black87, size: 19),
              const SizedBox(height: 5),
              Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count',
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreCategoriesTile extends StatelessWidget {
  final VoidCallback onTap;

  const _MoreCategoriesTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: AppColors.textSecondary, size: 20),
            SizedBox(height: 5),
            Text(
              'More',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EOD Summary Banner
// ─────────────────────────────────────────────────────────────────────────────
class _EodSummaryBanner extends StatelessWidget {
  final DashboardState state;

  const _EodSummaryBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final net = state.todayCredits - state.todayDebits;
    final isPositive = net >= 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.aiViolet.withAlpha(60), AppColors.surfaceElevated],
        ),
        border: Border.all(color: AppColors.glassBorderStrong, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.nights_stay_rounded,
                color: AppColors.aiVioletLight,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'End of Day Summary · ${DateFormat('d MMM').format(now)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.aiVioletLight,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Each _EodItem is wrapped in Expanded so the three columns
          // share available width equally — prevents overflow on small phones.
          Row(
            children: [
              Expanded(
                child: _EodItem(
                  label: 'Spent',
                  amount: state.todayDebits,
                  color: AppColors.debitLight,
                  prefix: '-',
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.glassBorder),
              Expanded(
                child: _EodItem(
                  label: 'Received',
                  amount: state.todayCredits,
                  color: AppColors.creditLight,
                  prefix: '+',
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.glassBorder),
              Expanded(
                child: _EodItem(
                  label: 'Net',
                  amount: net.abs(),
                  color: isPositive
                      ? AppColors.creditLight
                      : AppColors.debitLight,
                  prefix: isPositive ? '+' : '-',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EodItem extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final String prefix;

  const _EodItem({
    required this.label,
    required this.amount,
    required this.color,
    required this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##,##0', 'en_IN');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textMuted,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        // FittedBox shrinks font size if the amount is too large for the
        // column — prevents overflow without truncating important digits.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$prefix₹${fmt.format(amount)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Tab Bar (All / Debit / Credit)
// ─────────────────────────────────────────────────────────────────────────────
class _FilterTabBar extends StatelessWidget {
  final TabController controller;

  const _FilterTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: AppColors.aiViolet,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(3),
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'All'),
          Tab(text: 'Debits'),
          Tab(text: 'Credits'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction List (filtered)
// ─────────────────────────────────────────────────────────────────────────────
class _TransactionList extends StatelessWidget {
  final String filter;
  final DashboardState state;

  const _TransactionList({required this.filter, required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return Column(
        children: List.generate(
          5,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            height: 66,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }

    final rows = filter == 'All'
        ? state.recentTransactions
        : state.recentTransactions
              .where((r) => r['txn_type'] == filter)
              .toList();

    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          children: [
            Icon(
              Icons.notifications_none_rounded,
              color: AppColors.textDisabled,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              filter == 'All'
                  ? 'No transactions captured yet.\nPrism Engine is listening for\nbank notifications in the background.'
                  : 'No ${filter == 'DEBIT' ? 'debit' : 'credit'} transactions yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    return Column(children: rows.map((row) => TxnListTile(row: row)).toList());
  }
}
