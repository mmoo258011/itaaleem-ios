/// Translates the backend's English (Laravel) validation/auth messages into
/// Arabic so the student never sees raw English text.
class ErrorMessages {
  ErrorMessages._();

  static const generic = 'حدث خطأ ما، حاول مرة أخرى';

  static const _fields = {
    'mobile': 'رقم الهاتف',
    'phone': 'رقم الهاتف',
    'password': 'كلمة المرور',
    'name': 'الاسم',
    'email': 'البريد الإلكتروني',
    'password confirmation': 'تأكيد كلمة المرور',
    'grade': 'الصف الدراسي',
    'center code': 'كود السنتر',
    'code': 'الكود',
  };

  static final _arabic = RegExp(r'[؀-ۿ]');

  static String _field(String raw) {
    final key = raw.toLowerCase().replaceAll('_', ' ').trim();
    return _fields[key] ?? 'هذا الحقل';
  }

  /// Sign-up with a number that already has an account.
  static const mobileTaken =
      'رقم الهاتف ده متسجّل قبل كده. سجّل دخول بيه، أو استخدم «نسيت كلمة المرور».';

  /// The server's "mobile already registered" in either language — e.g.
  /// `رقم التليفون مسجل من قبل` or `The mobile has already been taken.`
  static bool _isMobileTaken(String m) {
    final lower = m.toLowerCase();
    final aboutMobile = RegExp(
      r'mobile|phone|رقم|تليفون|هاتف|موبايل',
    ).hasMatch(lower);
    final taken = RegExp(
      r'already been taken|already (registered|exists)|مسجل من قبل|مسجّل من قبل|مستخدم من قبل|مسجل بالفعل',
    ).hasMatch(lower);
    return aboutMobile && taken;
  }

  /// Returns [message] unchanged if it's already Arabic, otherwise the
  /// best-known Arabic equivalent (or [fallback]).
  static String translate(String message, {String fallback = generic}) {
    final m = message.trim();
    if (m.isEmpty) return fallback;
    if (_isMobileTaken(m)) return mobileTaken;
    if (_arabic.hasMatch(m)) return m;
    final lower = m.toLowerCase();

    if (lower.contains('credentials') ||
        lower.contains('invalid') && lower.contains('password') ||
        lower.contains('unauthenticated') ||
        lower.contains('incorrect')) {
      return 'رقم الهاتف أو كلمة المرور غلط';
    }
    final taken = RegExp(
      r'^the (.+?) has already been taken',
    ).firstMatch(lower);
    if (taken != null) return '${_field(taken.group(1)!)} مستخدم من قبل';
    final required = RegExp(r'^the (.+?) field is required').firstMatch(lower);
    if (required != null) {
      final f = required.group(1)!;
      return f == 'password' ? 'كلمة المرور مطلوبة' : '${_field(f)} مطلوب';
    }
    final atLeast = RegExp(
      r'^the (.+?) (?:field )?must be at least (\d+)',
    ).firstMatch(lower);
    if (atLeast != null) {
      return '${_field(atLeast.group(1)!)} يجب ألا يقل عن ${atLeast.group(2)} حروف';
    }
    if (lower.contains('confirmation does not match')) {
      return 'تأكيد كلمة المرور غير مطابق';
    }
    if (lower.contains('must be') && lower.contains('digits')) {
      return 'رقم الهاتف غير صحيح';
    }
    if (lower.contains('invalid') || lower.contains('format')) {
      return 'البيانات المدخلة غير صحيحة';
    }
    if (lower.contains('too many')) {
      return 'محاولات كثيرة، حاول لاحقاً';
    }
    if (lower.contains('not found')) return 'غير موجود';
    if (lower.contains('server error')) return 'خطأ في الخادم، حاول لاحقاً';
    return fallback;
  }
}
