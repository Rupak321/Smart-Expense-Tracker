import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/expense_model.dart';
import 'package:smartexpense/core/utils/receipt_storage.dart';

void main() {
  group('the stored file name', () {
    test('keeps a recognised image extension', () {
      expect(ReceiptStorage.extensionOf('/cache/photo.jpg'), '.jpg');
      expect(ReceiptStorage.extensionOf('/cache/photo.png'), '.png');
      expect(ReceiptStorage.extensionOf('/cache/photo.HEIC'), '.heic');
    });

    test('handles Windows separators as well as POSIX ones', () {
      expect(ReceiptStorage.extensionOf(r'C:\pics\photo.png'), '.png');
    });

    test('falls back to jpg when there is no usable extension', () {
      expect(ReceiptStorage.extensionOf('/cache/photo'), '.jpg');
      expect(ReceiptStorage.extensionOf('/cache/photo.'), '.jpg');
      expect(ReceiptStorage.extensionOf('.hidden'), '.jpg');
    });

    test('an unexpected suffix is not trusted verbatim', () {
      // A path should not be able to decide the stored file is a script.
      expect(ReceiptStorage.extensionOf('/cache/photo.exe'), '.jpg');
      expect(ReceiptStorage.extensionOf('/cache/photo.dart'), '.jpg');
    });

    test('a dot in a folder name is not mistaken for the extension', () {
      expect(ReceiptStorage.extensionOf('/my.photos/receipt'), '.jpg');
    });

    test('names are stamped so two receipts never collide', () {
      final first = ReceiptStorage.fileNameFor(
        'a.jpg',
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final second = ReceiptStorage.fileNameFor(
        'a.jpg',
        DateTime.fromMillisecondsSinceEpoch(2000),
      );

      expect(first, isNot(second));
      expect(first.endsWith('.jpg'), isTrue);
    });
  });

  group('a transaction knows whether it has one', () {
    ExpenseModel withReceipt(String? path) {
      return ExpenseModel(
        id: 'a',
        title: 'Lunch',
        amount: 450,
        category: 'Food & Dining',
        date: DateTime(2026, 8, 20),
        isExpense: true,
        receiptPath: path,
      );
    }

    test('null and empty both mean no receipt', () {
      expect(withReceipt(null).hasReceipt, isFalse);
      expect(withReceipt('').hasReceipt, isFalse);
    });

    test('a path means there is one', () {
      expect(withReceipt('/data/receipts/r.jpg').hasReceipt, isTrue);
    });

    test('an edit keeps the receipt unless it is cleared', () {
      final original = withReceipt('/data/receipts/r.jpg');

      expect(original.copyWith(amount: 500).receiptPath, '/data/receipts/r.jpg');
      expect(original.copyWith(clearReceipt: true).receiptPath, isNull);
    });
  });

  group('missing files', () {
    test('a null or empty path is reported as absent, not an error', () async {
      expect(await ReceiptStorage.exists(null), isFalse);
      expect(await ReceiptStorage.exists(''), isFalse);
    });

    test('deleting nothing is harmless', () async {
      await ReceiptStorage.delete(null);
      await ReceiptStorage.delete('');
      await ReceiptStorage.delete('/does/not/exist.jpg');
    });
  });
}
