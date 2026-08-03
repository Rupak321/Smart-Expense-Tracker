class CategoryTaxonomy {
  static const List<String> canonicalCategories = <String>[
    'Income - Salary',
    'Income - Family Support',
    'Food & Dining',
    'Bills & Utilities',
    'Travel',
    'Shopping',
    'Other',
  ];

  static String normalize(String? rawCategory) {
    final value = (rawCategory ?? '').trim();
    if (value.isEmpty) {
      return 'Other';
    }

    final normalized = value.toLowerCase();
    if (normalized.contains('salary') || normalized.contains('income')) {
      return 'Income - Salary';
    }
    if (normalized.contains('family') || normalized.contains('mom') || normalized.contains('dad') || normalized.contains('aama') || normalized.contains('buwa')) {
      return 'Income - Family Support';
    }
    if (normalized.contains('food') || normalized.contains('restaurant') || normalized.contains('dining') || normalized.contains('lunch') || normalized.contains('dinner')) {
      return 'Food & Dining';
    }
    if (normalized.contains('bill') || normalized.contains('utility') || normalized.contains('rent') || normalized.contains('emi') || normalized.contains('electric') || normalized.contains('water') || normalized.contains('internet')) {
      return 'Bills & Utilities';
    }
    if (normalized.contains('travel') || normalized.contains('transport') || normalized.contains('bus') || normalized.contains('taxi') || normalized.contains('fuel') || normalized.contains('uber')) {
      return 'Travel';
    }
    if (normalized.contains('shop') || normalized.contains('grocery') || normalized.contains('market')) {
      return 'Shopping';
    }
    return 'Other';
  }
}
