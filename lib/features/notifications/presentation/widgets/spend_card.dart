import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';

/// Reusable credit/debit summary block for the dashboard.
class SpendCard extends ConsumerWidget {
  final bool isDebit;

  const SpendCard({super.key, required this.isDebit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final amount = isDebit ? state.monthlyDebits : state.monthlyCredits;
    final todayAmount = isDebit ? state.todayDebits : state.todayCredits;
    final color = isDebit ? AppColors.debit : AppColors.credit;
    final containerColor = isDebit
        ? AppColors.debitContainer
        : AppColors.creditContainer;
    final foregroundColor = isDebit
        ? AppColors.debitLight
        : AppColors.creditLight;
    final label = isDebit ? 'Total Spent' : 'Total Received';
    final todayLabel = 'Today';
    final icon = isDebit
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;
    final fmt = NumberFormat('#,##,##0.00', 'en_IN');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(
          top: BorderSide(color: color, width: 2),
          bottom: const BorderSide(color: AppColors.glassBorder),
          left: const BorderSide(color: AppColors.glassBorder),
          right: const BorderSide(color: AppColors.glassBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: containerColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: foregroundColor, size: 16),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          state.isLoading
              ? Container(
                  height: 28,
                  width: 100,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                )
              : Text(
                  '₹${fmt.format(amount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
          const SizedBox(height: 8),
          Text(
            state.isLoading
                ? 'Today  —'
                : '$todayLabel  ₹${fmt.format(todayAmount)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}
