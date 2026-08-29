import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/models/financial_report.dart';
import '../core/utils/money_utils.dart';

/// Renders a [FinancialReport] as a designed multi-page PDF.
///
/// The previous export flattened the whole report to a single string, stripped
/// its markdown, collapsed every newline into a space and truncated it at 2,200
/// characters — then printed that one paragraph on a single page that silently
/// clipped anything taller. This builds real structure instead: a cover band,
/// KPI tiles, a category donut, tables, and page furniture.
class ReportPdfBuilder {
  const ReportPdfBuilder._();

  static const _brand = PdfColor.fromInt(0xFF2A9D8F);
  static const _brandDark = PdfColor.fromInt(0xFF1E7168);
  static const _ink = PdfColor.fromInt(0xFF16241F);
  static const _muted = PdfColor.fromInt(0xFF667571);
  static const _hairline = PdfColor.fromInt(0xFFDCE5E2);
  static const _tint = PdfColor.fromInt(0xFFF2F7F5);
  static const _positive = PdfColor.fromInt(0xFF1B8A5A);
  static const _negative = PdfColor.fromInt(0xFFD62828);

  /// Chart palette, mid-luminance so each slice stays distinct in colour and
  /// still separable when the page is printed in greyscale.
  static const _palette = <PdfColor>[
    PdfColor.fromInt(0xFFE76F51),
    PdfColor.fromInt(0xFF4EA8DE),
    PdfColor.fromInt(0xFFD4A017),
    PdfColor.fromInt(0xFF2A9D8F),
    PdfColor.fromInt(0xFFEF476F),
    PdfColor.fromInt(0xFF9B5DE5),
    PdfColor.fromInt(0xFF06D6A0),
    PdfColor.fromInt(0xFFF4A261),
    PdfColor.fromInt(0xFF64B5F6),
    PdfColor.fromInt(0xFF74C365),
  ];

  /// Typographic characters the built-in PDF fonts cannot draw, mapped to
  /// plain equivalents.
  ///
  /// The standard PDF fonts cover Latin-1 only. Anything outside it — an em
  /// dash, a bullet, the curly quotes a language model loves, a rupee sign —
  /// is rendered as a hollow box with a cross through it. The first export
  /// showed exactly that in the page footer.
  static const _substitutions = <String, String>{
    '—': '-', // em dash
    '–': '-', // en dash
    '•': '-', // bullet
    '·': '-', // middle dot
    '‘': "'", // left single quote
    '’': "'", // right single quote
    '“': '"', // left double quote
    '”': '"', // right double quote
    '…': '...', // ellipsis
    ' ': ' ', // non-breaking space
    '₹': 'Rs.', // rupee sign
    '→': '->',
    '×': 'x',
    '←': '<-',
    '≤': '<=',
    '≥': '>=',
  };

  /// Makes [value] safe to draw with the built-in fonts.
  ///
  /// Characters with no Latin-1 equivalent (Devanagari, CJK, emoji) are
  /// dropped rather than drawn as boxes. See the README note about bundling a
  /// Unicode font if those need to survive into the PDF.
  static String safeText(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final substitution = _substitutions[char];
      if (substitution != null) {
        buffer.write(substitution);
        continue;
      }
      if (rune == 0x0A) {
        buffer.write('\n');
        continue;
      }
      if (rune < 0x20) {
        buffer.write(' ');
        continue;
      }
      if (rune <= 0xFF) {
        buffer.write(char);
      }
    }
    final result = buffer.toString().trim();
    return result.isEmpty && value.trim().isNotEmpty ? '(unsupported)' : result;
  }

  static Future<Uint8List> build(FinancialReport report) async {
    final document = pw.Document(
      title: 'SmartExpense report - ${report.period.label}',
      author: 'SmartExpense',
      subject: 'Personal financial report',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 44),
        footer: (context) => _footer(context, report),
        build: (context) => [
          _coverBand(report),
          pw.SizedBox(height: 20),
          if (!report.hasData)
            _emptyNotice(report)
          else ...[
            _kpiRow(report),
            pw.SizedBox(height: 18),
            _comparisonLine(report),
            _sectionTitle('Where the money went'),
            _categorySection(report),
            if (report.months.length > 1) ...[
              _sectionTitle('Month by month'),
              _monthlyTable(report),
            ],
            if (report.topExpenses.isNotEmpty) ...[
              _sectionTitle('Largest expenses'),
              _transactionTable(report.topExpenses, isExpense: true),
            ],
            if (report.topIncome.isNotEmpty) ...[
              _sectionTitle('Largest income'),
              _transactionTable(report.topIncome, isExpense: false),
            ],
            if (report.observations.isNotEmpty) ...[
              _sectionTitle('Observations'),
              _observations(report),
            ],
            if (report.narrative != null) ...[
              _sectionTitle('Analysis'),
              ..._narrative(report.narrative!),
            ],
          ],
        ],
      ),
    );

    return document.save();
  }

  // ---------------------------------------------------------------- header

  static pw.Widget _coverBand(FinancialReport report) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(22),
      decoration: const pw.BoxDecoration(
        gradient: pw.LinearGradient(
          begin: pw.Alignment.centerLeft,
          end: pw.Alignment.centerRight,
          colors: [_brandDark, _brand],
        ),
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SMARTEXPENSE',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9,
                    letterSpacing: 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Financial Report',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 26,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  safeText(report.period.label),
                  style: const pw.TextStyle(
                    color: PdfColor.fromInt(0xFFD9F2EC),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _bandMeta('PERIOD', safeText(report.rangeLabel)),
              pw.SizedBox(height: 8),
              _bandMeta('GENERATED', _dateTime(report.generatedAt)),
              pw.SizedBox(height: 8),
              _bandMeta('TRANSACTIONS', '${report.transactionCount}'),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _bandMeta(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            color: const PdfColor.fromInt(0xFFA9DBD1),
            fontSize: 7,
            letterSpacing: 1.1,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          safeText(value),
          style: const pw.TextStyle(color: PdfColors.white, fontSize: 9.5),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- kpis

  static pw.Widget _kpiRow(FinancialReport report) {
    final rate = report.savingsRate;
    return pw.Row(
      children: [
        _kpiTile(
          'Income',
          MoneyUtils.formatPaisa(report.incomePaisa),
          '${report.incomeCount} entries',
          _positive,
        ),
        pw.SizedBox(width: 10),
        _kpiTile(
          'Spent',
          MoneyUtils.formatPaisa(report.expensePaisa),
          '${report.expenseCount} entries',
          _negative,
        ),
        pw.SizedBox(width: 10),
        _kpiTile(
          'Net',
          MoneyUtils.formatPaisa(report.netPaisa),
          report.netPaisa < 0 ? 'Overspent' : 'Kept',
          report.netPaisa < 0 ? _negative : _brand,
        ),
        pw.SizedBox(width: 10),
        _kpiTile(
          'Savings rate',
          rate == null ? '—' : '${(rate * 100).round()}%',
          rate == null ? 'No income recorded' : 'of income kept',
          rate == null
              ? _muted
              : rate < 0
              ? _negative
              : _brand,
        ),
      ],
    );
  }

  static pw.Widget _kpiTile(
    String label,
    String value,
    String caption,
    PdfColor accent,
  ) {
    return pw.Expanded(
      child: pw.Container(
        height: 76,
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: pw.BoxDecoration(
          color: _tint,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(9)),
          border: pw.Border.all(color: _hairline),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                color: _muted,
                fontSize: 7,
                letterSpacing: 0.9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                safeText(value),
                maxLines: 1,
                style: pw.TextStyle(
                  color: accent,
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              safeText(caption),
              maxLines: 1,
              style: const pw.TextStyle(color: _muted, fontSize: 7.5),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _comparisonLine(FinancialReport report) {
    final change = report.expenseChangeRatio;
    if (change == null) {
      return pw.SizedBox();
    }
    final up = change >= 0;
    final accent = up ? _negative : _positive;

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColor(accent.red, accent.green, accent.blue, 0.08),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            up ? 'UP' : 'DOWN',
            style: pw.TextStyle(
              color: accent,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              'Spending is ${up ? 'up' : 'down'} '
              '${(change.abs() * 100).round()}% versus the previous '
              '${report.period.label.toLowerCase()} '
              '(${MoneyUtils.formatPaisa(report.previousExpensePaisa ?? 0)} '
              'to ${MoneyUtils.formatPaisa(report.expensePaisa)}).',
              style: const pw.TextStyle(color: _ink, fontSize: 9.5),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- categories

  static pw.Widget _categorySection(FinancialReport report) {
    if (report.categories.isEmpty) {
      return _note('No spending recorded in this period.');
    }

    final visible = report.categories.take(8).toList();

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 150,
          height: 150,
          child: pw.Chart(
            grid: pw.PieGrid(),
            datasets: [
              for (var index = 0; index < visible.length; index++)
                pw.PieDataSet(
                  value: visible[index].paisa.toDouble(),
                  color: _palette[index % _palette.length],
                  legend: '',
                  innerRadius: 34,
                  borderWidth: 1.5,
                ),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(child: _categoryBars(visible, report.expensePaisa)),
      ],
    );
  }

  static pw.Widget _categoryBars(
    List<ReportCategory> categories,
    int totalPaisa,
  ) {
    final largest = categories.isEmpty ? 1 : categories.first.paisa;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < categories.length; index++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 9),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                      width: 8,
                      height: 8,
                      decoration: pw.BoxDecoration(
                        color: _palette[index % _palette.length],
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Text(
                        safeText(categories[index].label),
                        maxLines: 1,
                        style: pw.TextStyle(
                          color: _ink,
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Text(
                      MoneyUtils.formatPaisa(categories[index].paisa),
                      style: pw.TextStyle(
                        color: _ink,
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.SizedBox(
                      width: 30,
                      child: pw.Text(
                        '${(categories[index].share * 100).round()}%',
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(color: _muted, fontSize: 9),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                _bar(categories[index].paisa / (largest == 0 ? 1 : largest),
                    _palette[index % _palette.length]),
              ],
            ),
          ),
      ],
    );
  }

  /// Proportional bar built from two flex children.
  ///
  /// The pdf package has no FractionallySizedBox, and Stack here would need a
  /// known pixel width the layout does not have at this point.
  static pw.Widget _bar(double fraction, PdfColor color) {
    final safe = fraction.isFinite ? fraction.clamp(0.02, 1.0) : 0.02;
    final filled = (safe * 1000).round().clamp(1, 1000);
    final remainder = 1000 - filled;

    return pw.Container(
      height: 5,
      decoration: const pw.BoxDecoration(
        color: _hairline,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: filled,
            child: pw.Container(
              decoration: pw.BoxDecoration(
                color: color,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
            ),
          ),
          if (remainder > 0) pw.Expanded(flex: remainder, child: pw.SizedBox()),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- tables

  static pw.Widget _monthlyTable(FinancialReport report) {
    return pw.TableHelper.fromTextArray(
      headers: ['Month', 'Income', 'Spent', 'Net'],
      data: [
        for (final month in report.months)
          [
            safeText(month.shortLabel),
            MoneyUtils.formatPaisa(month.incomePaisa),
            MoneyUtils.formatPaisa(month.expensePaisa),
            MoneyUtils.formatPaisa(month.netPaisa),
          ],
      ],
      border: null,
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      ),
      headerDecoration: const pw.BoxDecoration(color: _brand),
      headerHeight: 22,
      cellHeight: 20,
      cellStyle: const pw.TextStyle(color: _ink, fontSize: 9),
      oddRowDecoration: const pw.BoxDecoration(color: _tint),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      headerAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
    );
  }

  static pw.Widget _transactionTable(
    List<dynamic> transactions, {
    required bool isExpense,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: ['Date', 'Description', 'Category', 'Amount'],
      data: [
        for (final tx in transactions)
          [
            _shortDate(tx.date as DateTime),
            (tx.title as String).isEmpty ? '-' : safeText(tx.title as String),
            safeText(tx.category as String),
            MoneyUtils.formatAmount(tx.amount as double),
          ],
      ],
      border: null,
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      ),
      headerDecoration: pw.BoxDecoration(
        color: isExpense ? _negative : _positive,
      ),
      headerHeight: 22,
      cellHeight: 20,
      cellStyle: const pw.TextStyle(color: _ink, fontSize: 9),
      oddRowDecoration: const pw.BoxDecoration(color: _tint),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.4),
        1: const pw.FlexColumnWidth(3.2),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(1.8),
      },
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
      },
      headerAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
      },
    );
  }

  // ----------------------------------------------------------- prose blocks

  static pw.Widget _observations(FinancialReport report) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final observation in report.observations)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 4,
                  height: 4,
                  margin: const pw.EdgeInsets.only(top: 4.5, right: 8),
                  decoration: const pw.BoxDecoration(
                    color: _brand,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    safeText(observation),
                    style: const pw.TextStyle(
                      color: _ink,
                      fontSize: 10,
                      lineSpacing: 2.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Converts the model's light markdown into styled blocks.
  ///
  /// The pdf package has no markdown renderer, and the old code "solved" that
  /// by deleting the markup and every newline with it.
  static List<pw.Widget> _narrative(String markdown) {
    final widgets = <pw.Widget>[];
    final paragraph = StringBuffer();

    void flush() {
      final text = paragraph.toString().trim();
      paragraph.clear();
      if (text.isEmpty) return;
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            text,
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(
              color: _ink,
              fontSize: 10,
              lineSpacing: 3,
            ),
          ),
        ),
      );
    }

    for (final rawLine in markdown.split('\n')) {
      final line = safeText(_stripInline(rawLine.trimRight()));
      if (line.trim().isEmpty) {
        flush();
        continue;
      }

      final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(line.trim());
      if (heading != null) {
        flush();
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
            child: pw.Text(
              heading.group(1)!,
              style: pw.TextStyle(
                color: _brandDark,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        );
        continue;
      }

      final bullet = RegExp(
        r'^[-*•]\s+(.*)$',
      ).firstMatch(line.trim());
      final numbered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(line.trim());
      if (bullet != null || numbered != null) {
        flush();
        final marker = numbered != null ? '${numbered.group(1)}.' : '•';
        final body = bullet?.group(1) ?? numbered!.group(2)!;
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5, left: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 14,
                  child: pw.Text(
                    marker,
                    style: pw.TextStyle(
                      color: _brand,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    body,
                    style: const pw.TextStyle(
                      color: _ink,
                      fontSize: 10,
                      lineSpacing: 2.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      if (paragraph.isNotEmpty) paragraph.write(' ');
      paragraph.write(line.trim());
    }

    flush();
    return widgets;
  }

  /// Removes inline emphasis markers the renderer cannot express.
  static String _stripInline(String value) {
    return value
        .replaceAll(RegExp(r'\*\*|__'), '')
        .replaceAll(RegExp(r'`'), '');
  }

  // ------------------------------------------------------------------ chrome

  static pw.Widget _sectionTitle(String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 22, bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              color: _ink,
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Container(width: 34, height: 2.5, color: _brand),
        ],
      ),
    );
  }

  static pw.Widget _note(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _tint,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: _hairline),
      ),
      child: pw.Text(
        safeText(text),
        style: const pw.TextStyle(color: _muted, fontSize: 10),
      ),
    );
  }

  static pw.Widget _emptyNotice(FinancialReport report) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(26),
      decoration: pw.BoxDecoration(
        color: _tint,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: _hairline),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Nothing recorded in this period',
            style: pw.TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            safeText(
              'There are no transactions between ${report.rangeLabel}. '
              'Try a longer period, or record some activity first.',
            ),
            style: const pw.TextStyle(
              color: _muted,
              fontSize: 10,
              lineSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context, FinancialReport report) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _hairline)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            safeText('SmartExpense - ${report.period.label}'),
            style: const pw.TextStyle(color: _muted, fontSize: 8),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(color: _muted, fontSize: 8),
          ),
        ],
      ),
    );
  }

  static String _shortDate(DateTime date) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${names[date.month - 1]} ${date.year % 100}';
  }

  static String _dateTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour < 12 ? 'am' : 'pm';
    return '${_shortDate(date)}, $hour:$minute$suffix';
  }
}
