import 'dart:io';

import 'package:path_provider_android/path_provider_android.dart';

class ProfileImageStorage {
  const ProfileImageStorage._();

  static Future<String> savePickedImage(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      return sourcePath;
    }

    final pathProvider = PathProviderAndroid();
    final supportPath = await pathProvider.getApplicationSupportPath();
    final directory = Directory(
      '${supportPath ?? Directory.current.path}${Platform.pathSeparator}profile_images',
    );
    await directory.create(recursive: true);

    final extension = _extensionFrom(sourcePath);
    final fileName =
        'profile_${DateTime.now().millisecondsSinceEpoch}$extension';
    final destination = File('${directory.path}${Platform.pathSeparator}$fileName');
    final saved = await source.copy(destination.path);
    return saved.path;
  }

  static String _extensionFrom(String path) {
    final lastSeparator = path.lastIndexOf(RegExp(r'[\\/]'));
    final fileName = lastSeparator == -1 ? path : path.substring(lastSeparator + 1);
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) {
      return '.jpg';
    }
    return fileName.substring(dot);
  }
}
