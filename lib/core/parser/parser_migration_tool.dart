import 'dart:convert';

class ParserMigrationTool {
  const ParserMigrationTool();

  List<Map<String, dynamic>> dryRun(List<Map<String, dynamic>> records) {
    return records.map((e) => {
      ...e,
      'reparsedType': _inferType(e['title']?.toString() ?? ''),
    }).toList();
  }

  String _inferType(String text) {
    final lowered = text.toLowerCase();
    if (lowered.contains('gave me') || lowered.contains('from mom') || lowered.contains('from dad')) {
      return 'income';
    }
    if (lowered.contains('gave mom') || lowered.contains('gave dad') || lowered.contains('to mom') || lowered.contains('to dad')) {
      return 'expense';
    }
    return 'unknown';
  }
}
