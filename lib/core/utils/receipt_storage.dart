import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps the photo behind a scanned receipt.
///
/// OCR read the image and then threw it away, so a disputed charge could never
/// be checked against the paper it came from.
///
/// Images stay on the device. They are not uploaded, which means they do not
/// follow the account to another phone and are lost if the app is removed -
/// the trade for not putting the user's receipts in cloud storage, or on their
/// bill for it.
class ReceiptStorage {
  const ReceiptStorage._();

  static const _folder = 'receipts';

  /// Uses path_provider rather than path_provider_android, so this works
  /// wherever the app runs instead of only on Android.
  static Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}$_folder',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static String fileNameFor(String sourcePath, DateTime stamp) {
    return 'receipt_${stamp.millisecondsSinceEpoch}${extensionOf(sourcePath)}';
  }

  /// The source extension, defaulting to .jpg.
  ///
  /// Handles both separators, since the picker returns platform-native paths.
  static String extensionOf(String path) {
    final lastSeparator = path.lastIndexOf(RegExp(r'[\\/]'));
    final name = lastSeparator == -1 ? path : path.substring(lastSeparator + 1);
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '.jpg';

    final extension = name.substring(dot).toLowerCase();
    // Anything unexpected is stored as a jpg rather than trusted verbatim,
    // so a path cannot introduce an arbitrary suffix.
    const allowed = {'.jpg', '.jpeg', '.png', '.heic', '.webp'};
    return allowed.contains(extension) ? extension : '.jpg';
  }

  /// Copies the picked image into the app's own storage.
  ///
  /// The picker's file lives in a cache the system is free to clear, so
  /// keeping its path would leave a reference that quietly stops resolving.
  static Future<String?> save(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return null;

      final directory = await _directory();
      final destination = File(
        '${directory.path}${Platform.pathSeparator}'
        '${fileNameFor(sourcePath, DateTime.now())}',
      );
      final saved = await source.copy(destination.path);
      return saved.path;
    } catch (e) {
      debugPrint('Could not store receipt: $e');
      return null;
    }
  }

  static Future<void> delete(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Could not remove receipt: $e');
    }
  }

  static Future<bool> exists(String? path) async {
    if (path == null || path.isEmpty) return false;
    try {
      return File(path).exists();
    } catch (_) {
      return false;
    }
  }
}
