import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A center code (and an invite code) the student arrived with from a
/// center's link: the Play install referrer on Android, the copied
/// `itaaleem:{code}:{ref}` on iOS.
class LinkReferral {
  const LinkReferral({required this.centerCode, this.ref});

  final String centerCode;
  final String? ref;

  @override
  bool operator ==(Object other) =>
      other is LinkReferral &&
      other.centerCode == centerCode &&
      other.ref == ref;

  @override
  int get hashCode => Object.hash(centerCode, ref);
}

final _code = RegExp(r'^[A-Za-z0-9-]{2,32}$');
final _ref = RegExp(r'^[A-Za-z0-9]{1,16}$');

LinkReferral? _make(String? code, String? ref) {
  code = code?.trim();
  ref = ref?.trim();
  if (code == null || !_code.hasMatch(code)) return null;
  return LinkReferral(
    centerCode: code,
    ref: ref != null && _ref.hasMatch(ref) ? ref : null,
  );
}

/// The Play referrer: a query string such as `center=m77&ref=AB12`.
LinkReferral? parsePlayReferrer(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final Map<String, String> params;
  try {
    params = Uri.splitQueryString(raw);
  } catch (_) {
    return null;
  }
  return _make(params['center'], params['ref']);
}

/// Exactly `itaaleem:{code}:{ref}` (ref may be empty) — anything else on
/// the clipboard is ignored.
LinkReferral? parseClipboardReferral(String? text) {
  final match = RegExp(
    r'^itaaleem:([A-Za-z0-9-]{2,32}):([A-Za-z0-9]{0,16})$',
  ).firstMatch(text?.trim() ?? '');
  if (match == null) return null;
  return _make(match.group(1), match.group(2));
}

// Device-level (kept through logout, see account_data_wiper): the link is
// about this install, and it is read once.
const linkReferralCheckedKey = 'link_referral_checked';
const linkCenterCodeKey = 'link_center_code';
const linkRefKey = 'link_ref';

/// Reads the link once per install, then hands out what it found until
/// each part is used.
class LinkReferralStore {
  const LinkReferralStore();

  /// First call only: reads the referrer (Android) or, after asking, the
  /// clipboard (iOS). Later calls return the center code still unused.
  Future<String?> takeCenterCode(BuildContext context) async {
    await readOnce(context);
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(linkCenterCodeKey);
    await prefs.remove(linkCenterCodeKey);
    return code;
  }

  /// The one read per install (referrer / asked clipboard), whichever
  /// screen needs it first: sign-up (for the invite code) or the join.
  Future<void> readOnce(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(linkReferralCheckedKey) == true) return;
    await prefs.setBool(linkReferralCheckedKey, true);
    if (!context.mounted) return;
    final found = await _read(context);
    if (found != null) {
      await prefs.setString(linkCenterCodeKey, found.centerCode);
      if (found.ref != null) await prefs.setString(linkRefKey, found.ref!);
    }
  }

  Future<String?> pendingRef() async =>
      (await SharedPreferences.getInstance()).getString(linkRefKey);

  Future<void> clearRef() async =>
      (await SharedPreferences.getInstance()).remove(linkRefKey);

  Future<LinkReferral?> _read(BuildContext context) async {
    try {
      if (PlatformUtils.isIOS) return await _readClipboard(context);
      final details = await PlayInstallReferrer.installReferrer;
      return parsePlayReferrer(details.installReferrer);
    } catch (e) {
      if (kDebugMode) debugPrint('[LinkReferral] read failed: $e');
      return null;
    }
  }

  /// iOS shows its own paste notice, so the student is asked first, and
  /// once more to use what was found.
  Future<LinkReferral?> _readClipboard(BuildContext context) async {
    final allowed = await _ask(
      context,
      title: 'جاي من لينك سنتر؟',
      body: 'لو نسخت كود السنتر من اللينك، نقدر نقراه من الحافظة.',
      yes: 'اقرا الكود',
      no: 'لا',
    );
    if (allowed != true) return null;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final found = parseClipboardReferral(data?.text);
    if (found == null || !context.mounted) return null;
    final use = await _ask(
      context,
      title: 'لقينا كود سنتر: ${found.centerCode}',
      body: 'استخدمه؟',
      yes: 'استخدمه',
      no: 'لا',
    );
    return use == true ? found : null;
  }

  Future<bool?> _ask(
    BuildContext context, {
    required String title,
    required String body,
    required String yes,
    required String no,
  }) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(no),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(yes),
        ),
      ],
    ),
  );
}
