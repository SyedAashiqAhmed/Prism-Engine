import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';

/// Reusable transaction list tile for the dashboard feed.
class TxnListTile extends StatelessWidget {
  final Map<String, dynamic> row;

  const TxnListTile({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final isDebit = (row['txn_type'] as String?) == 'DEBIT';
    final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
    final merchant = (row['merchant'] as String?) ??
        (row['title'] as String?) ??
        'Transaction';
    final timestamp = row['timestamp'] as int? ?? 0;
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final color = isDebit ? AppColors.debit : AppColors.credit;
    final colorLight = isDebit ? AppColors.debitLight : AppColors.creditLight;
    final containerColor =
        isDebit ? AppColors.debitContainer : AppColors.creditContainer;
    final icon = isDebit
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final txnDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(txnDay).inDays;

    String dateLabel;
    if (diff == 0) {
      dateLabel = 'Today, ${DateFormat('h:mm a').format(dt)}';
    } else if (diff == 1) {
      dateLabel = 'Yesterday, ${DateFormat('h:mm a').format(dt)}';
    } else if (diff < 7) {
      dateLabel = DateFormat('EEEE, h:mm a').format(dt); // e.g. "Monday, 3:45 PM"
    } else {
      dateLabel = DateFormat('d MMM, h:mm a').format(dt);
    }

    final fmt = NumberFormat('#,##,##0.00', 'en_IN');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isDebit ? '-' : '+'}₹${fmt.format(amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: colorLight,
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: containerColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isDebit ? 'DEBIT' : 'CREDIT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
