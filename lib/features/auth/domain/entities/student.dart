import 'package:itaaleem/core/config/admin_config.dart';
import 'package:itaaleem/features/smart_ui/completion/profile_completion.dart';
import 'package:itaaleem/features/smart_ui/smart_ui_access.dart';

/// Domain entity for the authenticated student — the shape presentation
/// code works with, independent of the JSON wire format.
class Student {
  const Student({
    required this.id,
    required this.fullName,
    required this.mobile,
    required this.status,
    this.avatarUrl,
    this.email,
    this.isDemo = false,
    this.centerId,
    this.centerJson,
    this.gradeId,
    this.subscriptionStatus,
    this.hasPaidAccess = false,
    this.role,
    this.mustChangePassword = false,
    this.parentCode,
    this.smartUi,
    this.profileCompletion,
  });

  final int id;

  /// `must_change_password` — the center set a temporary password; the app
  /// blocks everything behind "تغيير كلمة السر" until it's changed.
  final bool mustChangePassword;

  /// `user.parent_code` — only sent when "متابعة ولي الأمر" is on for the
  /// student's center; `null` hides the parent-code card.
  final String? parentCode;

  /// `smart_ui` from `GET /profile`; `null` keeps the native app.
  final SmartUiAccess? smartUi;

  /// `profile_completion` from `GET /profile`; `null` = nothing asked.
  final ProfileCompletion? profileCompletion;

  /// A smart-UI student the server still needs details from (governorate,
  /// two-part name) before going on.
  bool get mustCompleteProfile =>
      !isDemo &&
      isStudent &&
      !isAdmin &&
      (smartUi?.enabled ?? false) &&
      (profileCompletion?.required ?? false);

  /// The user's `role` from `GET /profile` / `/login` (`"student"` for
  /// every regular account). `null` when the response didn't carry one —
  /// treated as a student.
  final String? role;

  /// `GET /profile`'s `has_paid_access` — whether the student can open
  /// non-free lessons. Defaults to `false` when the field is absent.
  final bool hasPaidAccess;
  final String fullName;
  final String mobile;
  final String status;
  final String? avatarUrl;
  final String? email;

  /// `GET /profile`'s `subscription_status` — `"pending"`, `"active"` or
  /// `"none"`, per the joined center's activation state. Deliberately
  /// nullable rather than defaulted to a string: `null` means the backend
  /// response didn't carry this field at all (not shipped there yet, or an
  /// older cached profile), and [AppRouter] must treat that exactly like
  /// `"active"` — a hard default of `"none"` here would instead force every
  /// already-joined student back through a gate meant only for genuinely
  /// pending activations.
  final String? subscriptionStatus;

  /// The center/grade this student has joined, per `GET /profile`'s nested
  /// `center`/`grade` objects — `null` until they join one. Only read once,
  /// to seed [CenterMembershipController]'s initial state; a later
  /// join/leave updates that controller's own state directly rather than
  /// re-reading these, so they're allowed to go stale after that.
  final int? centerId;

  /// Raw nested `center` object from `GET /profile` (name, logo, cover,
  /// primary_color, ...) — lets the UI show the joined center's
  /// branding without waiting on (or depending on) `GET /centers/{id}`.
  final Map<String, dynamic>? centerJson;

  /// Storage-relative `logo`/`cover` of [centerJson] (raw, un-resolved).
  String? get centerLogo =>
      _nonEmpty(centerJson?['logo_url'] ?? centerJson?['logo']);
  String? get centerCover =>
      _nonEmpty(centerJson?['cover_url'] ?? centerJson?['cover']);

  static String? _nonEmpty(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  final int? gradeId;

  /// True for the local, backend-free "دخول تجريبي" session
  /// ([AuthController.loginAsDemo]) — never set by any API response.
  final bool isDemo;

  bool get isActive => status == 'active';

  /// Center staff with access to the in-app admin dashboard — by the
  /// server's `role`, or (until the API sends one for admins) a phone
  /// listed in [AdminConfig]. UI gate only: every `/admin/*` endpoint must
  /// enforce the role itself.
  bool get isAdmin =>
      !isDemo &&
      (role == 'admin' ||
          role == 'center_admin' ||
          role == 'super_admin' ||
          AdminConfig.isAdmin(mobile));

  /// Students only: staff and the demo session stay on the native app.
  bool get opensSmartUi =>
      !isDemo && isStudent && !isAdmin && (smartUi?.enabled ?? false);

  bool get isTeacher => role == 'teacher';

  bool get isStudent => role == null || role == 'student';

  /// Already activated/subscribed — "تفعيل كود" and "طلب اشتراك" are hidden.
  bool get isActivated => hasPaidAccess || subscriptionStatus == 'active';
}
