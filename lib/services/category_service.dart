import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/categories/category_icons.dart';
import '../core/categories/category_matcher.dart';
import '../core/models/expense_category.dart';
import '../core/models/expense_model.dart';
import 'user_data_service.dart';

/// Owns the user's category vocabulary and keeps transactions in step with it.
///
/// Transactions store the category *name*, so renaming or merging has to
/// rewrite the affected rows. Those rewrites go through batched writes so a
/// rename either lands everywhere or nowhere.
class CategoryService {
  const CategoryService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Firestore caps a batch at 500 operations.
  static const _batchLimit = 400;

  static CollectionReference<Map<String, dynamic>> _collection() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('User must be logged in to use categories.');
    }
    return _firestore.collection('users').doc(uid).collection('categories');
  }

  static CollectionReference<Map<String, dynamic>> _transactions() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('User must be logged in to use categories.');
    }
    return _firestore.collection('users').doc(uid).collection('data');
  }

  static Stream<List<ExpenseCategory>> stream() {
    try {
      return _collection().snapshots().map(_sorted);
    } catch (_) {
      return Stream.value(const <ExpenseCategory>[]);
    }
  }

  static Future<List<ExpenseCategory>> getOnce() async {
    try {
      final snapshot = await _collection().get();
      return _sorted(snapshot);
    } catch (_) {
      return <ExpenseCategory>[];
    }
  }

  static List<ExpenseCategory> _sorted(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final categories = snapshot.docs
        .map((doc) => ExpenseCategory.fromMap(doc.id, doc.data()))
        .where((category) => category.name.trim().isNotEmpty)
        .toList();
    // Fallback last, everything else alphabetical.
    categories.sort((a, b) {
      if (a.isFallback != b.isFallback) return a.isFallback ? 1 : -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return categories;
  }

  /// Creates the starting vocabulary the first time it is needed.
  ///
  /// Any category name already present on a transaction is imported too, so
  /// nothing recorded before this existed is lost or silently rewritten.
  static Future<List<ExpenseCategory>> ensureSeeded() async {
    final existing = await getOnce();
    if (existing.isNotEmpty) {
      return existing;
    }

    final now = DateTime.now();
    final batch = _firestore.batch();
    final seen = <String>{};

    for (final category in ExpenseCategory.defaults(now)) {
      seen.add(category.name.toLowerCase());
      batch.set(_collection().doc(), category.toMap());
    }

    // Import whatever the old free-form entries used.
    final transactions = await UserDataService.getTransactionsOnce();
    final legacy = <String, bool>{};
    for (final transaction in transactions) {
      final name = transaction.category.trim();
      if (name.isEmpty || seen.contains(name.toLowerCase())) continue;
      // If a name appears on both directions, treat it as usable by either.
      legacy.update(
        name,
        (value) => value == transaction.isExpense ? value : value,
        ifAbsent: () => transaction.isExpense,
      );
    }

    for (final entry in legacy.entries) {
      batch.set(
        _collection().doc(),
        ExpenseCategory(
          id: '',
          name: entry.key,
          kind: entry.value ? CategoryKind.expense : CategoryKind.income,
          iconKey: CategoryIcons.suggestFor(entry.key),
          colorIndex: entry.key.hashCode.abs() % 12,
          createdAt: now,
        ).toMap(),
      );
    }

    await batch.commit();
    return getOnce();
  }

  static Future<ExpenseCategory> create({
    required String name,
    required CategoryKind kind,
    String? iconKey,
    int? colorIndex,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('A category needs a name.');
    }

    final existing = await getOnce();
    final clash = existing.where(
      (category) => category.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (clash.isNotEmpty) {
      return clash.first;
    }

    final category = ExpenseCategory(
      id: '',
      name: trimmed,
      kind: kind,
      iconKey: iconKey ?? CategoryIcons.suggestFor(trimmed),
      colorIndex: colorIndex ?? existing.length % 12,
      createdAt: DateTime.now(),
    );

    final doc = _collection().doc();
    await doc.set(category.toMap());
    return ExpenseCategory.fromMap(doc.id, category.toMap());
  }

  static Future<void> update(ExpenseCategory category) async {
    await _collection().doc(category.id).set(category.toMap());
  }

  /// Renames a category and every transaction filed under the old name.
  static Future<int> rename(ExpenseCategory category, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == category.name) {
      return 0;
    }

    await update(category.copyWith(name: trimmed));
    return _rewriteCategoryName(from: category.name, to: trimmed);
  }

  /// Moves everything in [from] into [into], then removes [from].
  ///
  /// This is the cleanup for vocabularies that already fragmented.
  static Future<int> merge({
    required ExpenseCategory from,
    required ExpenseCategory into,
  }) async {
    if (from.id == into.id) {
      return 0;
    }

    final moved = await _rewriteCategoryName(from: from.name, to: into.name);
    await _collection().doc(from.id).delete();
    return moved;
  }

  /// Deletes a category, reassigning its transactions to the fallback.
  static Future<int> delete(ExpenseCategory category) async {
    if (category.isFallback) {
      throw StateError('The fallback category cannot be deleted.');
    }

    final moved = await _rewriteCategoryName(
      from: category.name,
      to: ExpenseCategory.fallbackName,
    );
    await _collection().doc(category.id).delete();
    return moved;
  }

  /// Points every transaction using [from] at [to]. Returns how many moved.
  static Future<int> _rewriteCategoryName({
    required String from,
    required String to,
  }) async {
    final snapshot = await _transactions()
        .where('category', isEqualTo: from)
        .get();
    if (snapshot.docs.isEmpty) {
      return 0;
    }

    var written = 0;
    var batch = _firestore.batch();
    var pending = 0;

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'category': to});
      pending++;
      written++;
      if (pending >= _batchLimit) {
        await batch.commit();
        batch = _firestore.batch();
        pending = 0;
      }
    }

    if (pending > 0) {
      await batch.commit();
    }
    return written;
  }

  /// How many transactions and how much money sit in each category name.
  static Map<String, CategoryUsage> usage(List<ExpenseModel> transactions) {
    final usage = <String, CategoryUsage>{};
    for (final transaction in transactions) {
      final key = transaction.category.trim();
      if (key.isEmpty) continue;
      final current = usage[key] ?? const CategoryUsage();
      usage[key] = CategoryUsage(
        count: current.count + 1,
        paisa: current.paisa + transaction.amountPaisa,
      );
    }
    return usage;
  }

  /// Finds categories that look like duplicates of each other.
  ///
  /// Uses the same matcher the entry paths use, so what it flags is exactly
  /// what would have been folded together had the rules existed earlier.
  ///
  /// [usage] decides which side survives when neither is a seeded category.
  static List<DuplicateSuggestion> findDuplicates(
    List<ExpenseCategory> categories, {
    Map<String, CategoryUsage> usage = const {},
  }) {
    final suggestions = <DuplicateSuggestion>[];

    // Only the disappearing side is locked. Locking the surviving side too
    // meant that once "Food - Miscellaneous" claimed "Food & Dining", a second
    // duplicate like "Food - Restaurant" could no longer fold into it and was
    // silently left behind.
    final absorbed = <String>{};

    for (final candidate in categories) {
      if (candidate.isFallback || absorbed.contains(candidate.id)) continue;

      final others = categories
          .where(
            (other) =>
                other.id != candidate.id &&
                !other.isFallback &&
                !absorbed.contains(other.id),
          )
          .toList();
      if (others.isEmpty) continue;

      final match = CategoryMatcher.match(
        rawName: candidate.name,
        categories: others,
        isExpense: candidate.kind != CategoryKind.income,
      );

      final target = match.category;
      if (target == null || match.isNew) continue;

      final ordered = _orderMerge(candidate, target, usage);
      if (absorbed.contains(ordered.from.id)) continue;

      absorbed.add(ordered.from.id);
      suggestions.add(
        DuplicateSuggestion(
          from: ordered.from,
          into: ordered.into,
          reason: match.reason,
        ),
      );
    }

    return suggestions;
  }

  /// Decides which of two duplicates survives.
  ///
  /// Without this the direction came from list order, which proposed folding
  /// the tidy seeded "Shopping" into the improvised "Shopping - Clothes" —
  /// exactly backwards.
  static ({ExpenseCategory from, ExpenseCategory into}) _orderMerge(
    ExpenseCategory a,
    ExpenseCategory b,
    Map<String, CategoryUsage> usage,
  ) {
    // A seeded category is the canonical name; keep it.
    if (a.isSystem != b.isSystem) {
      return a.isSystem ? (from: b, into: a) : (from: a, into: b);
    }

    // Otherwise keep whichever is actually being used, so the merge moves the
    // fewest transactions.
    final usedA = usage[a.name]?.count ?? 0;
    final usedB = usage[b.name]?.count ?? 0;
    if (usedA != usedB) {
      return usedA > usedB ? (from: b, into: a) : (from: a, into: b);
    }

    // Last resort: the shorter name is usually the cleaner one.
    return a.name.length <= b.name.length
        ? (from: b, into: a)
        : (from: a, into: b);
  }
}

class CategoryUsage {
  final int count;
  final int paisa;

  const CategoryUsage({this.count = 0, this.paisa = 0});
}

class DuplicateSuggestion {
  final ExpenseCategory from;
  final ExpenseCategory into;
  final CategoryMatchReason reason;

  const DuplicateSuggestion({
    required this.from,
    required this.into,
    required this.reason,
  });
}
