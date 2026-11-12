import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.itaaleem.app/storage');

/// Keeps [path] (a directory) out of iCloud / iTunes backups on iOS, so the
/// downloaded lessons never leave the device. Android is covered by
/// `data_extraction_rules.xml` + `allowBackup="false"`. Best effort: true
/// when done (or nothing to do), false on failure — never throws.
Future<bool> excludeFromBackup(String path) async {
  if (kIsWeb || !Platform.isIOS) return true;
  try {
    return await _channel.invokeMethod<bool>('excludeFromBackup', path) ?? false;
  } catch (e) {
    if (kDebugMode) debugPrint('[Storage] excludeFromBackup failed: $e');
    return false;
  }
}
