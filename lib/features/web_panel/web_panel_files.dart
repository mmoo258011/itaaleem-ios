import 'dart:convert';
import 'dart:typed_data';

import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:path/path.dart' as p;

/// What the panel may upload: documents, sheets and images.
const panelUploadExtensions = [
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'xlsx',
  'xls',
  'csv',
  'docx',
  'doc',
];

const maxPanelUploadBytes = 50 * 1024 * 1024;

/// Largest export the page may hand over (base64 through the JS channel).
const maxPanelDownloadBytes = 20 * 1024 * 1024;

/// What a download may be saved as; anything else is refused.
const panelDownloadExtensions = {
  'csv',
  'xlsx',
  'xls',
  'pdf',
  'zip',
  'docx',
  'doc',
  'txt',
  'png',
  'jpg',
  'jpeg',
};

String _extOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

bool isPanelUploadAllowed(String name, int? size) =>
    panelUploadExtensions.contains(_extOf(name)) &&
    size != null &&
    size > 0 &&
    size <= maxPanelUploadBytes;

/// A safe file name for a download: the last part of [raw] only, with
/// separators, `..` and control characters gone, and an allowed extension.
/// `null` when the extension isn't allowed.
String? safeDownloadName(String? raw, {String? mime}) {
  var name = (raw ?? '').replaceAll('\\', '/').split('/').last;
  name = name.replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '').trim();
  while (name.startsWith('.')) {
    name = name.substring(1);
  }
  var ext = _extOf(name);
  if (!panelDownloadExtensions.contains(ext)) {
    final fromMime = _extOfMime(mime);
    if (fromMime == null) return null;
    ext = fromMime;
    name = name.isEmpty ? 'export.$ext' : '$name.$ext';
  }
  var stem = name.substring(0, name.length - ext.length - 1).trim();
  if (stem.isEmpty || stem == '.') stem = 'export';
  if (stem.length > 80) stem = stem.substring(0, 80);
  return '$stem.$ext';
}

String? _extOfMime(String? mime) => switch (mime?.split(';').first.trim()) {
  'text/csv' => 'csv',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => 'xlsx',
  'application/vnd.ms-excel' => 'xls',
  'application/pdf' => 'pdf',
  'application/zip' => 'zip',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
    'docx',
  'text/plain' => 'txt',
  _ => null,
};

/// `<dir>/<name>`, or `null` if it would land outside [dir].
String? downloadPathIn(String dir, String name) {
  final path = p.normalize(p.join(dir, name));
  return p.isWithin(dir, path) ? path : null;
}

/// The base64 body the page sent, or `null` when it's malformed or too big.
Uint8List? decodeDownload(Object? data) {
  if (data is! String || data.isEmpty) return null;
  if (data.length > (maxPanelDownloadBytes * 4 / 3) + 8) return null;
  try {
    final bytes = base64Decode(data);
    return bytes.isEmpty || bytes.length > maxPanelDownloadBytes ? null : bytes;
  } on FormatException {
    return null;
  }
}

/// A link the user tapped that leaves our domain: https, port 443, no
/// user info, at most 2048 characters. Else `null`.
Uri? outsideTappedLink(Object? raw) {
  if (raw is! String || raw.length > 2048) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      isInAppWebAllowed(uri)) {
    return null;
  }
  return uri;
}

/// A main-frame URL on our domain that's a file, not a page (exports).
bool looksLikeDownload(Uri uri) {
  final path = uri.path.toLowerCase();
  return RegExp(r'\.(csv|xlsx|xls|pdf|zip|docx)$').hasMatch(path) ||
      RegExp(r'/(download|export)$').hasMatch(path);
}
