import '../models/expense_category.dart';

/// How a proposed category name was resolved.
enum CategoryMatchReason {
  /// Same name, ignoring case, punctuation and spacing.
  exact,

  /// A known synonym, e.g. "restaurant" for Food & Dining.
  alias,

  /// Close enough by spelling or shared words, e.g. "Foods" for Food & Dining.
  similar,

  /// Nothing matched; this name would be a new category.
  novel,
}

class CategoryMatch {
  /// The category to reuse, or null when [reason] is novel.
  final ExpenseCategory? category;

  /// Cleaned-up name to create, set only when [reason] is novel.
  final String? proposedName;

  final CategoryMatchReason reason;

  const CategoryMatch({
    this.category,
    this.proposedName,
    required this.reason,
  });

  bool get isNew => reason == CategoryMatchReason.novel;

  String get resolvedName => category?.name ?? proposedName ?? ExpenseCategory.fallbackName;
}

/// Resolves a free-text category name against the user's existing vocabulary.
///
/// The assistant used to store whatever string the model produced, with no
/// check against what the user already had. That is how "Food - Restaurant"
/// and "Food - Miscellaneous" became two categories for one kind of spending.
/// This runs locally, so it holds even when the model ignores instructions.
class CategoryMatcher {
  const CategoryMatcher._();

  /// Words that mean the same thing as one of the seeded categories.
  ///
  /// Keys are normalised tokens; values are canonical category names.
  static const _aliases = <String, String>{
    // Food
    'food': 'Food & Dining',
    'foods': 'Food & Dining',
    'dining': 'Food & Dining',
    'restaurant': 'Food & Dining',
    'restaurants': 'Food & Dining',
    'cafe': 'Food & Dining',
    'coffee': 'Food & Dining',
    'tea': 'Food & Dining',
    'lunch': 'Food & Dining',
    'dinner': 'Food & Dining',
    'breakfast': 'Food & Dining',
    'snack': 'Food & Dining',
    'snacks': 'Food & Dining',
    'khana': 'Food & Dining',
    // Groceries
    'grocery': 'Groceries',
    'groceries': 'Groceries',
    'supermarket': 'Groceries',
    'vegetables': 'Groceries',
    'vegetable': 'Groceries',
    'kirana': 'Groceries',
    // Transport
    'transport': 'Transport',
    'transportation': 'Transport',
    'travel': 'Transport',
    'taxi': 'Transport',
    'bus': 'Transport',
    'uber': 'Transport',
    'pathao': 'Transport',
    'fuel': 'Transport',
    'petrol': 'Transport',
    'flight': 'Transport',
    // Shopping
    'shopping': 'Shopping',
    'clothes': 'Shopping',
    'clothing': 'Shopping',
    'electronics': 'Shopping',
    // Bills
    'bill': 'Bills & Utilities',
    'bills': 'Bills & Utilities',
    'utility': 'Bills & Utilities',
    'utilities': 'Bills & Utilities',
    'electricity': 'Bills & Utilities',
    'water': 'Bills & Utilities',
    'internet': 'Bills & Utilities',
    'wifi': 'Bills & Utilities',
    'recharge': 'Bills & Utilities',
    'emi': 'Bills & Utilities',
    // Rent
    'rent': 'Rent',
    'housing': 'Rent',
    // Health
    'health': 'Health',
    'medical': 'Health',
    'medicine': 'Health',
    'hospital': 'Health',
    'doctor': 'Health',
    'pharmacy': 'Health',
    // Education
    'education': 'Education',
    'school': 'Education',
    'college': 'Education',
    'tuition': 'Education',
    'course': 'Education',
    'books': 'Education',
    // Entertainment
    'entertainment': 'Entertainment',
    'movie': 'Entertainment',
    'movies': 'Entertainment',
    'games': 'Entertainment',
    'gaming': 'Entertainment',
    'subscription': 'Entertainment',
    'netflix': 'Entertainment',
    // Personal
    'personal': 'Personal',
    'cash': 'Personal',
    'misc': 'Personal',
    'miscellaneous': 'Personal',
    // Income
    'salary': 'Salary',
    'payroll': 'Salary',
    'paycheck': 'Salary',
    'wage': 'Salary',
    'wages': 'Salary',
    'business': 'Business',
    'freelance': 'Freelance',
    'freelancing': 'Freelance',
    'contract': 'Freelance',
    'family': 'Family & Gifts',
    'gift': 'Family & Gifts',
    'gifts': 'Family & Gifts',
    'mom': 'Family & Gifts',
    'dad': 'Family & Gifts',
    'parents': 'Family & Gifts',
    'investment': 'Investments',
    'investments': 'Investments',
    'dividend': 'Investments',
    'interest': 'Investments',
    'refund': 'Refunds',
    'refunds': 'Refunds',
    'reimbursement': 'Refunds',
    'cashback': 'Refunds',
  };

  /// Tokens that carry no meaning for matching.
  static const _stopWords = {'and', 'the', 'of', 'for', 'a', 'an', 'to', 'my'};

  /// Minimum whole-string similarity to treat two names as the same.
  static const _similarityThreshold = 0.82;

  /// Minimum shared-token overlap to treat two names as the same.
  static const _overlapThreshold = 0.6;

  /// Finds the best home for [rawName] among [categories].
  ///
  /// [isExpense] filters to categories that accept that direction, so an
  /// expense can never be filed under an income-only category.
  static CategoryMatch match({
    required String rawName,
    required List<ExpenseCategory> categories,
    required bool isExpense,
  }) {
    final usable = categories
        .where((category) => category.kind.allows(isExpense: isExpense))
        .toList();

    final cleaned = _clean(rawName);
    final normalized = _normalize(cleaned);
    // Punctuation-only input such as "!!!" is not blank, but it carries no
    // name — without this it would be created as a category called "!!!".
    if (cleaned.isEmpty || normalized.isEmpty) {
      return _fallback(usable);
    }

    // 1. Exact, ignoring case, punctuation and spacing.
    for (final category in usable) {
      if (_normalize(category.name) == normalized) {
        return CategoryMatch(
          category: category,
          reason: CategoryMatchReason.exact,
        );
      }
    }

    // 2. Known synonym. "Food - Restaurant" and "Food - Miscellaneous" both
    //    carry the token 'food', so both land on Food & Dining.
    final tokens = _tokens(normalized);
    for (final token in tokens) {
      final canonical = _aliases[token];
      if (canonical == null) continue;
      for (final category in usable) {
        if (_normalize(category.name) == _normalize(canonical)) {
          return CategoryMatch(
            category: category,
            reason: CategoryMatchReason.alias,
          );
        }
      }
    }

    // 3. Close spelling or strong word overlap: "Foods", "Food and Dining".
    ExpenseCategory? best;
    var bestScore = 0.0;
    for (final category in usable) {
      final score = _score(normalized, tokens, category.name);
      if (score > bestScore) {
        bestScore = score;
        best = category;
      }
    }
    if (best != null && bestScore >= 1.0) {
      return CategoryMatch(
        category: best,
        reason: CategoryMatchReason.similar,
      );
    }

    // 4. Genuinely new.
    return CategoryMatch(
      proposedName: _titleCase(cleaned),
      reason: CategoryMatchReason.novel,
    );
  }

  static CategoryMatch _fallback(List<ExpenseCategory> usable) {
    for (final category in usable) {
      if (category.isFallback) {
        return CategoryMatch(
          category: category,
          reason: CategoryMatchReason.exact,
        );
      }
    }
    return const CategoryMatch(
      proposedName: ExpenseCategory.fallbackName,
      reason: CategoryMatchReason.novel,
    );
  }

  /// Returns >= 1.0 when the two names should be treated as the same.
  static double _score(
    String normalized,
    Set<String> tokens,
    String candidateName,
  ) {
    final candidate = _normalize(candidateName);
    final candidateTokens = _tokens(candidate);

    final similarity = _similarity(normalized, candidate);
    if (similarity >= _similarityThreshold) {
      return 1.0 + similarity;
    }

    if (tokens.isEmpty || candidateTokens.isEmpty) {
      return 0;
    }
    final shared = tokens.intersection(candidateTokens).length;
    if (shared == 0) {
      return 0;
    }
    final overlap =
        shared / (tokens.length < candidateTokens.length
            ? tokens.length
            : candidateTokens.length);
    return overlap >= _overlapThreshold ? 1.0 + overlap : overlap;
  }

  /// Levenshtein distance expressed as a 0..1 similarity.
  static double _similarity(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;

    final distance = _levenshtein(a, b);
    final longest = a.length > b.length ? a.length : b.length;
    return 1 - (distance / longest);
  }

  static int _levenshtein(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (index) => index);
    var current = List<int>.filled(b.length + 1, 0);

    for (var i = 0; i < a.length; i++) {
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        final deletion = previous[j + 1] + 1;
        final insertion = current[j] + 1;
        final substitution = previous[j] + cost;
        var best = deletion < insertion ? deletion : insertion;
        if (substitution < best) best = substitution;
        current[j + 1] = best;
      }
      final swap = previous;
      previous = current;
      current = swap;
    }

    return previous[b.length];
  }

  /// Trims and collapses whitespace without altering the wording.
  static String _clean(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Lowercases and reduces punctuation to single spaces, so
  /// "Food & Dining", "food-dining" and "Food  Dining" all compare equal.
  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static Set<String> _tokens(String normalized) {
    return normalized
        .split(' ')
        .where((token) => token.isNotEmpty && !_stopWords.contains(token))
        .toSet();
  }

  static String _titleCase(String value) {
    return value
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          if (word.length == 1) return word.toUpperCase();
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ');
  }
}
