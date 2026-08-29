import 'package:flutter/material.dart';

import '../../core/categories/category_icons.dart';
import '../../core/categories/category_matcher.dart';
import '../../core/models/expense_category.dart';
import '../../core/models/expense_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_utils.dart';
import '../../services/category_service.dart';
import '../../services/user_data_service.dart';

/// Manage the category vocabulary: rename, merge, delete, and clean up
/// duplicates that accumulated while categories were free-form strings.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<void> _seeding;

  @override
  void initState() {
    super.initState();
    _seeding = CategoryService.ensureSeeded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            tooltip: 'Add category',
            onPressed: _createCategory,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _seeding,
        builder: (context, seedSnapshot) {
          if (seedSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<List<ExpenseCategory>>(
            stream: CategoryService.stream(),
            builder: (context, categorySnapshot) {
              final categories = categorySnapshot.data;
              if (categories == null) {
                return const Center(child: CircularProgressIndicator());
              }

              return StreamBuilder<List<ExpenseModel>>(
                stream: UserDataService.transactionsStream(),
                builder: (context, txSnapshot) {
                  final usage = CategoryService.usage(
                    txSnapshot.data ?? const <ExpenseModel>[],
                  );
                  return _CategoryList(
                    categories: categories,
                    usage: usage,
                    onEdit: _editCategory,
                    onTidyUp: () => _tidyUp(categories, usage),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createCategory() async {
    final result = await showModalBottomSheet<_CategoryDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _CategoryEditSheet(),
    );
    if (result == null) return;

    try {
      await CategoryService.create(
        name: result.name,
        kind: result.kind,
        iconKey: result.iconKey,
        colorIndex: result.colorIndex,
      );
      if (mounted) _snack('Added ${result.name}');
    } catch (error) {
      if (mounted) _snack('Could not add it: $error');
    }
  }

  Future<void> _editCategory(
    ExpenseCategory category,
    List<ExpenseCategory> all,
    CategoryUsage usage,
  ) async {
    final result = await showModalBottomSheet<_CategoryDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CategoryEditSheet(
        category: category,
        usage: usage,
        canDelete: !category.isFallback,
        canMerge: all.length > 1,
      ),
    );
    if (result == null || !mounted) return;

    switch (result.action) {
      case _CategoryAction.save:
        await _applyEdits(category, result);
      case _CategoryAction.merge:
        await _mergeCategory(category, all);
      case _CategoryAction.delete:
        await _deleteCategory(category, usage);
    }
  }

  Future<void> _applyEdits(
    ExpenseCategory category,
    _CategoryDraft draft,
  ) async {
    try {
      final renamed = draft.name.trim() != category.name;
      await CategoryService.update(
        category.copyWith(
          name: draft.name.trim(),
          kind: draft.kind,
          iconKey: draft.iconKey,
          colorIndex: draft.colorIndex,
        ),
      );

      var moved = 0;
      if (renamed) {
        // update() already stored the new name; this repoints the rows.
        moved = await CategoryService.rename(
          category.copyWith(name: category.name),
          draft.name.trim(),
        );
      }

      if (mounted) {
        _snack(
          renamed && moved > 0
              ? 'Renamed, and updated $moved transaction'
                    '${moved == 1 ? '' : 's'}'
              : 'Saved',
        );
      }
    } catch (error) {
      if (mounted) _snack('Could not save it: $error');
    }
  }

  Future<void> _mergeCategory(
    ExpenseCategory from,
    List<ExpenseCategory> all,
  ) async {
    final target = await showModalBottomSheet<ExpenseCategory>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _MergeTargetSheet(
        from: from,
        options: all.where((c) => c.id != from.id).toList(),
      ),
    );
    if (target == null || !mounted) return;

    final confirmed = await _confirm(
      title: 'Merge ${from.name}?',
      message:
          'Every transaction in "${from.name}" moves to "${target.name}", '
          'and "${from.name}" is removed. This cannot be undone.',
      action: 'Merge',
    );
    if (!confirmed) return;

    try {
      final moved = await CategoryService.merge(from: from, into: target);
      if (mounted) {
        _snack('Moved $moved transaction${moved == 1 ? '' : 's'} '
            'into ${target.name}');
      }
    } catch (error) {
      if (mounted) _snack('Could not merge: $error');
    }
  }

  Future<void> _deleteCategory(
    ExpenseCategory category,
    CategoryUsage usage,
  ) async {
    final confirmed = await _confirm(
      title: 'Delete ${category.name}?',
      message: usage.count == 0
          ? 'Nothing is filed under it, so nothing else changes.'
          : '${usage.count} transaction${usage.count == 1 ? '' : 's'} '
                'will move to "${ExpenseCategory.fallbackName}".',
      action: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await CategoryService.delete(category);
      if (mounted) _snack('Deleted ${category.name}');
    } catch (error) {
      if (mounted) _snack('Could not delete: $error');
    }
  }

  Future<void> _tidyUp(
    List<ExpenseCategory> categories,
    Map<String, CategoryUsage> usage,
  ) async {
    final suggestions = CategoryService.findDuplicates(
      categories,
      usage: usage,
    );
    if (suggestions.isEmpty) {
      _snack('No duplicates found.');
      return;
    }

    final approved = await showModalBottomSheet<List<DuplicateSuggestion>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _TidyUpSheet(suggestions: suggestions),
    );
    if (approved == null || approved.isEmpty || !mounted) return;

    var moved = 0;
    for (final suggestion in approved) {
      try {
        moved += await CategoryService.merge(
          from: suggestion.from,
          into: suggestion.into,
        );
      } catch (_) {
        // Keep going; one failed merge should not abandon the rest.
      }
    }

    if (mounted) {
      _snack('Merged ${approved.length} categor'
          '${approved.length == 1 ? 'y' : 'ies'}, '
          'moving $moved transaction${moved == 1 ? '' : 's'}');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                  )
                : null,
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CategoryList extends StatelessWidget {
  final List<ExpenseCategory> categories;
  final Map<String, CategoryUsage> usage;
  final void Function(
    ExpenseCategory category,
    List<ExpenseCategory> all,
    CategoryUsage usage,
  )
  onEdit;
  final VoidCallback onTidyUp;

  const _CategoryList({
    required this.categories,
    required this.usage,
    required this.onEdit,
    required this.onTidyUp,
  });

  @override
  Widget build(BuildContext context) {
    final duplicates = CategoryService.findDuplicates(
      categories,
      usage: usage,
    );
    final expense = categories
        .where((c) => c.kind != CategoryKind.income)
        .toList();
    final income = categories
        .where((c) => c.kind != CategoryKind.expense)
        .toList();
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppTokens.pageGutter,
        AppTokens.gapLg,
        AppTokens.pageGutter,
        AppTokens.gapXl + bottomInset,
      ),
      children: [
        if (duplicates.isNotEmpty) ...[
          _DuplicateBanner(count: duplicates.length, onTidyUp: onTidyUp),
          const SizedBox(height: AppTokens.gapLg),
        ],
        _GroupLabel('Spending (${expense.length})'),
        for (final category in expense)
          _CategoryTile(
            category: category,
            usage: usage[category.name] ?? const CategoryUsage(),
            onTap: () => onEdit(
              category,
              categories,
              usage[category.name] ?? const CategoryUsage(),
            ),
          ),
        const SizedBox(height: AppTokens.gapLg),
        _GroupLabel('Income (${income.length})'),
        for (final category in income)
          _CategoryTile(
            category: category,
            usage: usage[category.name] ?? const CategoryUsage(),
            onTap: () => onEdit(
              category,
              categories,
              usage[category.name] ?? const CategoryUsage(),
            ),
          ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String label;

  const _GroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppTokens.gapSm),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DuplicateBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTidyUp;

  const _DuplicateBanner({required this.count, required this.onTidyUp});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapLg),
      decoration: BoxDecoration(
        color: colorScheme.appWarning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: colorScheme.appWarning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_fix_high_rounded,
                color: colorScheme.appWarning,
                size: 20,
              ),
              const SizedBox(width: AppTokens.gapSm),
              Expanded(
                child: Text(
                  '$count possible duplicate${count == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.gapSm),
          Text(
            'Some categories look like different names for the same thing, '
            'which splits them apart in analytics.',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTokens.gapMd),
          OutlinedButton.icon(
            onPressed: onTidyUp,
            icon: const Icon(Icons.merge_rounded, size: 18),
            label: const Text('Review and merge'),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ExpenseCategory category;
  final CategoryUsage usage;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.usage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = AppColorRoles
        .chartPalette[category.colorIndex % AppColorRoles.chartPalette.length];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.gapSm),
      child: Material(
        color: colorScheme.appCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          side: BorderSide(color: colorScheme.appBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Icon(
              CategoryIcons.resolve(category.iconKey),
              color: color,
              size: 21,
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (category.kind == CategoryKind.both) ...[
                const SizedBox(width: AppTokens.gapSm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.appCardMuted,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                  child: Text(
                    'either',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            usage.count == 0
                ? 'Not used yet'
                : '${usage.count} transaction${usage.count == 1 ? '' : 's'} · '
                      '${MoneyUtils.formatPaisa(usage.paisa)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }
}

enum _CategoryAction { save, merge, delete }

class _CategoryDraft {
  final String name;
  final CategoryKind kind;
  final String iconKey;
  final int colorIndex;
  final _CategoryAction action;

  const _CategoryDraft({
    required this.name,
    required this.kind,
    required this.iconKey,
    required this.colorIndex,
    this.action = _CategoryAction.save,
  });
}

class _CategoryEditSheet extends StatefulWidget {
  final ExpenseCategory? category;
  final CategoryUsage? usage;
  final bool canDelete;
  final bool canMerge;

  const _CategoryEditSheet({
    this.category,
    this.usage,
    this.canDelete = false,
    this.canMerge = false,
  });

  @override
  State<_CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends State<_CategoryEditSheet> {
  late final TextEditingController _nameController;
  late CategoryKind _kind;
  late String _iconKey;
  late int _colorIndex;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _nameController = TextEditingController(text: category?.name ?? '');
    _kind = category?.kind ?? CategoryKind.expense;
    _iconKey = category?.iconKey ?? CategoryIcons.fallbackKey;
    _colorIndex = category?.colorIndex ?? 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = widget.category != null;
    final usage = widget.usage;

    return Padding(
      padding: EdgeInsets.only(
        left: AppTokens.gapLg,
        right: AppTokens.gapLg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppTokens.gapXl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEditing ? 'Edit category' : 'New category',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (usage != null && usage.count > 0) ...[
              const SizedBox(height: AppTokens.gapXs),
              Text(
                '${usage.count} transaction${usage.count == 1 ? '' : 's'} '
                'use this',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: AppTokens.gapLg),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.label_rounded),
              ),
              onChanged: (value) {
                if (widget.category == null) {
                  setState(() => _iconKey = CategoryIcons.suggestFor(value));
                }
              },
            ),
            const SizedBox(height: AppTokens.gapLg),
            Text(
              'Used for',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.gapSm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<CategoryKind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: CategoryKind.expense,
                    label: Text('Expense'),
                  ),
                  ButtonSegment(
                    value: CategoryKind.income,
                    label: Text('Income'),
                  ),
                  ButtonSegment(value: CategoryKind.both, label: Text('Either')),
                ],
                selected: {_kind},
                onSelectionChanged: (value) =>
                    setState(() => _kind = value.first),
              ),
            ),
            const SizedBox(height: AppTokens.gapLg),
            Text(
              'Icon',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.gapSm),
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: CategoryIcons.pickable.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppTokens.gapSm),
                itemBuilder: (context, index) {
                  final key = CategoryIcons.pickable[index];
                  final selected = key == _iconKey;
                  return InkWell(
                    onTap: () => setState(() => _iconKey = key),
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                    child: Container(
                      width: 48,
                      decoration: BoxDecoration(
                        color: selected
                            ? colorScheme.primary.withValues(alpha: 0.16)
                            : colorScheme.appCardMuted,
                        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                        border: Border.all(
                          color: selected
                              ? colorScheme.primary
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        CategoryIcons.resolve(key),
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppTokens.gapLg),
            Text(
              'Colour',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.gapSm),
            Wrap(
              spacing: AppTokens.gapSm,
              runSpacing: AppTokens.gapSm,
              children: [
                for (
                  var index = 0;
                  index < AppColorRoles.chartPalette.length;
                  index++
                )
                  GestureDetector(
                    onTap: () => setState(() => _colorIndex = index),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColorRoles.chartPalette[index],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: index == _colorIndex
                              ? colorScheme.onSurface
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.gapXl),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(isEditing ? 'Save changes' : 'Add category'),
            ),
            if (widget.canMerge) ...[
              const SizedBox(height: AppTokens.gapSm),
              OutlinedButton.icon(
                onPressed: () => _pop(_CategoryAction.merge),
                icon: const Icon(Icons.merge_rounded, size: 18),
                label: const Text('Merge into another'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
            if (widget.canDelete) ...[
              const SizedBox(height: AppTokens.gapSm),
              TextButton.icon(
                onPressed: () => _pop(_CategoryAction.delete),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete category'),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Give it a name first')));
      return;
    }
    _pop(_CategoryAction.save);
  }

  void _pop(_CategoryAction action) {
    Navigator.of(context).pop(
      _CategoryDraft(
        name: _nameController.text.trim(),
        kind: _kind,
        iconKey: _iconKey,
        colorIndex: _colorIndex,
        action: action,
      ),
    );
  }
}

class _MergeTargetSheet extends StatelessWidget {
  final ExpenseCategory from;
  final List<ExpenseCategory> options;

  const _MergeTargetSheet({required this.from, required this.options});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.gapXl,
              0,
              AppTokens.gapXl,
              AppTokens.gapSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Merge "${from.name}" into',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppTokens.gapXs),
                Text(
                  'Its transactions move to whichever you pick.',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.gapLg,
                vertical: AppTokens.gapSm,
              ),
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                final color = AppColorRoles.chartPalette[option.colorIndex %
                    AppColorRoles.chartPalette.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.gapSm),
                  child: Material(
                    color: colorScheme.appCard,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      side: BorderSide(color: colorScheme.appBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      onTap: () => Navigator.of(context).pop(option),
                      leading: Icon(
                        CategoryIcons.resolve(option.iconKey),
                        color: color,
                      ),
                      title: Text(
                        option.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppTokens.gapSm),
        ],
      ),
    );
  }
}

class _TidyUpSheet extends StatefulWidget {
  final List<DuplicateSuggestion> suggestions;

  const _TidyUpSheet({required this.suggestions});

  @override
  State<_TidyUpSheet> createState() => _TidyUpSheetState();
}

class _TidyUpSheetState extends State<_TidyUpSheet> {
  late final Set<int> _selected = {
    for (var index = 0; index < widget.suggestions.length; index++) index,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.gapXl,
              0,
              AppTokens.gapXl,
              AppTokens.gapSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tidy up categories',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppTokens.gapXs),
                Text(
                  'Untick anything you want to keep separate.',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.gapLg,
              ),
              itemCount: widget.suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = widget.suggestions[index];
                return CheckboxListTile(
                  value: _selected.contains(index),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selected.add(index);
                      } else {
                        _selected.remove(index);
                      }
                    });
                  },
                  title: Text(
                    '${suggestion.from.name}  →  ${suggestion.into.name}',
                    maxLines: 2,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(_reasonLabel(suggestion.reason)),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTokens.gapLg),
            child: FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop([
                      for (final index in _selected) widget.suggestions[index],
                    ]),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(
                _selected.isEmpty
                    ? 'Nothing selected'
                    : 'Merge ${_selected.length} selected',
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _reasonLabel(CategoryMatchReason reason) {
    return switch (reason) {
      CategoryMatchReason.exact => 'Same name',
      CategoryMatchReason.alias => 'Means the same thing',
      CategoryMatchReason.similar => 'Very similar name',
      CategoryMatchReason.novel => 'Unrelated',
    };
  }
}
