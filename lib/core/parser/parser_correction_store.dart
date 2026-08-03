import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'transaction_parser_service.dart';

class ParserCorrectionStore {
  static const _correctionsKey = 'parser_corrections_v1';
  static const _promotedRulesKey = 'parser_promoted_rules_v1';

  static Future<void> logCorrection({
    required String rawInput,
    required ParsedTransaction corrected,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(_correctionsKey) ?? <String>[];

    entries.add(
      jsonEncode({
        'input': rawInput.trim(),
        'type': corrected.type.name,
        'confidence': corrected.confidence,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );

    if (entries.length > 200) {
      entries.removeRange(0, entries.length - 200);
    }
    await prefs.setStringList(_correctionsKey, entries);

    final pattern = _normalizePattern(rawInput);
    final count = entries.where((entry) {
      final decoded = jsonDecode(entry) as Map<String, dynamic>;
      return (decoded['input'] as String?)?.trim().toLowerCase() == pattern;
    }).length;

    if (count >= 3) {
      await _promoteRule(pattern: pattern, type: corrected.type.name);
    }
  }

  static Future<List<Map<String, dynamic>>> promotedRules() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_promotedRulesKey) ?? <String>[];
    return values
        .map((value) => jsonDecode(value) as Map<String, dynamic>)
        .toList();
  }

  static Future<void> _promoteRule({
    required String pattern,
    required String type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await promotedRules();
    final alreadyExists = existing.any((rule) => rule['pattern'] == pattern);
    if (alreadyExists) {
      return;
    }

    existing.add({
      'pattern': pattern,
      'type': type,
      'confidence': 0.9,
      'reason': 'learned from user correction',
    });

    await prefs.setStringList(
      _promotedRulesKey,
      existing.map((rule) => jsonEncode(rule)).toList(),
    );
  }

  static String _normalizePattern(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
