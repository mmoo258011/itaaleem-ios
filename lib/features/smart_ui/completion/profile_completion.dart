import 'package:dio/dio.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/dio_client.dart' show skipAuthOptions;

/// `profile_completion` from `GET /profile`: what the student still has to
/// fill in. `missing` holds `governorate` and/or `name`, in that order.
class ProfileCompletion {
  const ProfileCompletion({required this.required, this.missing = const []});

  final bool required;
  final List<String> missing;

  bool get needsGovernorate => missing.contains('governorate');
  bool get needsName => missing.contains('name');

  static ProfileCompletion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final missing = raw['missing'];
    return ProfileCompletion(
      required: raw['required'] == true || raw['required'] == 1,
      missing: missing is List
          ? [
              for (final m in missing)
                if (m == 'governorate' || m == 'name') m as String,
            ]
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {'required': required, 'missing': missing};
}

class Governorate {
  const Governorate(this.key, this.name);

  final String key;
  final String name;
}

/// The server's 27 governorates, used when `GET /public/governorates`
/// can't be reached.
const fallbackGovernorates = [
  Governorate('cairo', 'القاهرة'),
  Governorate('giza', 'الجيزة'),
  Governorate('alexandria', 'الإسكندرية'),
  Governorate('qalyubia', 'القليوبية'),
  Governorate('sharqia', 'الشرقية'),
  Governorate('dakahlia', 'الدقهلية'),
  Governorate('gharbia', 'الغربية'),
  Governorate('monufia', 'المنوفية'),
  Governorate('kafr_el_sheikh', 'كفر الشيخ'),
  Governorate('beheira', 'البحيرة'),
  Governorate('damietta', 'دمياط'),
  Governorate('port_said', 'بورسعيد'),
  Governorate('ismailia', 'الإسماعيلية'),
  Governorate('suez', 'السويس'),
  Governorate('faiyum', 'الفيوم'),
  Governorate('beni_suef', 'بني سويف'),
  Governorate('minya', 'المنيا'),
  Governorate('asyut', 'أسيوط'),
  Governorate('sohag', 'سوهاج'),
  Governorate('qena', 'قنا'),
  Governorate('luxor', 'الأقصر'),
  Governorate('aswan', 'أسوان'),
  Governorate('red_sea', 'البحر الأحمر'),
  Governorate('new_valley', 'الوادي الجديد'),
  Governorate('matrouh', 'مطروح'),
  Governorate('north_sinai', 'شمال سيناء'),
  Governorate('south_sinai', 'جنوب سيناء'),
];

List<Governorate>? parseGovernorates(Object? raw) {
  final data = raw is Map ? (raw['data'] ?? raw['items']) : raw;
  if (data is! List) return null;
  final list = [
    for (final g in data)
      if (g is Map && g['key'] is String && g['name'] is String)
        Governorate(g['key'] as String, g['name'] as String),
  ];
  return list.isEmpty ? null : list;
}

final _twoWords = RegExp(r'^\s*\S+(\s+\S+)+\s*$', unicode: true);
final _parentPhone = RegExp(r'^01[0-9]{9}$');

/// Same rule and wording as `POST /profile/complete`.
String? validateFullName(String? v) =>
    v != null && _twoWords.hasMatch(v) && v.trim().length <= 255
    ? null
    : 'يجب إدخال الاسم ثنائي على الأقل';

String? validateParentPhone(String? v, {required String studentMobile}) {
  final phone = v?.trim() ?? '';
  if (phone.isEmpty) return null;
  if (!_parentPhone.hasMatch(phone)) {
    return 'رقم ولي الأمر لازم 11 رقم ويبدأ بـ 01';
  }
  if (phone == studentMobile.trim()) {
    return 'رقم ولي الأمر لازم يكون مختلف عن رقمك';
  }
  return null;
}

/// A 422: the first message per field, plus the overall message.
class ProfileCompletionErrors implements Exception {
  const ProfileCompletionErrors(this.fields, this.message);

  final Map<String, String> fields;
  final String message;

  @override
  String toString() => message;
}

class ProfileCompletionApi {
  const ProfileCompletionApi(this._dio);

  final Dio _dio;

  Future<List<Governorate>> governorates() async {
    try {
      final res = await _dio.get<dynamic>(
        ApiEndpoints.publicGovernorates,
        options: skipAuthOptions,
      );
      return parseGovernorates(res.data) ?? fallbackGovernorates;
    } catch (_) {
      return fallbackGovernorates;
    }
  }

  /// Empty optional values are left out (the server keeps what it has).
  /// Returns the 200 body: `user`, `profile_completion` and `referral`
  /// (`attached`, `ignored` or `null`).
  Future<Map<String, dynamic>> complete({
    String? governorate,
    String? name,
    String? parentPhone,
    String? referralCode,
  }) async {
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    try {
      final res = await _dio.post<dynamic>(
        ApiEndpoints.profileComplete,
        data: {
          'governorate': ?clean(governorate),
          'name': ?clean(name),
          'parent_phone': ?clean(parentPhone),
          'referral_code': ?clean(referralCode),
        },
      );
      final body = res.data;
      return body is Map ? Map<String, dynamic>.from(body) : const {};
    } on DioException catch (e) {
      final body = e.response?.data;
      if (e.response?.statusCode == 422 && body is Map) {
        throw parseCompletionErrors(body);
      }
      rethrow;
    }
  }
}

ProfileCompletionErrors parseCompletionErrors(Map body) {
  final errors = body['errors'];
  return ProfileCompletionErrors({
    if (errors is Map)
      for (final entry in errors.entries)
        if (entry.value is List && (entry.value as List).isNotEmpty)
          entry.key.toString(): (entry.value as List).first.toString(),
  }, body['message']?.toString() ?? 'راجع البيانات');
}
