import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrScanResult {
  final String rawText;
  final String? title;
  final double? amount;
  final DateTime? date;

  OcrScanResult({
    required this.rawText,
    this.title,
    this.amount,
    this.date,
  });
}

class OcrService {
  final ImagePicker _picker = ImagePicker();

  Future<File?> pickImage(ImageSource source) async {
    final XFile? photo = await _picker.pickImage(source: source);
    if (photo == null) return null;
    return File(photo.path);
  }

  Future<OcrScanResult> scanBill(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
    await textRecognizer.close();

    final String rawText = recognizedText.text;
    return parseBillText(rawText);
  }

  OcrScanResult parseBillText(String rawText) {
    if (rawText.trim().isEmpty) {
      return OcrScanResult(rawText: rawText);
    }

    final lines = rawText
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // 1. Extract Vendor / Title (Usually the first non-numeric header line)
    String? extractedTitle;
    for (final line in lines) {
      // Skip lines that look strictly like dates, amounts, or receipts header fluff
      if (RegExp(r'^\d+$').hasMatch(line)) continue;
      if (RegExp(r'total|subtotal|receipt|invoice|tax|date|thank', caseSensitive: false).hasMatch(line)) continue;
      if (line.length >= 3) {
        extractedTitle = line;
        break;
      }
    }

    // 2. Extract Amount (Looks for 'Total', 'Grand Total', or highest dollar/number amount)
    double? extractedAmount;
    final totalRegex = RegExp(
      r'(?:total|amount|due|pay|grand\s*total)\D*?\$?\s*([0-9]+\.?[0-9]{0,2})',
      caseSensitive: false,
    );

    for (final line in lines) {
      final match = totalRegex.firstMatch(line);
      if (match != null) {
        final valStr = match.group(1);
        if (valStr != null) {
          final val = double.tryParse(valStr);
          if (val != null && val > 0) {
            extractedAmount = val;
            break;
          }
        }
      }
    }

    // Fallback: search for any max currency-like number if explicit 'Total' wasn't matched
    if (extractedAmount == null) {
      final numberRegex = RegExp(r'\$?\s*([0-9]+\.[0-9]{2})\b');
      double maxFound = 0.0;
      for (final line in lines) {
        final matches = numberRegex.allMatches(line);
        for (final m in matches) {
          final valStr = m.group(1);
          if (valStr != null) {
            final val = double.tryParse(valStr);
            if (val != null && val > maxFound) {
              maxFound = val;
            }
          }
        }
      }
      if (maxFound > 0) {
        extractedAmount = maxFound;
      }
    }

    // 3. Extract Date
    DateTime? extractedDate;
    final dateRegex = RegExp(
      r'\b(\d{1,2})[\/\.-](\d{1,2})[\/\.-](\d{2,4})\b|\b(\d{4})[\/\.-](\d{1,2})[\/\.-](\d{1,2})\b',
    );

    for (final line in lines) {
      final match = dateRegex.firstMatch(line);
      if (match != null) {
        final dateStr = match.group(0);
        if (dateStr != null) {
          try {
            final parts = dateStr.split(RegExp(r'[\/\.-]'));
            if (parts.length == 3) {
              int p1 = int.parse(parts[0]);
              int p2 = int.parse(parts[1]);
              int p3 = int.parse(parts[2]);

              if (p1 > 1000) {
                extractedDate = DateTime(p1, p2, p3);
              } else {
                int year = p3 < 100 ? (2000 + p3) : p3;
                int month = p1 <= 12 ? p1 : p2;
                int day = p1 <= 12 ? p2 : p1;
                extractedDate = DateTime(year, month, day);
              }
              break;
            }
          } catch (_) {}
        }
      }
    }

    return OcrScanResult(
      rawText: rawText,
      title: extractedTitle,
      amount: extractedAmount,
      date: extractedDate,
    );
  }
}
