/// How digits are grouped in large numbers.
enum DigitGrouping {
  /// Groups of three throughout: 8,538,550.
  western,

  /// The South Asian system: three digits, then twos. 85,38,550.
  ///
  /// This is what Nepal and India use, and what "lakh" and "crore" count. The
  /// app already spoke in lakhs and crores in its compact figures while
  /// spelling full amounts the western way, so the same number was grouped two
  /// different ways on the same screen.
  southAsian;

  String format(int value) {
    final source = value.toString();
    if (source.length <= 3) return source;

    if (this == DigitGrouping.western) {
      final buffer = StringBuffer();
      for (var index = 0; index < source.length; index++) {
        final remaining = source.length - index;
        buffer.write(source[index]);
        if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
      }
      return buffer.toString();
    }

    // South Asian: keep the last three together, then pair off the rest from
    // the right.
    final tail = source.substring(source.length - 3);
    var head = source.substring(0, source.length - 3);
    final groups = <String>[];
    while (head.length > 2) {
      groups.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) groups.insert(0, head);

    return '${groups.join(',')},$tail';
  }
}

/// A currency the app can display amounts in.
///
/// The Account screen offered a Currency row that said "coming soon" and did
/// nothing. Amounts were hard-coded to "Rs." throughout.
class AppCurrency {
  final String code;
  final String symbol;
  final String name;
  final DigitGrouping grouping;

  /// Short names for the compact form, largest first. Empty means the plain
  /// thousands/millions abbreviations are used instead.
  final List<({int value, String suffix})> compactUnits;

  const AppCurrency({
    required this.code,
    required this.symbol,
    required this.name,
    required this.grouping,
    this.compactUnits = const [],
  });

  static const nepaleseRupee = AppCurrency(
    code: 'NPR',
    symbol: 'Rs.',
    name: 'Nepalese Rupee',
    grouping: DigitGrouping.southAsian,
    compactUnits: [
      (value: 10000000, suffix: 'Cr'),
      (value: 100000, suffix: 'L'),
      (value: 1000, suffix: 'k'),
    ],
  );

  static const indianRupee = AppCurrency(
    code: 'INR',
    symbol: '₹',
    name: 'Indian Rupee',
    grouping: DigitGrouping.southAsian,
    compactUnits: [
      (value: 10000000, suffix: 'Cr'),
      (value: 100000, suffix: 'L'),
      (value: 1000, suffix: 'k'),
    ],
  );

  static const usDollar = AppCurrency(
    code: 'USD',
    symbol: r'$',
    name: 'US Dollar',
    grouping: DigitGrouping.western,
    compactUnits: [
      (value: 1000000000, suffix: 'B'),
      (value: 1000000, suffix: 'M'),
      (value: 1000, suffix: 'K'),
    ],
  );

  static const euro = AppCurrency(
    code: 'EUR',
    symbol: '€',
    name: 'Euro',
    grouping: DigitGrouping.western,
    compactUnits: [
      (value: 1000000000, suffix: 'B'),
      (value: 1000000, suffix: 'M'),
      (value: 1000, suffix: 'K'),
    ],
  );

  static const poundSterling = AppCurrency(
    code: 'GBP',
    symbol: '£',
    name: 'Pound Sterling',
    grouping: DigitGrouping.western,
    compactUnits: [
      (value: 1000000000, suffix: 'B'),
      (value: 1000000, suffix: 'M'),
      (value: 1000, suffix: 'K'),
    ],
  );

  static const supported = [
    nepaleseRupee,
    indianRupee,
    usDollar,
    euro,
    poundSterling,
  ];

  static AppCurrency fromCode(String? code) {
    return supported.firstWhere(
      (currency) => currency.code == code,
      orElse: () => nepaleseRupee,
    );
  }

  /// "Rs. 1,234" — a space after a word-like symbol, none after a glyph.
  ///
  /// "Rs.1,234" reads badly and "€ 12" is not how the symbol is written, so
  /// the separator follows the symbol rather than being fixed.
  String withSymbol(String amount) {
    final needsSpace = symbol.length > 1;
    return needsSpace ? '$symbol $amount' : '$symbol$amount';
  }

  @override
  bool operator ==(Object other) =>
      other is AppCurrency && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
