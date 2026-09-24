import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';

/// Reusable Credit / Debit summary card widget.
class SpendCard extends ConsumerWidget {
  final bool isDebit;

  const SpendCard({super.key, required this.isDebit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final amount = isDebit ? state.monthlyDebits : state.monthlyCredits;
    final todayAmount = isDebit ? state.todayDebits : state.todayCredits;
    final color = isDebit ? AppColors.debit : AppColors.credit;
    final colorLight = isDebit ? AppColors.debitLight : AppColors.creditLight;
    final containerColor =
        isDebit ? AppColors.debitContainer : AppColors.creditContainer;
    final label = isDebit ? 'Total Spent' : 'Total Received';
    final todayLabel = isDebit ? 'Today spent' : 'Today received';
    final icon = isDebit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
    final fmt = NumberFormat('#,##,##0.00', 'en_IN');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(60), width: 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surface,
            containerColor.withAlpha(40),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(20),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: containerColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          state.isLoading
              ? Container(
                  height: 34,
                  width: 140,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                )
              : Text(
                  '₹${fmt.format(amount)}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: colorLight,
                    letterSpacing: -0.5,
                  ),
                ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.today_rounded, size: 12, color: colorLight),
                const SizedBox(width: 4),
                Text(
                  state.isLoading
                      ? '—'
                      : '$todayLabel: ₹${fmt.format(todayAmount)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colorLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
