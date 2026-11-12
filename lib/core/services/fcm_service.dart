import 'dart:convert';

import 'package:itaaleem/features/smart_ui/smart_push_routes.dart';
import 'package:itaaleem/features/smart_ui/smart_ui_session.dart';
import 'package:itaaleem/features/grade_change/grade_change_screen.dart'
    show gradeChangePath;
import 'dart:async';
import 'package:itaaleem/features/news/presentation/news_routes.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/device/device_identity_service.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/features/center_admin/presentation/center_admin_routes.dart';

/// Lets the guardian ("ولي الأمر") session plug into push handling without
/// this core service depending on that feature — set once from `App`.
class GuardianPushHooks {
  const GuardianPushHooks({
    required this.isGuardianMode,
    required this.sendToken,
    required this.openChild,
  });

  /// Whether the signed-in session is a guardian one.
  final bool Function() isGuardianMode;

  /// `POST /parent/fcm-token`.
  final Future<void> Function(String token) sendToken;

  /// Opens a child's page (`data.student_id`).
  final void Function(int studentId) openChild;
}

/// The interactive half of push notifications — permission + token
/// registration, foreground display, and tap-to-navigate. Firebase itself
/// (`Firebase.initializeApp()`) and the background-message handler are
/// bootstrapped earlier, in `NotificationService.bootstrap()` (called from
/// `main()` before this service is ever touched), since those must be set
/// up unconditionally at process start — before it's even known whether
/// this is a demo session.
///
/// ⚠️ Needs a Firebase project: drop `google-services.json` into
/// `android/app/` and `GoogleService-Info.plist` into `ios/Runner/` (get
/// both from the Firebase console for this app's Android/iOS bundle ids —
/// `com.itaaleem.app`). Every method here is guarded by [isConfigured], so
/// the app runs identically with neither file present — push notifications
/// just silently never register.
class FcmService {
  FcmService(this._dio, this._deviceIdentityService);

  final Dio _dio;
  final DeviceIdentityService _deviceIdentityService;

  final _localNotifications = FlutterLocalNotificationsPlugin();

  GuardianPushHooks? guardianHooks;

  bool get _isGuardianMode => guardianHooks?.isGuardianMode() ?? false;

  /// The channel the guardian pushes are sent on.
  static const _guardianChannel = AndroidNotificationChannel(
    'high_importance_channel',
    'متابعة ولي الأمر',
    description: 'نتائج الامتحانات ومتابعة دخول الطالب',
    importance: Importance.high,
  );

  static const _androidChannel = AndroidNotificationChannel(
    'fcm_default_channel',
    'إشعارات عامة',
    description: 'إشعارات المحاضرات والامتحانات والإعلانات',
    importance: Importance.high,
  );

  /// Whether `Firebase.initializeApp()` (in `NotificationService.bootstrap`)
  /// succeeded — see that class's doc for why this is checked live instead
  /// of cached.
  static bool get isConfigured => Firebase.apps.isNotEmpty;

  bool _permissionAsked = false;
  bool _listenersReady = false;

  /// The signed-in (non-demo) student this device's token belongs to, and the
  /// `studentId:token` pair last accepted by the backend — a token is only
  /// re-sent when either changes (or a previous attempt failed), so the
  /// repeated calls from `App`'s auth listener cost nothing.
  int? _studentId;
  String? _registeredKey;

  /// A tapped push that launched the app from fully terminated. Held until a
  /// session exists ([flushPendingNavigation]) — navigating during the splash
  /// / login redirect would just be discarded.
  ({Object? type, Object? id, Map<String, dynamic> data})? _pendingNavigation;

  /// Asks for notification permission once (Android 13+ `POST_NOTIFICATIONS`,
  /// iOS), then registers this device's FCM token for [studentId] with the
  /// backend and keeps it fresh via [FirebaseMessaging.onTokenRefresh].
  /// Safe to call repeatedly (login, session restore, profile refreshes): the
  /// permission prompt and refresh listener are set up once, and the token is
  /// re-sent only when it or the student changed or the last attempt failed.
  /// No-ops entirely if Firebase isn't configured.
  Future<void> init([int? studentId]) async {
    if (kDebugMode) {
      debugPrint('>>> FCM init: configured=$isConfigured student=$studentId');
    }
    if (!isConfigured) return;
    if (studentId != null) _studentId = studentId;

    await _ensurePermissionAndRefreshListener();

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) {
        debugPrint('>>> FCM TOKEN: $token');
      }
      if (token != null) await _registerToken(token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('>>> FCM getToken failed: $e');
      }
    }
  }

  /// Guardian session: same permission ask and refresh listener as [init],
  /// but the token goes to `POST /parent/fcm-token` (via [guardianHooks]).
  Future<void> initGuardian() async {
    if (!isConfigured) return;
    await _ensurePermissionAndRefreshListener();
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } catch (e) {
      if (kDebugMode) debugPrint('>>> FCM guardian getToken failed: $e');
    }
  }

  Future<void> _ensurePermissionAndRefreshListener() async {
    if (!_permissionAsked) {
      _permissionAsked = true;
      try {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        if (kDebugMode) {
          debugPrint('>>> FCM permission: ${settings.authorizationStatus}');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[FcmService] requestPermission failed: $e');
      }
      FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);
    }
  }

  Future<void> _registerToken(String token) async {
    final hooks = guardianHooks;
    if (hooks != null && hooks.isGuardianMode()) {
      final key = 'guardian:$token';
      if (key == _registeredKey) return;
      try {
        await hooks.sendToken(token);
        _registeredKey = key;
      } catch (e) {
        if (kDebugMode) debugPrint('[FcmService] POST /parent/fcm-token: $e');
      }
      return;
    }
    final studentId = _studentId;
    // Signed out (e.g. the refresh fired right after logout): the request would
    // just 401 — the next login sends the token inline and via init().
    if (studentId == null) return;
    final key = '$studentId:$token';
    if (key == _registeredKey) return;
    try {
      // Both keys: `/login` already takes `fcm_token`, this endpoint `token`.
      // Same `device_id` as `/login`, so the backend ties the token to this device.
      final device = await _deviceIdentityService.getIdentity();
      final response = await _dio.post<dynamic>(
        ApiEndpoints.fcmToken,
        data: {'token': token, 'fcm_token': token, ...device.toJson()},
      );
      _registeredKey = key;
      if (kDebugMode) {
        debugPrint('>>> FCM TOKEN sent to server: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '>>> FCM TOKEN sent to server FAILED: '
          '${e.response?.statusCode} ${e.response?.data ?? e.message}',
        );
      }
    } catch (e) {
      // Best-effort — a failed registration is retried by the next init()
      // (login / session restore / auth state change) or token refresh; never
      // worth surfacing to the student.
      if (kDebugMode) debugPrint('[FcmService] POST /fcm-token failed: $e');
    }
  }

  /// Opens the screen for a push that launched the app, once a session exists.
  void flushPendingNavigation() {
    final pending = _pendingNavigation;
    if (pending == null) return;
    _pendingNavigation = null;
    // After the router has settled on the home shell.
    Future<void>.delayed(
      const Duration(milliseconds: 600),
      () => _navigateForType(pending.type, pending.id, pending.data),
    );
  }

  /// Sets up the local-notification plugin plus every FCM message listener:
  /// [FirebaseMessaging.onMessage] (shown as a native local notification —
  /// FCM never puts one up itself while the app is foregrounded) and
  /// [FirebaseMessaging.onMessageOpenedApp] / a tapped local notification
  /// (both navigate via [_navigateForType]). Safe to call on every `App`
  /// rebuild — internally idempotent, and a no-op without Firebase
  /// configured.
  Future<void> setupListeners() async {
    if (!isConfigured || _listenersReady) return;
    _listenersReady = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
      onDidReceiveNotificationResponse: (response) {
        _navigateForPayload(response.payload);
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_guardianChannel);

    FirebaseMessaging.onMessage.listen((message) {
      final type = _pushKind(message.data);
      if (type is String) _foregroundTypes.add(type);
      if (kDebugMode) {
        debugPrint(
          '>>> FCM onMessage: title=${message.notification?.title}, body=${message.notification?.body}',
        );
      }
      _showLocalNotification(message);
    });
    if (kDebugMode) {
      debugPrint('>>> FCM listeners registered');
    }
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _navigateForType(
        _typeOf(message.data),
        _targetId(message.data),
        message.data,
      ),
    );
    // A push that launched the app from fully terminated never fires
    // onMessageOpenedApp (the app wasn't running yet to listen) — this is
    // the one-time equivalent for that case.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _pendingNavigation = (
        type: _typeOf(initialMessage.data),
        id: _targetId(initialMessage.data),
        data: initialMessage.data,
      );
      // The session may already be up by the time this resolves.
      if (_studentId != null || _isGuardianMode) flushPendingNavigation();
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] as String?;
    final body = notification?.body ?? message.data['body'] as String?;
    if (title == null || title.isEmpty) return;

    await _localNotifications.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _navigateForPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _navigateForType(_typeOf(data), _targetId(data), data);
    } catch (e) {
      if (kDebugMode) debugPrint('[FcmService] bad notification payload: $e');
    }
  }

  /// A push for the center admin's own inbox (`data.source ==
  /// "center_inbox"`, or the older `activation_code_redeemed` type) maps to
  /// [_centerInboxType]; every other push keeps its own `type`.
  static Object? _typeOf(Map<String, dynamic> data) =>
      data['source'] == 'center_inbox' ||
          data['type'] == 'activation_code_redeemed'
      ? _centerInboxType
      : _pushKind(data);

  /// `content_type` refines a `general` push (e.g. `grade_change`, sent as
  /// `general` so older app versions still list it).
  static Object? _pushKind(Map<String, dynamic> data) =>
      data['type'] == 'general' && data['content_type'] is String
      ? data['content_type']
      : data['type'];

  static const _centerInboxType = '__center_inbox__';

  static final _foregroundTypes = StreamController<String>.broadcast();

  /// `data.type` of every push received while the app is open — lets a
  /// screen refresh itself (e.g. the news red dot) without a pull.
  static Stream<String> get foregroundTypes => _foregroundTypes.stream;

  static bool _isGuardianType(Object? type) =>
      type == 'parent_exam_result' || type == 'parent_student_inactive';

  static Object? _targetId(Map<String, dynamic> data) =>
      _isGuardianType(data['type'])
      ? data['student_id']
      : data['type'] == 'live_session'
      ? data['live_session_id']
      : data['type'] == 'news'
      ? data['post_id']
      : data['id'] ??
            data['lecture_id'] ??
            data['exam_id'] ??
            data['assignment_id'] ??
            data['target_id'];

  /// Routes a tapped push to the right screen: a lecture opens the internal
  /// video player, an exam opens its details/attempt screen, anything else
  /// (or a type/id the app doesn't recognize) falls back to "الإشعارات" —
  /// per the spec's "type = lecture → video player, exam → exams screen".
  void _navigateForType(
    Object? type,
    Object? id, [
    Map<String, dynamic> data = const {},
  ]) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final parsedId = id is num
        ? id.toInt()
        : int.tryParse(id?.toString() ?? '');

    // A guardian push only opens in a guardian session, and a guardian
    // session never opens a student screen — anything else is ignored.
    if (_isGuardianType(type) || _isGuardianMode) {
      if (_isGuardianType(type) && _isGuardianMode && parsedId != null) {
        guardianHooks?.openChild(parsedId);
      }
      return;
    }

    // Smart UI students: the push opens inside the shell.
    // (Center-inbox pushes are for staff, who never get the shell.)
    if (SmartShellHooks.active && type != _centerInboxType) {
      final hash = smartHashForPush(data);
      final open = SmartShellHooks.openHash;
      if (open != null) {
        open(hash);
      } else {
        SmartShellHooks.pendingHash = hash;
      }
      return;
    }

    switch (type) {
      case _centerInboxType:
        context.push(centerAdminInboxPath);
      case 'lecture' when parsedId != null:
        context.push('/lectures/$parsedId');
      case 'exam' when parsedId != null:
        context.push('/exams/$parsedId');
      case 'live_session' when parsedId != null:
        context.push('/live-sessions/$parsedId');
      case 'grade_change':
        context.push(gradeChangePath);
      case 'news':
        // Opens the channel (on the post when known); the screen itself
        // shows «القناة مش متاحة» if the channel was switched off since.
        context.push(parsedId != null ? newsPostPath(parsedId) : newsPath);
      default:
        context.go(notificationsPath);
    }
  }

  /// Logout: the push token itself is deleted ([deleteLocalToken]) and
  /// `POST /logout` revokes the session, so the server can't reach this
  /// device any more — no separate `DELETE /fcm-token` call.
  Future<void> unregisterFromServer() async {}

  /// Unregisters this device from FCM and forgets its local token — called
  /// on logout (see `AuthController`) so a signed-out device stops
  /// receiving another student's pushes on a shared device.
  Future<void> deleteLocalToken() async {
    _studentId = null;
    _registeredKey = null;
    if (!isConfigured) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      if (kDebugMode) debugPrint('[FcmService] deleteToken failed: $e');
    }
  }
}

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(
    ref.watch(dioClientProvider),
    ref.watch(deviceIdentityServiceProvider),
  );
});
