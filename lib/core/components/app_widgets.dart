import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Large screen title with a tinted icon badge on the right.
///
/// Home, Analytics, Expenses and Account all drew this by hand with slightly
/// different sizes; this keeps them identical.
class ScreenHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final List<Widget> actions;

  const ScreenHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.pageGutter,
        AppTokens.gapLg,
        AppTokens.pageGutter,
        AppTokens.gapSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
          if (actions.isNotEmpty) const SizedBox(width: AppTokens.gapSm),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Icon(icon, color: colorScheme.primary, size: 22),
          ),
        ],
      ),
    );
  }
}

/// Smaller "Transactions History" style heading with an optional trailing
/// action or count.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.pageGutter,
        AppTokens.gapMd,
        AppTokens.pageGutter,
        AppTokens.gapSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (trailing != null)
            Flexible(child: Align(alignment: Alignment.centerRight, child: trailing!)),
        ],
      ),
    );
  }
}

/// Illustrated, optionally actionable empty state.
class EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry margin;

  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.margin = const EdgeInsets.symmetric(horizontal: AppTokens.pageGutter),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(AppTokens.gapXl),
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: colorScheme.appBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: Icon(icon, color: colorScheme.primary, size: 28),
          ),
          const SizedBox(height: AppTokens.gapMd),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppTokens.gapXs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppTokens.gapLg),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shimmer-free skeleton block used while a stream delivers its first payload.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = AppTokens.radiusSm,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: colorScheme.appCardMuted,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Placeholder list shown while transactions load for the first time.
class TransactionListSkeleton extends StatelessWidget {
  final int itemCount;

  const TransactionListSkeleton({super.key, this.itemCount = 4});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (var index = 0; index < itemCount; index++)
          Container(
            margin: const EdgeInsets.only(bottom: AppTokens.gapSm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.gapMd,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: colorScheme.appCard,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              border: Border.all(color: colorScheme.appBorder),
            ),
            child: const Row(
              children: [
                SkeletonBox(width: 40, height: 40, radius: AppTokens.radiusSm),
                SizedBox(width: AppTokens.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 130, height: 12),
                      SizedBox(height: AppTokens.gapSm),
                      SkeletonBox(width: 90, height: 10),
                    ],
                  ),
                ),
                SizedBox(width: AppTokens.gapSm),
                SkeletonBox(width: 64, height: 14),
              ],
            ),
          ),
      ],
    );
  }
}
