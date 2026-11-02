import 'package:itaaleem/features/auth/presentation/screens/force_change_password_screen.dart';
import 'package:itaaleem/features/grade_change/grade_change_screen.dart';
import 'package:itaaleem/features/news/presentation/news_screen.dart';
import 'package:itaaleem/features/news/presentation/news_routes.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_dashboard_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_request_approve_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_activation_codes_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_inbox_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_students_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_student_detail_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_subjects_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_teachers_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_lectures_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_lecture_detail_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_exams_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_subscriptions_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_notifications_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_banners_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_files_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_settings_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_stats_screen.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_models.dart';
import 'package:itaaleem/features/center_admin/presentation/center_admin_routes.dart';
import 'package:itaaleem/features/exams/presentation/screens/exam_review_screen.dart';
import 'package:itaaleem/features/subscriptions/presentation/screens/my_subscriptions_screen.dart';
import 'package:itaaleem/app/router/route_args.dart';
import 'package:itaaleem/features/admin/data/models/admin_models.dart';
import 'package:itaaleem/features/admin/presentation/screens/admin_announcements_screen.dart';
import 'package:itaaleem/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:itaaleem/features/admin/presentation/screens/admin_schedule_screen.dart';
import 'package:itaaleem/features/admin/presentation/screens/admin_students_screen.dart';
import 'package:itaaleem/features/admin/presentation/screens/admin_subjects_screen.dart';
import 'package:itaaleem/features/admin/presentation/screens/admin_subscriptions_screen.dart';
import 'package:itaaleem/core/widgets/fullscreen_image_viewer.dart';
import 'package:itaaleem/features/account/presentation/screens/about_screen.dart';
import 'package:itaaleem/features/account/presentation/screens/support_screen.dart';
import 'package:itaaleem/features/activation/presentation/screens/activation_screen.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/auth/presentation/providers/signed_in_before_provider.dart';
import 'package:itaaleem/features/auth/presentation/screens/change_password_screen.dart';
import 'package:itaaleem/features/auth/presentation/screens/edit_profile_screen.dart';
import 'package:itaaleem/features/channel/presentation/screens/channel_image_viewer_screen.dart';
import 'package:itaaleem/features/exams/presentation/screens/exam_result_screen.dart';
import 'package:itaaleem/features/exams/presentation/screens/exam_taking_screen.dart';
import 'package:itaaleem/features/subjects/domain/entities/subject.dart';
import 'package:itaaleem/features/subjects/presentation/screens/lesson_pdf_screen.dart';
import 'package:itaaleem/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:itaaleem/features/auth/presentation/screens/login_screen.dart';
import 'package:itaaleem/features/auth/presentation/screens/register_screen.dart';
import 'package:itaaleem/features/center/domain/entities/center_model.dart';
import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';
import 'package:itaaleem/features/center/presentation/screens/center_deactivated_screen.dart';
import 'package:itaaleem/features/center/presentation/screens/center_profile_screen.dart';
import 'package:itaaleem/features/center/presentation/screens/center_search_screen.dart';
import 'package:itaaleem/features/center/presentation/screens/contact_center_screen.dart';
import 'package:itaaleem/features/center/presentation/screens/pending_activation_screen.dart';
import 'package:itaaleem/features/center/presentation/screens/select_grade_screen.dart';
import 'package:itaaleem/features/chat/presentation/screens/chat_screen.dart';
import 'package:itaaleem/features/courses/domain/entities/course_details.dart';
import 'package:itaaleem/features/courses/presentation/screens/course_details_screen.dart';
import 'package:itaaleem/features/courses/presentation/screens/lecture_player_screen.dart';
import 'package:itaaleem/features/courses/presentation/screens/pdf_viewer_screen.dart';
import 'package:itaaleem/features/courses/presentation/screens/section_lessons_screen.dart';
import 'package:itaaleem/features/exams/presentation/screens/exam_details_screen.dart';
import 'package:itaaleem/features/exams/presentation/screens/exams_screen.dart';
import 'package:itaaleem/features/home/presentation/screens/home_shell.dart';
import 'package:itaaleem/features/home/presentation/screens/subjects_screen.dart';
import 'package:itaaleem/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:itaaleem/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:itaaleem/features/onboarding/presentation/providers/permissions_onboarding_provider.dart';
import 'package:itaaleem/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:itaaleem/features/onboarding/presentation/screens/permissions_onboarding_screen.dart';
import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';
import 'package:itaaleem/features/settings/presentation/screens/maintenance_screen.dart';
import 'package:itaaleem/features/splash/presentation/providers/app_startup.dart';
import 'package:itaaleem/features/splash/presentation/screens/splash_screen.dart';
import 'package:itaaleem/features/subjects/presentation/screens/lesson_detail_screen.dart';
import 'package:itaaleem/features/subjects/presentation/screens/lesson_video_screen.dart';
import 'package:itaaleem/features/subjects/presentation/screens/subject_detail_screen.dart';
import 'package:itaaleem/features/update/presentation/providers/update_providers.dart';
import 'package:itaaleem/features/video/presentation/screens/downloads_screen.dart';
import 'package:itaaleem/features/center/data/models/center_review.dart';
import 'package:itaaleem/features/center/presentation/screens/all_reviews_screen.dart';
import 'package:itaaleem/features/center/presentation/screens/review_form_screen.dart';
import 'package:itaaleem/features/update/presentation/screens/force_update_screen.dart';
import 'package:itaaleem/features/parent/presentation/guardian_controller.dart';
import 'package:itaaleem/features/parent/presentation/screens/parent_auth_screen.dart';
import 'package:itaaleem/features/parent/presentation/screens/parent_child_screen.dart';
import 'package:itaaleem/features/parent/presentation/screens/parent_home_screen.dart';
import 'package:itaaleem/features/live/presentation/live_routes.dart';
import 'package:itaaleem/features/live/presentation/screens/live_session_screen.dart';
import 'package:itaaleem/features/live/presentation/screens/live_sessions_screen.dart';
import 'package:itaaleem/app/router/page_transition.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:itaaleem/core/widgets/secure_screen.dart';
import 'package:itaaleem/core/widgets/content_width_limit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const splashPath = '/';
const lessonVideoPath = '/lesson-video';
const loginPath = '/login';
const registerPath = '/register';
const forgotPasswordPath = '/forgot-password';
const forceChangePasswordPath = '/change-password-required';
const homePath = '/home';
const maintenancePath = '/maintenance';
const notificationsPath = '/notifications';
const forceUpdatePath = '/force-update';
const onboardingPath = '/onboarding';
const permissionsOnboardingPath = '/permissions';
const centerSearchPath = '/center-search';
const centerDeactivatedPath = '/center-deactivated';
const pendingActivationPath = '/pending-activation';
const contactCenterPath = '/contact-center';
const chatPath = '/chat';
const centerReviewsPath = '/center-reviews';
const centerReviewFormPath = '/center-review-form';
const downloadsPath = '/downloads';
const subjectsPath = '/subjects';
const examsPath = '/exams';
const assignmentsPath = '/assignments';
const supportPath = '/support';
const editProfilePath = '/edit-profile';
const changePasswordPath = '/change-password';
const aboutPath = '/about';
const activationPath = '/activation';
const lessonPdfPath = '/lesson-pdf';
const lessonAttachmentsPath = '/lesson-attachments';
const lessonExamsPath = '/lesson-exams';
const examTakingPath = '/exam-taking';
const examResultPath = '/exam-result';
const examReviewPath = '/exam-review';
const channelImagePath = '/channel-image';
const imageViewerPath = '/image-viewer';
const mySubscriptionsPath = '/profile/subscriptions';

// Admin dashboard — only reachable for admins (see the redirect below).
const adminPath = '/admin';
const adminStudentsPath = '/admin/students';
String adminStudentDetailsPath(int id) => '/admin/students/$id';
const adminSubjectsPath = '/admin/subjects';
const adminSchedulePath = '/admin/schedule';
const adminSubscriptionsPath = '/admin/subscriptions';
const adminAnnouncementsPath = '/admin/announcements';

/// Lets code without a local `BuildContext` (`FcmService`'s tap-to-navigate
/// handling) reach the active `Navigator` — e.g. to push a route.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Notifies GoRouter to re-run its `redirect` callback whenever
/// [authControllerProvider] or [appSettingsProvider] (maintenance mode)
/// changes, WITHOUT rebuilding [appRouterProvider] itself. Using
/// `ref.listen` (not `ref.watch`) here is deliberate: watching
/// authControllerProvider directly in the router's provider body used to
/// rebuild a brand-new `GoRouter` (and thus a brand-new `Navigator`) on
/// every single auth AsyncValue change — including transient
/// AsyncLoading during login/logout — which could momentarily show the old
/// and new route trees overlapping (e.g. a ghosted duplicate bottom nav
/// during the login/register -> home transition). GoRouter's
/// `refreshListenable` re-evaluates `redirect` in place instead.
class _AppRefreshListenable extends ChangeNotifier {
  _AppRefreshListenable(Ref ref) {
    ref.listen(authControllerProvider, (previous, next) => notifyListeners());
    ref.listen(
      guardianControllerProvider,
      (previous, next) => notifyListeners(),
    );
    ref.listen(splashReleasedProvider, (previous, next) => notifyListeners());
    ref.listen(appSettingsProvider, (previous, next) => notifyListeners());
    ref.listen(updateStatusProvider, (previous, next) => notifyListeners());
    ref.listen(onboardingSeenProvider, (previous, next) => notifyListeners());
    ref.listen(
      permissionsOnboardingSeenProvider,
      (previous, next) => notifyListeners(),
    );
    ref.listen(
      centerDeactivatedProvider,
      (previous, next) => notifyListeners(),
    );
  }
}

/// GoRouter config, built once and kept alive for the app's lifetime;
/// [_AuthRefreshListenable] tells it to re-run [redirect] whenever auth
/// state changes.
///
/// Redirect rules:
/// - maintenance mode on -> forced to `/maintenance` (the login route is the
///   one exception, always reachable).
/// - cold start not finished (see [splashReleasedProvider]) or session
///   still restoring -> stay on the splash route.
/// - first launch -> forced through `/onboarding` (feature intro) then
///   `/permissions`, in that order, before anything else.
/// - unauthenticated -> forced to `/login` (unless already on an auth
///   route).
/// - authenticated -> bounced away from splash/login/register to `/home`
///   regardless of center membership — [HomeShell]'s "الرئيسية" tab shows
///   the join-by-code screen itself until the student joins a center.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _AppRefreshListenable(ref);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: splashPath,
    debugLogDiagnostics: false,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final path = state.matchedLocation;

      // Cold start: stay on the splash until it releases the app — session,
      // center and onboarding flags loaded, its minimum duration shown and
      // its fade-out played (see [splashReleasedProvider]). Every rule below
      // then sees settled state, so the app makes exactly one move off the
      // splash, never a redirect chain.
      if (!ref.read(splashReleasedProvider)) {
        return path == splashPath ? null : splashPath;
      }

      // Highest-priority gate, ahead of even maintenance mode: an outdated
      // build may not be compatible with the current backend at all. Fails
      // open the same way maintenance/auth below do — a still-loading or
      // errored version check never blocks the app.
      final forceUpdate =
          ref.read(updateStatusProvider).valueOrNull?.forceUpdate ?? false;
      if (forceUpdate) {
        return path == forceUpdatePath ? null : forceUpdatePath;
      }
      if (path == forceUpdatePath) {
        return authState.valueOrNull != null ? homePath : loginPath;
      }

      // Guardian ("ولي الأمر") session: confined to its own routes — never a
      // student screen, content, video, PDF or activation.
      final isGuardian =
          ref.read(guardianControllerProvider).valueOrNull != null;
      final isGuardianPath =
          path == parentHomePath || path.startsWith('$parentHomePath/');
      if (isGuardian && !isGuardianPath) {
        final maintenanceOn =
            ref.read(appSettingsProvider).valueOrNull?.maintenanceMode ?? false;
        if (!(maintenanceOn && path == maintenancePath)) return parentHomePath;
      }

      // Fails open: only an explicit `true` (a loaded, successful response)
      // gates the app. A still-loading or errored settings fetch must never
      // lock students out.
      final maintenanceMode =
          ref.read(appSettingsProvider).valueOrNull?.maintenanceMode ?? false;
      if (maintenanceMode) {
        if (path == loginPath) return null;
        return path == maintenancePath ? null : maintenancePath;
      }
      if (path == maintenancePath) {
        return authState.valueOrNull != null ? homePath : loginPath;
      }

      // Only the genuine first-boot session restore has no previous value —
      // force splash for that. A login/register/logout in flight is also
      // AsyncLoading (via copyWithPrevious), but carries the prior value
      // forward, so it must NOT bounce the current screen (e.g. /login) away
      // mid-request: that would unmount it before its failure handler's
      // `mounted` check can show the error SnackBar.
      if (authState.isLoading && !authState.hasValue) {
        return path == splashPath ? null : splashPath;
      }

      // First-launch (or first-launch-after-install) gates, both shown once
      // ahead of login regardless of auth state, feature intro before the
      // permissions ask. Fail open the same way maintenance/force-update do
      // above — a still-loading or errored SharedPreferences read must
      // never block the app from starting.
      final onboardingSeen =
          ref.read(onboardingSeenProvider).valueOrNull ?? true;
      if (!onboardingSeen) {
        return path == onboardingPath ? null : onboardingPath;
      }

      final permissionsOnboardingSeen =
          ref.read(permissionsOnboardingSeenProvider).valueOrNull ?? true;
      if (!permissionsOnboardingSeen) {
        return path == permissionsOnboardingPath
            ? null
            : permissionsOnboardingPath;
      }

      final isLoggedIn = authState.valueOrNull != null;
      if (isGuardian) return null;
      if (isGuardianPath) return isLoggedIn ? homePath : loginPath;
      if (path == parentAuthPath) {
        final parentAccessEnabled =
            ref.read(appSettingsProvider).valueOrNull?.parentAccessEnabled ??
            false;
        if (isLoggedIn) return homePath;
        return parentAccessEnabled ? null : loginPath;
      }
      final isAuthRoute =
          path == loginPath ||
          path == registerPath ||
          path == forgotPasswordPath;

      // Very first open (nobody ever signed in here) → "إنشاء حساب";
      // after a logout → "تسجيل الدخول". Fails toward login.
      final authEntryPath =
          (ref.read(signedInBeforeProvider).valueOrNull ?? true)
          ? loginPath
          : registerPath;

      if (path == onboardingPath || path == permissionsOnboardingPath) {
        return isLoggedIn ? homePath : authEntryPath;
      }

      if (!isLoggedIn) {
        return isAuthRoute ? null : authEntryPath;
      }

      // A temporary password from the center: nothing else is reachable
      // until it's changed (`must_change_password`).
      final mustChange = authState.valueOrNull?.mustChangePassword ?? false;
      if (mustChange) {
        return path == forceChangePasswordPath ? null : forceChangePasswordPath;
      }
      if (path == forceChangePasswordPath) return homePath;

      // The joined center was deactivated server-side (flagged by a 403 on
      // any content endpoint, or the center's own `is_active: false`) —
      // force `/center-deactivated` until the student logs out, same as
      // maintenance mode above.
      final centerDeactivated = ref.read(centerDeactivatedProvider);
      if (centerDeactivated) {
        return path == centerDeactivatedPath ? null : centerDeactivatedPath;
      }
      if (path == centerDeactivatedPath) {
        return homePath;
      }

      // Activation is no longer required: students enter right after
      // joining. The pending-activation screen is kept but never routed to.
      if (path == pendingActivationPath) {
        return homePath;
      }

      // From here on the student is logged in — always land on the main
      // shell (3-tab bottom nav) regardless of center membership.
      // [HomeScreen] itself switches between the branded home and the
      // join-by-code view depending on [centerMembershipProvider], so
      // there's no forced confinement to a center-search route here.
      if (isAuthRoute || path == splashPath) return homePath;

      // Admin screens: hidden UI for everyone else, and a deep link or
      // stale back-stack entry can't reach them either. The server must
      // still enforce the role on every `/admin/*` endpoint.
      if ((path == adminPath ||
              path.startsWith('$adminPath/') ||
              path == centerAdminPath ||
              path.startsWith('$centerAdminPath/')) &&
          !(authState.valueOrNull?.isAdmin ?? false)) {
        return homePath;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: splashPath,
        pageBuilder: (context, state) =>
            buildPageWithTransition(state: state, child: const SplashScreen()),
      ),
      GoRoute(
        path: loginPath,
        pageBuilder: (context, state) =>
            buildPageWithTransition(state: state, child: const LoginScreen()),
      ),
      GoRoute(
        path: parentAuthPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const ParentAuthScreen(),
        ),
      ),
      GoRoute(
        path: parentHomePath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          // A child's name, grades and results — FLAG_SECURE / iOS shield.
          child: const SecureScreen(child: ParentHomeScreen()),
        ),
        routes: [
          GoRoute(
            path: 'child/:id',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: SecureScreen(
                child: ParentChildScreen(
                  childId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
                ),
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: forceChangePasswordPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const ForceChangePasswordScreen(),
        ),
      ),
      GoRoute(
        path: forgotPasswordPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const ForgotPasswordScreen(),
        ),
      ),
      GoRoute(
        path: registerPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const RegisterScreen(),
        ),
      ),
      GoRoute(
        path: homePath,
        pageBuilder: (context, state) =>
            buildPageWithTransition(state: state, child: const HomeShell()),
      ),
      GoRoute(
        path: maintenancePath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const MaintenanceScreen(),
        ),
      ),
      GoRoute(
        path: forceUpdatePath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const ForceUpdateScreen(),
        ),
      ),
      GoRoute(
        path: onboardingPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const OnboardingScreen(),
        ),
      ),
      GoRoute(
        path: permissionsOnboardingPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const PermissionsOnboardingScreen(),
        ),
      ),
      GoRoute(
        path: centerSearchPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const CenterSearchScreen(),
        ),
      ),
      GoRoute(
        path: '/center-profile/:id',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: CenterProfileScreen(
            centerId: int.parse(state.pathParameters['id']!),
            preview: extraOf(state) is CenterModel
                ? extraOf(state)! as CenterModel
                : null,
          ),
        ),
      ),
      GoRoute(
        path: '/select-grade/:centerId',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: SelectGradeScreen(
            centerId: int.parse(state.pathParameters['centerId']!),
            preview: extraOf(state) is CenterModel
                ? extraOf(state)! as CenterModel
                : null,
          ),
        ),
      ),
      GoRoute(
        path: '/center-reviews/:centerId',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: AllReviewsScreen(
            centerId: int.parse(state.pathParameters['centerId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/center-review-form/:centerId',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: ReviewFormScreen(
            centerId: int.parse(state.pathParameters['centerId']!),
            existing: extraOf(state) is CenterReview
                ? extraOf(state)! as CenterReview
                : null,
          ),
        ),
      ),
      GoRoute(
        path: centerDeactivatedPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const CenterDeactivatedScreen(),
        ),
      ),
      GoRoute(
        path: pendingActivationPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const PendingActivationScreen(),
        ),
      ),
      GoRoute(
        path: contactCenterPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: ContactCenterScreen(
            preview: extraOf(state) is CenterModel
                ? extraOf(state)! as CenterModel
                : null,
          ),
        ),
      ),
      GoRoute(
        path: chatPath,
        pageBuilder: (context, state) =>
            buildPageWithTransition(state: state, child: const ChatScreen()),
      ),
      GoRoute(
        path: notificationsPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const ContentWidthLimit.page(child: NotificationsScreen()),
        ),
      ),
      GoRoute(
        path: '/courses/:id',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: CourseDetailsScreen(
            courseId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ),
      GoRoute(
        path: '/courses/:courseId/sections/:sectionId',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: SectionLessonsScreen(
            courseId: int.parse(state.pathParameters['courseId']!),
            sectionId: int.parse(state.pathParameters['sectionId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/lectures/:id',
        pageBuilder: (context, state) {
          final extra = extraOf(state);
          final navArgs = extra is LectureNavArgs
              ? extra
              : LectureNavArgs(title: extra is String ? extra : null);
          return buildPageWithTransition(
            state: state,
            child: LecturePlayerScreen(
              lectureId: int.parse(state.pathParameters['id']!),
              initialTitle: navArgs.title,
              courseExams: navArgs.courseExams,
              courseId: navArgs.courseId,
              courseTitle: navArgs.courseTitle,
              orderedLectures: navArgs.orderedLectures,
              currentIndex: navArgs.currentIndex,
            ),
          );
        },
      ),
      GoRoute(
        path: '/lectures/:lectureId/pdfs/:pdfId',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: PdfViewerScreen(
            lectureId: int.parse(state.pathParameters['lectureId']!),
            pdfId: int.parse(state.pathParameters['pdfId']!),
            initialTitle: extraOf(state) is String
                ? extraOf(state)! as String
                : null,
          ),
        ),
      ),
      // Assignments are hidden app-wide (screens kept, no routes).
      GoRoute(
        path: '/exams/:id',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: ContentWidthLimit.page(
            child: ExamDetailsScreen(
              // A malformed id lands on the screen's "لا يمكن فتح" state.
              examId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            ),
          ),
        ),
      ),
      // Deep-linkable result/review of a specific attempt.
      GoRoute(
        path: '/exams/:examId/result/:attemptId',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: ExamAttemptResultScreen(
            examId: int.parse(state.pathParameters['examId']!),
            attemptId: int.parse(state.pathParameters['attemptId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/exams/:examId/review/:attemptId',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          // Shows the correct answers — no screenshots / recording.
          child: SecureScreen(
            child: ExamReviewScreen(
              args: ExamReviewArgs(
                attemptId: int.parse(state.pathParameters['attemptId']!),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: downloadsPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const DownloadsScreen(),
        ),
      ),
      GoRoute(
        path: subjectsPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const ContentWidthLimit.page(child: SubjectsScreen()),
        ),
      ),
      GoRoute(
        path: examReviewPath,
        pageBuilder: (context, state) {
          final args = extraOf(state);
          return buildPageWithTransition(
            state: state,
            child: args is ExamReviewArgs
                ? SecureScreen(child: ExamReviewScreen(args: args))
                : const _MissingArgsScreen(),
          );
        },
      ),
      // A subject's exams — same screen as `/exams?subject=`.
      GoRoute(
        path: '/subjects/:subjectId/exams',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: ExamsScreen(
            subjectId: int.tryParse(state.pathParameters['subjectId'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: examsPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: ContentWidthLimit.page(
            child: ExamsScreen(
              subjectId: int.tryParse(
                state.uri.queryParameters['subject'] ?? '',
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: gradeChangePath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const ContentWidthLimit.page(child: GradeChangeScreen()),
        ),
      ),
      GoRoute(
        path: newsPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: ContentWidthLimit.page(
            child: NewsScreen(
              focusPostId: int.tryParse(
                state.uri.queryParameters['post'] ?? '',
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: liveSessionsPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const ContentWidthLimit.page(child: LiveSessionsScreen()),
        ),
        routes: [
          GoRoute(
            path: ':id',
            pageBuilder: (context, state) {
              final extra = extraOf(state);
              return buildPageWithTransition(
                state: state,
                child: LiveSessionScreen(
                  sessionId:
                      int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
                  subjectId: extra is int ? extra : null,
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/subject-detail/:id',
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: ContentWidthLimit.page(
            child: SubjectDetailScreen(
              subjectId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/lessons/:id',
        pageBuilder: (context, state) {
          final extra = extraOf(state);
          if (extra is! LessonDetailNavArgs) {
            // Always navigated to with extra from SubjectDetailScreen —
            // there's no standalone GET /lessons/{id} this screen could
            // otherwise fall back to fetching by id alone. A visible screen
            // with a back button, never a blank one.
            return buildPageWithTransition(
              state: state,
              child: const _MissingArgsScreen(),
            );
          }
          return buildPageWithTransition(
            state: state,
            child: ContentWidthLimit.page(
              child: LessonDetailScreen(
                lesson: extra.lesson,
                subjectId: extra.subjectId,
                subjectExams: extra.subjectExams,
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: supportPath,
        pageBuilder: (context, state) =>
            buildPageWithTransition(state: state, child: const SupportScreen()),
      ),
      GoRoute(
        path: editProfilePath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const EditProfileScreen(),
        ),
      ),
      GoRoute(
        path: changePasswordPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const ChangePasswordScreen(),
        ),
      ),
      GoRoute(
        path: mySubscriptionsPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const MySubscriptionsScreen(),
        ),
      ),
      // Center-admin dashboard (admin-only, see the redirect).
      GoRoute(
        path: centerAdminPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const CenterDashboardScreen(),
        ),
        routes: [
          GoRoute(
            path: 'students',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              // `?tab=2` opens straight on "طلبات جديدة".
              child: CenterStudentsScreen(
                initialTab:
                    int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
              ),
            ),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) => buildPageWithTransition(
                  state: state,
                  child: CenterStudentDetailScreen(
                    studentId: int.parse(state.pathParameters['id']!),
                    preview: extraOf(state) is AdminRecord
                        ? extraOf(state)! as AdminRecord
                        : null,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'subjects',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterSubjectsScreen(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) => buildPageWithTransition(
                  state: state,
                  child: CenterSubjectDetailScreen(
                    subjectId: int.parse(state.pathParameters['id']!),
                    preview: extraOf(state) is AdminRecord
                        ? extraOf(state)! as AdminRecord
                        : null,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'teachers',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterTeachersScreen(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) => buildPageWithTransition(
                  state: state,
                  child: CenterTeacherDetailScreen(
                    teacherId: int.parse(state.pathParameters['id']!),
                    preview: extraOf(state) is AdminRecord
                        ? extraOf(state)! as AdminRecord
                        : null,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'lectures',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterLecturesScreen(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) => buildPageWithTransition(
                  state: state,
                  child: CenterLectureDetailScreen(
                    lectureId: int.parse(state.pathParameters['id']!),
                    preview: extraOf(state) is AdminRecord
                        ? extraOf(state)! as AdminRecord
                        : null,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'exams',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterExamsScreen(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) => buildPageWithTransition(
                  state: state,
                  child: CenterExamResultsScreen(
                    examId: int.parse(state.pathParameters['id']!),
                    preview: extraOf(state) is AdminRecord
                        ? extraOf(state)! as AdminRecord
                        : null,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'subscriptions',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterSubscriptionsScreen(),
            ),
          ),
          GoRoute(
            path: 'notifications',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterNotificationsScreen(),
            ),
          ),
          GoRoute(
            path: 'banners',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterBannersScreen(),
            ),
          ),
          GoRoute(
            path: 'files',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterFilesScreen(),
            ),
          ),
          GoRoute(
            path: 'settings',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterSettingsScreen(),
            ),
          ),
          GoRoute(
            path: 'stats',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterStatsScreen(),
            ),
          ),
          // A pending request → activation (subjects + duration). The
          // record comes as `extra`: the server has no GET for one row.
          GoRoute(
            path: 'requests/:id',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: extraOf(state) is AdminRecord
                  ? CenterRequestApproveScreen(
                      request: extraOf(state)! as AdminRecord,
                    )
                  : const _MissingArgsScreen(),
            ),
          ),
          GoRoute(
            path: 'activation-codes',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterActivationCodesScreen(),
            ),
          ),
          GoRoute(
            path: 'inbox',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const CenterInboxScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: adminPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: const AdminDashboardScreen(),
        ),
        routes: [
          GoRoute(
            path: 'students',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const AdminStudentsScreen(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) => buildPageWithTransition(
                  state: state,
                  child: AdminStudentDetailsScreen(
                    studentId: int.parse(state.pathParameters['id']!),
                    preview: extraOf(state) is AdminStudent
                        ? extraOf(state)! as AdminStudent
                        : null,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'subjects',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const AdminSubjectsScreen(),
            ),
          ),
          GoRoute(
            path: 'schedule',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const AdminScheduleScreen(),
            ),
          ),
          GoRoute(
            path: 'subscriptions',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: AdminSubscriptionsScreen(
                initialStatus: state.uri.queryParameters['status'],
              ),
            ),
          ),
          GoRoute(
            path: 'announcements',
            pageBuilder: (context, state) => buildPageWithTransition(
              state: state,
              child: const AdminAnnouncementsScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: aboutPath,
        pageBuilder: (context, state) =>
            buildPageWithTransition(state: state, child: const AboutScreen()),
      ),
      GoRoute(
        path: activationPath,
        pageBuilder: (context, state) => buildPageWithTransition(
          state: state,
          child: ActivationScreen(
            onActivated: () {
              // "المواد" isn't a bottom-nav tab — push straight to it so the
              // newly activated course's subjects are visible immediately.
              final navContext = rootNavigatorKey.currentContext;
              if (navContext == null) return;
              navContext.pop();
              navContext.push(subjectsPath);
            },
          ),
        ),
      ),
      GoRoute(
        path: lessonPdfPath,
        pageBuilder: (context, state) {
          final args = extraOf(state);
          return buildPageWithTransition(
            state: state,
            child: args is LessonPdfArgs
                ? LessonPdfScreen(
                    title: args.title,
                    pdfUrl: args.pdfUrl,
                    downloadable: args.downloadable,
                    fileRef: args.fileRef,
                  )
                : const _MissingArgsScreen(),
          );
        },
      ),
      GoRoute(
        path: lessonAttachmentsPath,
        pageBuilder: (context, state) {
          final args = extraOf(state);
          return buildPageWithTransition(
            state: state,
            child: args is LessonAttachmentsArgs
                ? LessonAttachmentsScreen(
                    lesson: args.lesson,
                    subjectId: args.subjectId,
                  )
                : const _MissingArgsScreen(),
          );
        },
      ),
      GoRoute(
        path: lessonExamsPath,
        pageBuilder: (context, state) {
          final exams = extraOf(state);
          return buildPageWithTransition(
            state: state,
            child: exams is List<SubjectExam>
                ? LessonExamsScreen(exams: exams)
                : const _MissingArgsScreen(),
          );
        },
      ),
      GoRoute(
        path: examTakingPath,
        pageBuilder: (context, state) {
          final args = extraOf(state);
          return buildPageWithTransition(
            state: state,
            child: args is ExamTakingArgs
                // Exam questions — no screenshots / recording.
                ? SecureScreen(
                    child: ExamTakingScreen(
                      examId: args.examId,
                      title: args.title,
                      durationMinutes: args.durationMinutes,
                      questions: args.questions,
                      passPercentage: args.passPercentage,
                      attemptId: args.attemptId,
                      startedAt: args.startedAt,
                      allowReview: args.allowReview,
                    ),
                  )
                : const _MissingArgsScreen(),
          );
        },
      ),
      GoRoute(
        path: examResultPath,
        pageBuilder: (context, state) {
          final args = extraOf(state);
          return buildPageWithTransition(
            state: state,
            child: args is ExamResultArgs
                ? ExamResultScreen(
                    result: args.result,
                    questions: args.questions,
                    answers: args.answers,
                    title: args.title,
                    allowReview: args.allowReview,
                  )
                : const _MissingArgsScreen(),
          );
        },
      ),
      GoRoute(
        path: channelImagePath,
        pageBuilder: (context, state) {
          final url = extraOf(state);
          return buildPageWithTransition(
            state: state,
            child: url is String
                ? ChannelImageViewerScreen(imageUrl: url)
                : const _MissingArgsScreen(),
          );
        },
      ),
      GoRoute(
        path: imageViewerPath,
        pageBuilder: (context, state) {
          final url = extraOf(state);
          return buildPageWithTransition(
            state: state,
            child: url is String
                ? FullscreenImageViewer(imageUrl: url)
                : const _MissingArgsScreen(),
          );
        },
      ),
      // The lesson video is a real GoRouter route (opened with
      // `context.push`) rather than an imperative `Navigator.push`: routes
      // pushed straight onto the Navigator aren't tracked by GoRouter, and
      // when it reconciles its page stack they can vanish, leaving a black
      // screen on back.
      GoRoute(
        path: lessonVideoPath,
        pageBuilder: (context, state) {
          if (kDebugMode) {
            debugPrint('>>> VIDEO: route built via GoRouter push');
          }
          final extra = extraOf(state);
          return buildPageWithTransition(
            state: state,
            child: extra is LessonVideoArgs
                ? LessonVideoScreen(
                    title: extra.title,
                    videoUrl: extra.videoUrl,
                    lessonId: extra.lessonId,
                    pdfUrl: extra.pdfUrl,
                    playerKind: extra.playerKind,
                  )
                : const Scaffold(body: Center(child: Text('تعذر فتح الفيديو'))),
          );
        },
      ),
    ],
  );
});

/// `state.extra`, remembered per location. GoRouter keeps `extra` only in
/// memory and can hand a page back *without* it when it rebuilds the stack
/// (a `refreshListenable` redirect pass after returning from another screen
/// — e.g. lecture → "تواصل مع المركز" → back while the profile/subscription
/// re-check fires). Pages built from `extra` then showed "تعذر فتح الصفحة".
/// Every route reads its args through this, so a rebuild gets the same
/// args the page was first opened with.
final _extraByLocation = <String, Object>{};
const _maxRememberedExtras = 40;

Object? extraOf(GoRouterState state) {
  final key = state.uri.toString();
  final extra = state.extra;
  if (extra != null) {
    _extraByLocation.remove(key);
    _extraByLocation[key] = extra;
    if (_extraByLocation.length > _maxRememberedExtras) {
      _extraByLocation.remove(_extraByLocation.keys.first);
    }
    return extra;
  }
  return _extraByLocation[key];
}

/// Shown when a route that needs `state.extra` is reached without it (e.g. a
/// process restore that dropped the in-memory args) — a visible screen with a
/// back button instead of a blank/black one.
class _MissingArgsScreen extends StatelessWidget {
  const _MissingArgsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const Center(child: Text('تعذر فتح الصفحة')),
    );
  }
}
