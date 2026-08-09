import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TransactionTile extends StatelessWidget {
  final String title;
  final String category;
  final String amount;
  final bool isExpense;
  final IconData icon;
  final VoidCallback? onTap;

  const TransactionTile({
    super.key,
    required this.title,
    required this.category,
    required this.amount,
    required this.isExpense,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isExpense ? colorScheme.appExpense : colorScheme.appIncome;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.gapSm),
      child: Material(
        color: colorScheme.appCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          side: BorderSide(color: colorScheme.appBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.gapMd,
              vertical: 10,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  child: Icon(icon, color: accent, size: 21),
                ),
                const SizedBox(width: AppTokens.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.2,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppTokens.gapXs),
                      Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTokens.gapSm),
                // Capped so a very large amount shrinks instead of pushing the
                // title out of the row.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      amount,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
