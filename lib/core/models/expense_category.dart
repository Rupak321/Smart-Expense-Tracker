/// Whether a category is for money going out, coming in, or either.
///
/// Without this an income category can be attached to an expense — which is
/// how a one-off land sale ended up filed under "Salary".
enum CategoryKind { expense, income, both }

extension CategoryKindInfo on CategoryKind {
  String get label => switch (this) {
    CategoryKind.expense => 'Expense',
    CategoryKind.income => 'Income',
    CategoryKind.both => 'Either',
  };

  /// True when this category may be used for a transaction of the given
  /// direction.
  bool allows({required bool isExpense}) {
    return switch (this) {
      CategoryKind.expense => isExpense,
      CategoryKind.income => !isExpense,
      CategoryKind.both => true,
    };
  }

  static CategoryKind parse(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'income' => CategoryKind.income,
      'both' => CategoryKind.both,
      _ => CategoryKind.expense,
    };
  }
}

/// A category in the user's own vocabulary.
///
/// Transactions still store the category *name*, not this id. Keeping the name
/// denormalised means no schema migration for existing records, and rename and
/// merge simply rewrite the affected transactions.
class ExpenseCategory {
  final String id;
  final String name;
  final CategoryKind kind;

  /// Key into [CategoryIcons], not a raw code point — storing code points
  /// breaks icon tree-shaking in release builds.
  final String iconKey;

  /// Index into the shared chart palette, so colours stay theme-correct in
  /// both light and dark rather than being frozen hex values.
  final int colorIndex;

  /// Seeded categories. They can be renamed and merged, but the fallback
  /// cannot be deleted.
  final bool isSystem;

  final DateTime createdAt;

  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.iconKey,
    required this.colorIndex,
    required this.createdAt,
    this.isSystem = false,
  });

  /// The category every unmatched transaction falls back to.
  static const fallbackName = 'Other';

  bool get isFallback => name.trim().toLowerCase() == 'other';

  ExpenseCategory copyWith({
    String? name,
    CategoryKind? kind,
    String? iconKey,
    int? colorIndex,
  }) {
    return ExpenseCategory(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      iconKey: iconKey ?? this.iconKey,
      colorIndex: colorIndex ?? this.colorIndex,
      createdAt: createdAt,
      isSystem: isSystem,
    );
  }

  factory ExpenseCategory.fromMap(String id, Map<String, dynamic> map) {
    return ExpenseCategory(
      id: id,
      name: map['name']?.toString().trim() ?? 'Untitled',
      kind: CategoryKindInfo.parse(map['kind']?.toString()),
      iconKey: map['iconKey']?.toString() ?? 'category',
      colorIndex: (map['colorIndex'] as num?)?.toInt() ?? 0,
      isSystem: map['isSystem'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'kind': kind.name,
      'iconKey': iconKey,
      'colorIndex': colorIndex,
      'isSystem': isSystem,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// The starting vocabulary.
  ///
  /// Deliberately flat. The "Group - Sub" shape in the existing data was
  /// improvised by the model, and it is why one kind of spending can appear as
  /// two separate slices in analytics.
  static List<ExpenseCategory> defaults(DateTime now) {
    ExpenseCategory make(
      String name,
      CategoryKind kind,
      String iconKey,
      int colorIndex,
    ) {
      return ExpenseCategory(
        id: '',
        name: name,
        kind: kind,
        iconKey: iconKey,
        colorIndex: colorIndex,
        createdAt: now,
        isSystem: true,
      );
    }

    return [
      make('Food & Dining', CategoryKind.expense, 'restaurant', 0),
      make('Groceries', CategoryKind.expense, 'groceries', 10),
      make('Transport', CategoryKind.expense, 'transport', 1),
      make('Shopping', CategoryKind.expense, 'shopping', 2),
      make('Bills & Utilities', CategoryKind.expense, 'bill', 3),
      make('Rent', CategoryKind.expense, 'home', 7),
      make('Health', CategoryKind.expense, 'health', 4),
      make('Education', CategoryKind.expense, 'education', 8),
      make('Entertainment', CategoryKind.expense, 'entertainment', 5),
      make('Personal', CategoryKind.expense, 'personal', 9),
      make('Salary', CategoryKind.income, 'salary', 6),
      make('Business', CategoryKind.income, 'business', 3),
      make('Freelance', CategoryKind.income, 'laptop', 1),
      make('Family & Gifts', CategoryKind.both, 'gift', 4),
      make('Investments', CategoryKind.income, 'investment', 6),
      make('Refunds', CategoryKind.income, 'refund', 10),
      make(ExpenseCategory.fallbackName, CategoryKind.both, 'category', 11),
    ];
  }
}
