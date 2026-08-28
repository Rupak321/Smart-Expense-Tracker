import 'package:flutter/foundation.dart';

import '../../services/user_settings_service.dart';
import '../models/app_currency.dart';
import '../utils/money_utils.dart';

/// Owns the currency amounts are displayed in.
///
/// Nothing is converted. Changing this changes the symbol and the digit
/// grouping only, because the app never held an exchange rate and inventing
/// one would silently restate every figure the user recorded.
class CurrencyController {
  const CurrencyController._();

  static final ValueNotifier<AppCurrency> currency = ValueNotifier(
    AppCurrency.nepaleseRupee,
  );

  static Future<void> load() async {
    final code = await UserSettingsService.loadCurrencyCode();
    final resolved = AppCurrency.fromCode(code);
    currency.value = resolved;
    MoneyUtils.currency = resolved;
  }

  static Future<void> set(AppCurrency next) async {
    if (currency.value == next) return;

    currency.value = next;
    MoneyUtils.currency = next;
    await UserSettingsService.saveCurrencyCode(next.code);
  }
}
