class MoneyUtils {
  const MoneyUtils._();

  static int parseToPaisa(String input) {
    final normalized = input.trim().replaceAll(',', '');
    final isNegative = normalized.startsWith('-');
    final raw = normalized.replaceFirst('-', '');

    final parts = raw.split('.');
    final whole = int.tryParse(parts[0]) ?? 0;
    final fraction = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
    final cents = int.tryParse(fraction.substring(0, 2)) ?? 0;
    final paisa = whole * 100 + cents;

    return isNegative ? -paisa : paisa;
  }

  static int amountToPaisa(double amount) {
    final normalized = amount.toStringAsFixed(2);
    final isNegative = normalized.startsWith('-');
    final raw = normalized.replaceFirst('-', '');
    final parts = raw.split('.');
    final whole = int.tryParse(parts[0]) ?? 0;
    final fraction = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
    final cents = int.tryParse(fraction.substring(0, 2)) ?? 0;
    final paisa = whole * 100 + cents;

    return isNegative ? -paisa : paisa;
  }

  static double paisaToAmount(int paisa) {
    return paisa / 100;
  }

  /// The amount as the user would type it, for prefilling an edit field.
  ///
  /// No symbol and no separators, since this value is parsed straight back by
  /// [parseToPaisa]. Whole rupees drop the ".00" so the field reads "500"
  /// rather than "500.00".
  static String editableAmount(double amount) {
    final paisa = amountToPaisa(amount);
    final rupees = paisa ~/ 100;
    final cents = paisa % 100;
    if (cents == 0) {
      return rupees.toString();
    }
    return '$rupees.${cents.toString().padLeft(2, '0')}';
  }

  static String? validateAmount(String? input) {
    if (input == null || input.trim().isEmpty) {
      return 'Please enter an amount';
    }

    final normalized = input.trim().replaceAll(',', '');
    final amount = double.tryParse(normalized);
    if (amount == null) {
      return 'Please enter a valid number';
    }
    if (amount <= 0) {
      return 'Amount must be greater than zero';
    }
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) {
      return 'Use up to 2 decimal places';
    }

    return null;
  }

  static String formatPaisa(int paisa) {
    final isNegative = paisa < 0;
    final absolute = paisa.abs();
    final rupees = absolute ~/ 100;
    final cents = absolute % 100;
    final rupeesText = _formatWholeNumber(rupees);
    final decimalText = cents == 0
        ? ''
        : '.${cents.toString().padLeft(2, '0')}';
    final sign = isNegative ? '-' : '';

    return '${sign}Rs. $rupeesText$decimalText';
  }

  static String formatAmount(double amount) {
    return formatPaisa(amountToPaisa(amount));
  }

  /// Short form for axis ticks and tight badges: `Rs. 12.4k`, `Rs. 1.2L`.
  static String formatCompactPaisa(int paisa) {
    final isNegative = paisa < 0;
    final rupees = paisa.abs() / 100;
    final sign = isNegative ? '-' : '';

    if (rupees >= 10000000) {
      return '${sign}Rs. ${(rupees / 10000000).toStringAsFixed(1)}Cr';
    }
    if (rupees >= 100000) {
      return '${sign}Rs. ${(rupees / 100000).toStringAsFixed(1)}L';
    }
    if (rupees >= 1000) {
      return '${sign}Rs. ${(rupees / 1000).toStringAsFixed(1)}k';
    }
    return '${sign}Rs. ${rupees.round()}';
  }

  static String _formatWholeNumber(int value) {
    final source = value.toString();
    final buffer = StringBuffer();

    for (var index = 0; index < source.length; index++) {
      final remaining = source.length - index;
      buffer.write(source[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }

    return buffer.toString();
  }
}
