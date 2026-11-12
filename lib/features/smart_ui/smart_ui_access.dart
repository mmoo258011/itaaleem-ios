import 'package:itaaleem/core/config/obf.dart';

/// `smart_ui` from `GET /profile`: whether this student opens the smart UI,
/// and on which center's subdomain. A missing or malformed value means the
/// app stays exactly as it was.
class SmartUiAccess {
  const SmartUiAccess({required this.enabled, required this.centerCode});

  final bool enabled;
  final String centerCode;

  /// The code becomes a subdomain, so nothing that could change the host
  /// gets through.
  static final _validCode = RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$');

  static SmartUiAccess? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final code = raw['center_code'];
    if (code is! String || !_validCode.hasMatch(code)) return null;
    final enabled = raw['enabled'];
    return SmartUiAccess(
      enabled: enabled == true || enabled == 1,
      centerCode: code,
    );
  }

  Uri get origin => Uri.https('$centerCode.${Obf.rootDomain}');

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'center_code': centerCode,
  };
}
