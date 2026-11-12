import 'package:itaaleem/core/config/obf.dart';

/// Central place for the API base URL and endpoint paths, per APP_SPEC.md.
///
/// `API_BASE_URL` is injected via `--dart-define=API_BASE_URL=...` at build
/// time, defaulting to the live منصة أونلاين backend.
class ApiEndpoints {
  ApiEndpoints._();

  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// `--dart-define=API_BASE_URL=…`, else the production API.
  static final String baseUrl = _baseUrlOverride.isNotEmpty
      ? _baseUrlOverride
      : Obf.apiBase;

  // --- Auth ---
  static const String register = '/register';
  static const String login = '/login';
  static const String logout = '/logout';

  /// `POST /forgot-password {mobile | email}` — asks the backend to start a
  /// password reset. Not confirmed against the live backend: a 404/405/501 is
  /// treated as "unsupported" and the screen falls back to contacting the
  /// center (see `ForgotPasswordScreen`).
  static const String forgotPassword = '/forgot-password';

  // --- Profile ---
  /// `GET /profile` — also used to restore/verify the session on app start;
  /// the API has no separate `/me` route (confirmed 404 on the live
  /// backend), despite APP_SPEC.md's original draft mentioning one.
  static const String profile = '/profile';

  /// `POST /profile/password` `{current_password, password,
  /// password_confirmation}`.
  static const String password = '/profile/password';

  // --- Account ---
  /// Account deletion is `DELETE /profile` ([profile]).

  // --- Centers ---
  /// `GET /centers?search=` — paginated `{items, meta}`, not confirmed in
  /// APP_SPEC.md but verified live on the backend.
  static const String centers = '/centers';
  static String centerDetails(int id) => '/centers/$id';

  /// `GET /center/support-info` — the logged-in student's own center
  /// contact details (no id: resolved server-side from the token).
  static const String centerSupportInfo = '/center/support-info';

  /// `GET/POST /centers/{id}/reviews`, `PUT/DELETE /centers/{id}/reviews/{reviewId}`.
  static String centerReviews(int id) => '/centers/$id/reviews';
  static String centerReview(int id, int reviewId) =>
      '/centers/$id/reviews/$reviewId';

  /// `POST /centers/join` — joins by `code` (not by id in the URL), body
  /// `{code, grade_id?}`. Confirmed against the live Laravel backend, which
  /// has no `/centers/{id}/join` route.
  static const String centerJoin = '/centers/join';
  static const String centersLeave = '/centers/leave';

  // --- Courses ---
  // NOT LIVE: `GET /courses` 404s on the live backend (confirmed) — the
  // server-side concept these targeted has been replaced by `/subjects`
  // below. Left in place only because [CoursesRemoteDataSource] and its
  // screens (`/courses/:id`, reached from "مشترياتي") still reference them;
  // out of scope for this pass to rewire onto `/subjects`.
  static const String courses = '/courses';
  static const String availableCourses = '/courses/available';
  static String courseDetails(int id) => '/courses/$id';
  static String courseRequest(int id) => '/courses/$id/request';

  /// `GET /courses/{id}/exams` — the course's exams with each one's attempt
  /// status (`attempted`, `score`, `passed`), richer than the exam stubs
  /// embedded directly in `GET /courses/{id}`.
  static String courseExams(int id) => '/courses/$id/exams';

  // --- Subjects ---
  /// `GET /subjects` — the joined center/grade's subjects (flat array, not
  /// paginated): `{id, name, icon, description, lessons_count,
  /// exams_count}`. 403s with "يجب الانضمام لسنتر أولاً" if the student
  /// hasn't joined a center yet. Verified live; not documented in
  /// APP_SPEC.md.
  static const String subjects = '/subjects';

  /// `GET /subjects/{id}` — same fields as the list plus `lessons` and
  /// `exams` arrays.
  static String subjectDetails(int id) => '/subjects/$id';

  /// `GET /subjects/{id}/progress` — `{progress: {"<lessonId>": {
  /// watched_seconds, total_seconds, percentage, completed, ...}}}`, one
  /// key per active lecture (zeros, not null, when never watched). Replaces
  /// a `/lessons/{id}/progress` call per lecture.
  static String subjectProgress(int id) => '/subjects/$id/progress';

  /// `GET /subjects/{id}/exams` — the subject's exams. Exams belong to the
  /// subject on the server (no lesson_id), so this one call covers every
  /// lecture of it.
  static String subjectExams(int id) => '/subjects/$id/exams';

  /// `GET /lessons?subject_id=&limit=` — flat array of the same lesson
  /// shape embedded in `GET /subjects/{id}`.
  static const String lessons = '/lessons';

  /// `POST /subscription-requests` — asks the center for paid-content access.
  static const String subscriptionRequests = '/subscription-requests';

  // --- Subject subscriptions (see docs/api/subject_subscriptions_routes.md) ---
  /// `GET /subjects/{id}/subscription-status` — whether this subject needs a
  /// subscription and whether the student has an active one.
  static String subjectSubscriptionStatus(int subjectId) =>
      '/subjects/$subjectId/subscription-status';

  /// `GET /my-subscriptions` — the student's subject subscriptions.
  static const String mySubscriptions = '/my-subscriptions';

  // --- Teachers ---
  /// Public — reachable without a session, but [AuthInterceptor] still
  /// attaches the bearer token automatically when one is stored.
  static const String publicTeachers = '/public/teachers';

  // --- Lectures ---
  /// `GET /lessons/{id}` (the old `/lectures/{id}` is kept server-side only
  /// for older app versions).
  static String lectureDetails(int id) => '/lessons/$id';

  /// `GET /lectures/{id}/playback` — a signed, time-limited streaming URL
  /// for the lecture's video (plus optional per-quality alternates and any
  /// headers the CDN requires), replacing the plain `video_url` embedded in
  /// `GET /lectures/{id}` whenever this call succeeds.
  static String lecturePlayback(int id) => '/lectures/$id/playback';

  /// `GET`/`POST /lessons/{id}/progress` — lecture-level playback progress
  /// (`position`/`duration`/`progress_percentage`/`is_completed`), separate
  /// from the older per-video `/videos/{id}/progress` below. `id` is the
  /// same lesson/lecture id space `GET /lectures/{id}` uses.
  static String lectureProgress(int id) => '/lessons/$id/progress';

  // --- Videos ---

  // --- PDFs ---
  static String pdfProgress(int id) => '/pdfs/$id/progress';

  // --- Activation ---
  static const String activateCode = '/activate-code';

  // --- Exams ---
  /// `GET /exams` — the joined center/grade's exams (flat array):
  /// `{id, title, subject:{id,name}, questions_count, duration_minutes,
  /// pass_percentage, is_locked}`. Verified live.
  static const String exams = '/exams';

  /// `GET /lectures/{id}/exams` — a lecture's own exams, if the server
  /// offers it (probed; falls back to `?lecture_id=` then the subject's).
  static String lectureExams(int lectureId) => '/lectures/$lectureId/exams';
  static String examDetails(int id) => '/exams/$id';

  /// `GET /exams/{id}/questions` — the exam's questions, without the
  /// correct answer.
  static String examQuestions(int id) => '/exams/$id/questions';

  /// `POST /exams/{id}/submit` — body `{answers: [{question_id,
  /// selected_option}]}`, returns the graded result.
  static String examSubmit(int id) => '/exams/$id/submit';

  /// `POST /exams/{id}/start` — opens an attempt and returns its questions
  /// (`{attempt_id, questions, duration_minutes, started_at}`). Newer servers
  /// only; older ones fall back to [examQuestions].
  static String examStart(int id) => '/exams/$id/start';

  /// `GET /exam-attempts/{id}/review` — an attempt's answers with the correct
  /// options and explanations (when the exam allows review).
  static String examAttemptReview(int attemptId) =>
      '/exam-attempts/$attemptId/review';

  /// `GET /exams/{id}/results` — this student's past attempts on the exam.
  static String examResults(int id) => '/exams/$id/results';

  /// `GET /exams/{id}/result` — singular form some backend versions expose
  /// for the same data as [examResults]; tried as a fallback when the plural
  /// one 404s.
  static String examResult(int id) => '/exams/$id/result';

  // --- Assignments ---
  /// `GET /courses/{subject}/assignments` — a subject's assignments.
  static String subjectAssignments(int subjectId) =>
      '/courses/$subjectId/assignments';

  /// `GET /assignments/{id}`.
  static String assignmentDetails(int id) => '/assignments/$id';

  /// `POST /assignments/{id}/submit` — multipart (`file`, optional `notes`).
  static String assignmentSubmit(int id) => '/assignments/$id/submit';

  /// `GET /assignments/{id}/submission` — this student's own submission.
  static String assignmentSubmission(int id) => '/assignments/$id/submission';

  /// `GET /teachers` — the joined center's teachers (distinct from
  /// [publicTeachers] above, which is scoped by course instead).
  static const String teachers = '/teachers';

  // --- Attachments ---
  /// `GET /attachments?subject_id=` — a subject's downloadable files.
  static const String attachments = '/attachments';

  /// `GET /lessons/{id}/file-link` / `GET /attachments/{id}/link` — a fresh
  /// signed `{url, download_url, expires_at}` (the signed `file_url` is only
  /// valid for ~10 minutes and is bound to the student).
  static String lessonFileLink(int id) => '/lessons/$id/file-link';
  static String attachmentLink(int id) => '/attachments/$id/link';

  // --- Smart UI ---
  /// `POST /smart-ui/handoff` — a one-time `{ticket, url}` that signs the
  /// student into the smart UI on the center's subdomain.
  static const String smartUiHandoff = '/smart-ui/handoff';

  /// `POST /web/handoff` `{url}` — a one-time `{ticket, url}` that signs the
  /// user into a web page on `*.itaaleem.com` (the center panel, menu links).
  static const String webHandoff = '/web/handoff';

  /// `POST /profile/complete` — governorate, two-part name, optional parent
  /// phone and referral code (`profile_completion` in `GET /profile`).
  static const String profileComplete = '/profile/complete';

  /// `GET /public/governorates` — `{key, name, city}` items, no token.
  static const String publicGovernorates = '/public/governorates';

  // --- Banners ---
  /// `GET /banners` — the joined center's home-screen banners.
  static const String banners = '/banners';

  // --- Channel ---
  // NOT LIVE: `GET /channel` 404s on the live backend (confirmed), and
  // nothing in the app actually routes to `ChannelScreen` — dead code, left
  // untouched since it's unreachable. The real student<->center messaging
  // used by `ChatScreen` is `/messages` below.
  static const String channel = '/channel';

  // --- Messages ---
  /// `GET /messages` — paginated `{items, meta}`, newest first per the
  /// live behavior. `POST /messages` with `{body}` sends one, returning it
  /// in the same shape. Verified live; not documented in APP_SPEC.md.
  static const String messages = '/messages';

  // --- Notifications ---
  /// `GET /notifications` — paginated `{items, meta}`. Verified live
  /// (empty-list shape only — no populated sample was available to confirm
  /// each item's exact field names, so [Notification.fromJson] is written
  /// defensively).
  static const String notifications = '/notifications';
  static String notificationRead(String id) => '/notifications/$id/read';

  static const String notificationsReadAll = '/notifications/mark-all-read';

  /// `GET /notifications/unread-count`.
  static const String notificationsUnreadCount = '/notifications/unread-count';

  // --- Push notifications (FCM) ---
  /// `POST /fcm-token` — registers/refreshes this device's push token
  /// against the logged-in student, body `{token}`. The very first token is
  /// also sent inline on `POST /login` (see `AuthRemoteDataSource.login`);
  /// this endpoint is what [FcmService] calls afterwards — at app start for
  /// an already-restored session, and on `onTokenRefresh`.
  static const String fcmToken = '/fcm-token';

  // --- Center admin dashboard ---
  /// Base of every center-admin endpoint (`/api/v1/center-admin/...`).
  /// The server scopes each response to the admin's own center from the
  /// auth token. See `CenterAdminApi`.
  static const String centerAdmin = '/center-admin';

  // --- Admin (in-app dashboard) ---
  /// Center-admin endpoints behind the in-app "الإدارة" tab — new, see
  /// `docs/api/admin_routes.md`. Until they're deployed every screen shows
  /// a "not available on the server yet" state instead of failing.
  static const String adminDashboardStats = '/admin/dashboard-stats';
  static const String adminStudents = '/admin/students';
  static String adminStudent(int id) => '/admin/students/$id';
  static String adminStudentDevice(int studentId, int deviceId) =>
      '/admin/students/$studentId/devices/$deviceId';
  static const String adminSubjects = '/admin/subjects';
  static String adminSubject(int id) => '/admin/subjects/$id';
  static const String adminSchedules = '/admin/schedules';
  static String adminSchedule(int id) => '/admin/schedules/$id';
  static const String adminSubscriptions = '/admin/subscriptions';
  static String adminSubscription(int id) => '/admin/subscriptions/$id';
  static const String adminAnnouncements = '/admin/announcements';
  static String adminAnnouncement(int id) => '/admin/announcements/$id';

  // --- App version ---
  /// Public — checked once after splash to offer/force an app update.
  static const String appVersion = '/public/app-version';

  // --- Settings ---
  /// Public — no auth token, reachable even while logged out (e.g. from the
  /// login screen's support links).
  static const String publicSettings = '/public/settings';

  /// `GET /app-config` — dashboard-controlled features, texts, links, menu
  /// items, home cards and maintenance. A 404 (older server) = defaults.
  static const String appConfig = '/app-config';

  // --- News channel (3.1.0; 403 when the channel is off) ---
  /// `GET /news?page=` — `{posts, pagination, reactions_available}`.
  static const String news = '/news';
  static const String newsUnreadCount = '/news/unread-count';
  static const String newsSeen = '/news/seen';
  static String newsView(int id) => '/news/$id/view';
  static String newsReact(int id) => '/news/$id/react';

  // --- Grade change (3.1.0; 403 when the feature is off) ---
  static const String gradeChangeOptions = '/grade-change/options';
  static const String gradeChange = '/grade-change';
  static const String gradeChangeStatus = '/grade-change/status';
  static const String gradeChangeCancel = '/grade-change/cancel';

  /// The API returns storage paths (e.g. `courses/xxx.png`), not full URLs.
  /// Resolves one against the server's public storage disk
  /// (`<origin>/storage/<path>`, confirmed against the live API). Already
  /// looks like a full URL? — returned unchanged.
  /// A streaming URL from `GET /lectures/{id}/playback`. Unlike [mediaUrl],
  /// a root-relative path (`/stream/12/720p?signature=…`) is a server route,
  /// not a file under `/storage` — prefixing it would break the signature.
  /// Only a bare relative path (`videos/12.mp4`) is treated as storage.
  static String? playbackUrl(String? path) {
    final value = path?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('/')) {
      return '${Uri.parse(baseUrl).replace(path: '').toString()}$value';
    }
    return mediaUrl(value);
  }

  static String? mediaUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final origin = Uri.parse(baseUrl).replace(path: '').toString();
    return '$origin/storage/${path.startsWith('/') ? path.substring(1) : path}';
  }
}
