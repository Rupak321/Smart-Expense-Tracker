import '../models/app_currency.dart';

class MoneyUtils {
  const MoneyUtils._();

  /// The currency every formatter here renders in.
  ///
  /// Deliberately a static rather than something threaded through hundreds of
  /// call sites: formatting is a display concern and the app shows one
  /// currency at a time. CurrencyController owns setting it.
  static AppCurrency currency = AppCurrency.nepaleseRupee;

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
    final rupeesText = currency.grouping.format(rupees);
    final decimalText = cents == 0
        ? ''
        : '.${cents.toString().padLeft(2, '0')}';
    final sign = isNegative ? '-' : '';

    return '$sign${currency.withSymbol('$rupeesText$decimalText')}';
  }

  static String formatAmount(double amount) {
    return formatPaisa(amountToPaisa(amount));
  }

  /// Short form for axis ticks and tight badges: `Rs. 12.4k`, `Rs. 1.2L`.
  ///
  /// The units come from the currency, so a rupee amount reads in lakhs and
  /// crores while a dollar one reads in K, M and B.
  static String formatCompactPaisa(int paisa) {
    final isNegative = paisa < 0;
    final amount = paisa.abs() / 100;
    final sign = isNegative ? '-' : '';

    for (final unit in currency.compactUnits) {
      if (amount >= unit.value) {
        final scaled = (amount / unit.value).toStringAsFixed(1);
        return '$sign${currency.withSymbol('$scaled${unit.suffix}')}';
      }
    }
    return '$sign${currency.withSymbol('${amount.round()}')}';
  }
}
