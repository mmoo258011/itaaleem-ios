import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:itaaleem/features/smart_ui/completion/profile_completion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the student gave at sign-up beyond the account itself: governorate,
/// parent's phone and invite code. Sent with `POST /register`, and — so the
/// student is never asked twice even if that endpoint ignores them — also
/// to `POST /profile/complete` once signed in ([flushSignupExtras]).
class SignupExtras {
  const SignupExtras({this.governorate, this.parentPhone, this.referralCode});

  final String? governorate;
  final String? parentPhone;
  final String? referralCode;

  static String? _clean(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  bool get isEmpty =>
      governorate == null && parentPhone == null && referralCode == null;

  /// The `POST /register` body fields.
  Map<String, String> toRegisterFields() => {
    'governorate': ?governorate,
    'parent_phone': ?parentPhone,
    'referral_code': ?referralCode,
  };

  Map<String, dynamic> toJson() => toRegisterFields();

  factory SignupExtras.fromJson(Map<String, dynamic> json) => SignupExtras(
    governorate: _clean(json['governorate']),
    parentPhone: _clean(json['parent_phone']),
    referralCode: _clean(json['referral_code']),
  );

  /// Without the fields the server refused (422), so a bad invite code
  /// doesn't hold back the governorate.
  SignupExtras without(Iterable<String> fields) {
    final json = toJson()..removeWhere((k, _) => fields.contains(k));
    return SignupExtras.fromJson(json);
  }
}

const signupExtrasKey = 'signup_extras';

Future<void> saveSignupExtras(SignupExtras extras) async {
  final prefs = await SharedPreferences.getInstance();
  if (extras.isEmpty) {
    await prefs.remove(signupExtrasKey);
  } else {
    await prefs.setString(signupExtrasKey, jsonEncode(extras.toJson()));
  }
}

Future<SignupExtras?> readSignupExtras() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(signupExtrasKey);
  if (raw == null) return null;
  try {
    return SignupExtras.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    await prefs.remove(signupExtrasKey);
    return null;
  }
}

/// Sends the stored sign-up details to `POST /profile/complete` and forgets
/// them once the server has them. Called right after sign-up and again
/// after joining a center, before the profile is refreshed — so
/// «كمّل بياناتك» only shows when the server still needs something.
/// A network error keeps them for the next try; a 422 drops the refused
/// fields and retries once with the rest.
Future<void> flushSignupExtras(ProfileCompletionApi api) async {
  var extras = await readSignupExtras();
  for (var attempt = 0; attempt < 2; attempt++) {
    if (extras == null || extras.isEmpty) {
      await saveSignupExtras(const SignupExtras());
      return;
    }
    try {
      await api.complete(
        governorate: extras.governorate,
        parentPhone: extras.parentPhone,
        referralCode: extras.referralCode,
      );
      await saveSignupExtras(const SignupExtras());
      return;
    } on ProfileCompletionErrors catch (e) {
      if (kDebugMode) debugPrint('[SignupExtras] refused: ${e.fields.keys}');
      final rest = extras.without(e.fields.keys);
      // Nothing field-specific to drop: give up rather than loop.
      if (e.fields.isEmpty || rest.toJson().length == extras.toJson().length) {
        await saveSignupExtras(const SignupExtras());
        return;
      }
      extras = rest;
      await saveSignupExtras(rest);
    } on DioException catch (e) {
      // Offline / timeout: keep them. Any other answer: don't retry forever.
      if (e.response != null) await saveSignupExtras(const SignupExtras());
      return;
    } catch (_) {
      return;
    }
  }
}
