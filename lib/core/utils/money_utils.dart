class MoneyUtils {
  const MoneyUtils._();

  static int parseToPaisa(String input) {
    final normalized = input.trim().replaceAll(',', '');
    final amount = double.parse(normalized);
    return (amount * 100).round();
  }

  static int amountToPaisa(double amount) {
    return (amount * 100).round();
  }

  static double paisaToAmount(int paisa) {
    return paisa / 100;
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

    return '$sign Rs. $rupeesText$decimalText';
  }

  static String formatAmount(double amount) {
    return formatPaisa(amountToPaisa(amount));
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
