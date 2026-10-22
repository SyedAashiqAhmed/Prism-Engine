import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/database/queries/notification_category_queries.dart';
import '../../../core/theme/app_colors.dart';

class NotificationCategoryBrowserScreen extends StatefulWidget {
  const NotificationCategoryBrowserScreen({super.key});

  @override
  State<NotificationCategoryBrowserScreen> createState() =>
      _NotificationCategoryBrowserScreenState();
}

class _NotificationCategoryBrowserScreenState
    extends State<NotificationCategoryBrowserScreen> {
  late Future<Map<String, int>> _counts;

  @override
  void initState() {
    super.initState();
    _counts = _loadCounts();
  }

  Future<Map<String, int>> _loadCounts() =>
      NotificationCategoryQueries.getCategoryCounts(
        notificationCategories.map((category) => category.name).toList(),
      );

  void _refresh() {
    setState(() => _counts = _loadCounts());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notification Categories'),
        backgroundColor: AppColors.background,
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh categories',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, int>>(
        future: _counts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _CategoryLoadError(onRetry: _refresh);
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.aiViolet),
            );
          }

          final counts = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: notificationCategories.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final category = notificationCategories[index];
              return _CategoryCard(
                category: category,
                count: counts[category.name] ?? 0,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          NotificationCategoryDetailScreen(category: category),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class NotificationCategoryDetailScreen extends StatefulWidget {
  final NotificationCategoryDefinition category;

  const NotificationCategoryDetailScreen({required this.category, super.key});

  @override
  State<NotificationCategoryDetailScreen> createState() =>
      _NotificationCategoryDetailScreenState();
}

class _NotificationCategoryDetailScreenState
    extends State<NotificationCategoryDetailScreen> {
  late Future<List<Map<String, dynamic>>> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = _loadNotifications();
  }

  Future<List<Map<String, dynamic>>> _loadNotifications() =>
      NotificationCategoryQueries.getNotificationsForCategory(
        widget.category.name,
      );

  void _refresh() {
    setState(() => _notifications = _loadNotifications());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.category.name),
        backgroundColor: AppColors.background,
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh notifications',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _notifications,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _CategoryLoadError(onRetry: _refresh);
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.aiViolet),
            );
          }

          final notifications = snapshot.data!;
          if (notifications.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.category.icon,
                      size: 42,
                      color: widget.category.color,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No ${widget.category.name} notifications yet',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            color: AppColors.aiViolet,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _NotificationCard(
                notification: notifications[index],
                category: widget.category.name,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final NotificationCategoryDefinition category;
  final int count;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: category.color.withAlpha(30),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(category.icon, color: category.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count ${count == 1 ? 'notification' : 'notifications'}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> notification;
  final String category;

  const _NotificationCard({required this.notification, required this.category});

  @override
  Widget build(BuildContext context) {
    final title = (notification['title'] as String?)?.trim();
    final body = (notification['text'] as String?)?.trim() ?? '';
    final timestamp = notification['timestamp'] as int? ?? 0;
    final labels = [
      ...NotificationCategoryQueries.decodeLabels(
        notification['category_labels'] as String?,
      ),
    ];
    if (labels.isEmpty) {
      labels.add(notification['category'] as String? ?? category);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title == null || title.isEmpty ? 'Notification' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat(
                  'd MMM, h:mm a',
                ).format(DateTime.fromMillisecondsSinceEpoch(timestamp)),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: labels
                .map(
                  (label) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.aiContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.aiVioletLight,
                        fontSize: 10,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _CategoryLoadError extends StatelessWidget {
  final VoidCallback onRetry;

  const _CategoryLoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Could not load notification categories.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class NotificationCategoryDefinition {
  final String name;
  final IconData icon;
  final Color color;

  const NotificationCategoryDefinition(this.name, this.icon, this.color);
}

const notificationCategories = [
  NotificationCategoryDefinition(
    'Placement & Jobs',
    Icons.work_outline_rounded,
    AppColors.cyanAccent,
  ),
  NotificationCategoryDefinition(
    'Banking & Payments',
    Icons.account_balance_wallet_outlined,
    AppColors.creditLight,
  ),
  NotificationCategoryDefinition(
    'Deliveries & Orders',
    Icons.local_shipping_outlined,
    AppColors.warning,
  ),
  NotificationCategoryDefinition(
    'Bills & Due Dates',
    Icons.receipt_long_outlined,
    AppColors.debitLight,
  ),
  NotificationCategoryDefinition(
    'Travel & Transport',
    Icons.directions_transit_rounded,
    AppColors.cyanAccent,
  ),
  NotificationCategoryDefinition(
    'Appointments & Reminders',
    Icons.event_note_rounded,
    AppColors.aiVioletLight,
  ),
  NotificationCategoryDefinition(
    'Unclassified',
    Icons.notifications_none_rounded,
    AppColors.textSecondary,
  ),
];
