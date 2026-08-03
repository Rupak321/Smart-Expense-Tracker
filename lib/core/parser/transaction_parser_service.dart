import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'category_taxonomy.dart';

class TransactionParserService {
  TransactionParserService({this.rulesAssetPath = 'assets/parser_rules.json'});

  final String rulesAssetPath;
  Map<String, dynamic>? _rules;

  Future<ParsedTransaction> parse(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) {
      return ParsedTransaction.empty();
    }

    final normalized = _normalizeInput(input);
    final ruleResult = await _applyRuleBasedClassifier(normalized);
    if (ruleResult.confidence >= 0.8) {
      return ruleResult;
    }

    return _fallbackParse(normalized, source: 'fallback');
  }

  Future<ParsedTransaction> _applyRuleBasedClassifier(String input) async {
    final rules = await _loadRules();
    final amount = _extractAmount(input);
    final directionFacts = _collectDirectionFacts(input, rules);
    final category = _categorize(input, rules);

    if (directionFacts.type != null) {
      final type = directionFacts.type == 'income'
          ? TransactionType.income
          : TransactionType.expense;
      final confidence = directionFacts.confidence;
      return ParsedTransaction(
        schemaVersion: 1,
        action: 'add',
        type: type,
        amount: amount,
        title: _buildTitle(input, type),
        category: category,
        confidence: confidence,
        needsClarification: false,
        reason: directionFacts.reason,
        source: 'rule',
      );
    }

    return ParsedTransaction(
      schemaVersion: 1,
      action: 'add',
      type: TransactionType.unknown,
      amount: amount,
      title: _buildTitle(input, TransactionType.unknown),
      category: category,
      confidence: 0.35,
      needsClarification: true,
      reason: 'Direction could not be determined confidently.',
      source: 'fallback',
    );
  }

  String _normalizeInput(String input) {
    var normalized = input.toLowerCase().trim();
    normalized = normalized.replaceAllMapped(RegExp(r'[\u0660-\u0669]'), (match) {
      final value = match.group(0)!;
      return '${value.codeUnitAt(0) - 0x0660}';
    });
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\b(rs?\.?|₹)\s*'), '');
    normalized = normalized.replaceAll(RegExp(r'\b(lakh|lac)\b'), ' lakh');
    normalized = normalized.replaceAllMapped(RegExp(r'\b(\d+(?:\.\d+)?)\s*k\b'), (match) {
      final value = double.parse(match.group(1)!);
      return '${(value * 1000).toInt()}';
    });
    normalized = normalized.replaceAllMapped(RegExp(r'\b(\d+(?:\.\d+)?)\s*l\b'), (match) {
      final value = double.parse(match.group(1)!);
      return '${(value * 100000).toInt()}';
    });
    normalized = normalized.replaceAllMapped(RegExp(r'\b(\d+(?:\.\d+)?)\s*lakh\b'), (match) {
      final value = double.parse(match.group(1)!);
      return '${(value * 100000).toInt()}';
    });
    normalized = normalized.replaceAllMapped(RegExp(r'\b(\d+)\s*(?:,|\.)\s*(\d{3})(?=\b|\D)'), (match) {
      return '${match.group(1)}${match.group(2)}';
    });
    normalized = normalized.replaceAllMapped(RegExp(r'\b(\d+)(?:\.(\d+))?\b'), (match) {
      return match.group(0)!;
    });
    return normalized;
  }

  double _extractAmount(String input) {
    final normalized = input.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (normalized.isEmpty) {
      return 0;
    }
    final amount = double.tryParse(normalized);
    return amount ?? 0;
  }

  _DirectionFacts _collectDirectionFacts(String input, Map<String, dynamic> rules) {
    final aliases = (rules['localeAliases'] as Map<String, dynamic>?) ?? const {};
    final aliasesMap = <String, String>{};
    for (final entry in aliases.entries) {
      final values = entry.value as List<dynamic>? ?? const <dynamic>[];
      for (final value in values) {
        aliasesMap[value.toString()] = entry.key;
      }
    }

    final relationPatterns = (rules['relationPatterns'] as List<dynamic>? ?? const []);
    for (final relation in relationPatterns) {
      final map = relation as Map<String, dynamic>;
      final pattern = map['pattern'] as String?;
      final direction = map['direction'] as String?;
      final confidence = (map['confidence'] as num?)?.toDouble() ?? 0.8;
      final regex = RegExp(pattern!, caseSensitive: false);
      if (regex.hasMatch(input)) {
        return _DirectionFacts(
          type: direction,
          confidence: confidence,
          reason: map['reason']?.toString() ?? 'Matched relation cue.',
        );
      }
    }

    final verbPairs = (rules['verbDirectionPairs'] as List<dynamic>? ?? const []);
    for (final pair in verbPairs) {
      final map = pair as Map<String, dynamic>;
      final pattern = map['pattern'] as String?;
      final direction = map['direction'] as String?;
      final confidence = (map['confidence'] as num?)?.toDouble() ?? 0.8;
      final regex = RegExp(pattern!, caseSensitive: false);
      if (regex.hasMatch(input)) {
        return _DirectionFacts(
          type: direction,
          confidence: confidence,
          reason: map['reason']?.toString() ?? 'Matched rule-based direction cue.',
        );
      }
    }

    for (final relation in relationPatterns) {
      final map = relation as Map<String, dynamic>;
      final pattern = map['pattern'] as String?;
      final direction = map['direction'] as String?;
      final confidence = (map['confidence'] as num?)?.toDouble() ?? 0.8;
      final regex = RegExp(pattern!, caseSensitive: false);
      if (regex.hasMatch(input)) {
        return _DirectionFacts(
          type: direction,
          confidence: confidence,
          reason: map['reason']?.toString() ?? 'Matched relation cue.',
        );
      }
    }

    final actorAliases = (rules['actorAliases'] as Map<String, dynamic>?) ?? const {};
    for (final entry in actorAliases.entries) {
      final alias = entry.key;
      final normalizedAlias = alias.toLowerCase();
      if (input.contains(normalizedAlias)) {
        final set = entry.value as List<dynamic>? ?? const <dynamic>[];
        final target = set.firstOrNull?.toString() ?? '';
        if (target.isNotEmpty) {
          return _DirectionFacts(
            type: target.contains('income') ? 'income' : 'expense',
            confidence: 0.7,
            reason: 'Matched actor alias.',
          );
        }
      }
    }

    return const _DirectionFacts();
  }

  String _categorize(String input, Map<String, dynamic> rules) {
    final categories = (rules['categories'] as List<dynamic>? ?? const []);
    for (final entry in categories) {
      final map = entry as Map<String, dynamic>;
      final pattern = map['pattern'] as String?;
      if (pattern != null && RegExp(pattern, caseSensitive: false).hasMatch(input)) {
        return map['category']?.toString() ?? 'Other';
      }
    }
    return CategoryTaxonomy.normalize(input);
  }

  ParsedTransaction _fallbackParse(String input, {required String source}) {
    final amount = _extractAmount(input);
    if (amount <= 0) {
      return ParsedTransaction(
        schemaVersion: 1,
        action: 'add',
        type: TransactionType.unknown,
        amount: 0,
        title: _buildTitle(input, TransactionType.unknown),
        category: 'Other',
        confidence: 0.2,
        needsClarification: true,
        reason: 'No amount found.',
        source: source,
      );
    }

    final lower = input.toLowerCase();
    final isIncome = lower.contains('from') || lower.contains('received') || lower.contains('gave me') || lower.contains('diyo');
    final type = isIncome ? TransactionType.income : TransactionType.expense;
    return ParsedTransaction(
      schemaVersion: 1,
      action: 'add',
      type: type,
      amount: amount,
      title: _buildTitle(input, type),
      category: 'Other',
      confidence: 0.4,
      needsClarification: true,
      reason: 'Used local fallback parsing.',
      source: source,
    );
  }

  String _buildTitle(String input, TransactionType type) {
    final sanitized = input.replaceAll(RegExp(r'\d+'), '').trim();
    final title = sanitized.isEmpty ? 'Parsed transaction' : sanitized;
    if (title.isEmpty) {
      return 'Parsed transaction';
    }
    return title[0].toUpperCase() + title.substring(1);
  }

  Future<Map<String, dynamic>> _loadRules() async {
    if (_rules != null) {
      return _rules!;
    }
    final content = await rootBundle.loadString(rulesAssetPath);
    final decoded = jsonDecode(content);
    _rules = decoded as Map<String, dynamic>;
    return _rules!;
  }
}

class ParsedTransaction {
  const ParsedTransaction({
    required this.schemaVersion,
    required this.action,
    required this.type,
    required this.amount,
    required this.title,
    required this.category,
    required this.confidence,
    required this.needsClarification,
    required this.reason,
    required this.source,
  });

  final int schemaVersion;
  final String action;
  final TransactionType type;
  final double amount;
  final String title;
  final String category;
  final double confidence;
  final bool needsClarification;
  final String reason;
  final String source;

  factory ParsedTransaction.empty() {
    return const ParsedTransaction(
      schemaVersion: 1,
      action: 'add',
      type: TransactionType.unknown,
      amount: 0,
      title: '',
      category: 'Other',
      confidence: 0,
      needsClarification: true,
      reason: 'Empty input.',
      source: 'fallback',
    );
  }
}

enum TransactionType { income, expense, unknown }

class _DirectionFacts {
  const _DirectionFacts({this.type, this.confidence = 0.0, this.reason = ''});

  final String? type;
  final double confidence;
  final String reason;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
