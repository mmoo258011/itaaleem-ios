import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;
import 'package:itaaleem/features/courses/domain/entities/course_details.dart'
    show LectureNavArgs;
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/app/router/route_args.dart';
import 'package:itaaleem/core/content/content_policy.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/auth/presentation/widgets/delete_account_confirm.dart';
import 'package:itaaleem/features/auth/presentation/widgets/logout_confirm.dart';
import 'package:itaaleem/features/courses/domain/entities/lecture_details.dart';
import 'package:itaaleem/features/courses/presentation/providers/courses_providers.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:itaaleem/core/utils/youtube_utils.dart';
import 'package:itaaleem/features/settings/presentation/rate_app.dart';
import 'package:itaaleem/features/smart_ui/smart_payment.dart';
import 'package:itaaleem/features/smart_ui/smart_ui_bridge.dart';
import 'package:itaaleem/features/smart_ui/smart_ui_session.dart';
import 'package:itaaleem/features/subjects/data/content_file_access.dart';
import 'package:itaaleem/features/video/data/offline/offline_download_manager.dart';

/// Carries out a validated request from the smart UI. Every link is fetched
/// here with the student's token: the page only ever names an id.
Future<void> handleSmartBridgeMessage(
  BuildContext context,
  WidgetRef ref,
  SmartBridgeMessage message,
) async {
  switch (message) {
    case Haptic():
      await HapticFeedback.mediumImpact();
    case OpenDownloads():
      await context.push(downloadsPath);
    case OpenPdf(:final lessonId, :final attachmentId):
      final fileRef = lessonId != null
          ? ContentFileRef.lesson(lessonId)
          : ContentFileRef.attachment(attachmentId!);
      // The native viewer: cached download with progress, the center's
      // watermark, FLAG_SECURE / iOS shield.
      await context.push(
        lessonPdfPath,
        extra: LessonPdfArgs(title: 'ملف PDF', pdfUrl: null, fileRef: fileRef),
      );
    case PlayVideo(:final lessonId):
      // The native lecture player: fetches `/lessons/{id}` with the
      // student's token, plays from a completed download when there is one.
      // A fresh fetch on every tap: the details provider keeps its last
      // result (also a failure) for the whole app session.
      ref.invalidate(lectureDetailsProvider(lessonId));
      const args = LectureNavArgs(videoOnly: true);
      await context.push('/lectures/$lessonId', extra: args);
    case DownloadLesson(:final lessonId):
      await _downloadLesson(context, ref, lessonId);
    case RateMoment():
      SmartShellHooks.onPositiveMoment?.call();
    case OpenStoreRating():
      await openRateApp(context);
    case Logout():
      // Same as «حسابي»: confirms when downloads would be removed; the
      // account wipe also clears the smart UI's cookies.
      await confirmAndLogout(context, ref);
    case DeleteAccount():
      await confirmAndDeleteAccount(context, ref);
    case AppInfo():
      await context.push(appInfoPath);
    case Reload():
      await SmartShellHooks.reload?.call();
    case OpenExternalLink(:final url):
      // The teacher's social / contact page: its own app or the browser.
      await launchUrlSafely(url, mode: LaunchMode.externalApplication);
    case OpenPayment(:final orderId):
      await _pay(context, ref, orderId);
  }
}

/// Where [OfflineDownloadManager] downloads this lesson's video from: our
/// own server's file, or a YouTube video (fetched with youtube_explode) —
/// the same lessons the old lesson screen offered a download for. Whether
/// downloads are allowed at all is the center's `can_download_video`.
String? downloadSourceOf(LectureDetails details) {
  for (final video in details.videos) {
    final url = video.videoUrl?.trim() ?? '';
    switch (video.provider) {
      case VideoProvider.privateServer:
        if (url.isNotEmpty) return url;
      case VideoProvider.youtube:
        if (url.isNotEmpty && isYouTubeUrl(url)) return url;
        final id = video.providerVideoId?.trim() ?? '';
        if (id.isNotEmpty) return 'https://youtu.be/$id';
      case VideoProvider.unknown:
        if (url.isNotEmpty && isYouTubeUrl(url)) return url;
      case VideoProvider.bunny:
      case VideoProvider.vimeo:
        break;
    }
  }
  return null;
}

Future<void> _downloadLesson(
  BuildContext context,
  WidgetRef ref,
  int lessonId,
) async {
  if (!ref.read(contentPolicyProvider).canDownloadVideo) {
    AppToast.showError(context, 'التحميل غير مسموح من قبل السنتر');
    return;
  }
  try {
    final details = await ref.read(lectureDetailsProvider(lessonId).future);
    final source = downloadSourceOf(details);
    if (kDebugMode) {
      debugPrint(
        '[SmartShell] download_lesson($lessonId): '
        '${details.videos.length} video(s), '
        'providers=${details.videos.map((v) => v.provider.name).toList()}, '
        'source=${source == null ? 'none' : 'found'}',
      );
    }
    if (!context.mounted) return;
    if (source == null) {
      AppToast.showError(context, 'الدرس ده مش متاح للتحميل');
      return;
    }
    final manager = ref.read(offlineDownloadManagerProvider);
    if (await manager.isFullyDownloaded(lessonId)) {
      if (context.mounted) {
        AppToast.showInfo(
          context,
          'الدرس ده متحمّل بالفعل — تلاقيه في «التحميلات»',
        );
      }
      return;
    }
    if (!context.mounted) return;
    // The encrypted offline store "التحميلات" plays from. Runs until the
    // file is complete (failures land on its row there), so not awaited.
    unawaited(
      manager
          .startDownload(
            lessonId,
            sourceUrl: source,
            lessonTitle: details.title,
          )
          .catchError((Object e) {
            if (kDebugMode) debugPrint('[SmartShell] download failed: $e');
            if (context.mounted) AppToast.showError(context, e.toString());
          }),
    );
    AppToast.showInfo(context, 'بدأ التحميل — تابعه من «التحميلات»');
  } catch (e) {
    if (kDebugMode) debugPrint('[SmartShell] download_lesson($lessonId): $e');
    if (context.mounted) AppToast.showError(context, 'تعذر بدء التحميل');
  }
}

/// Where payment links come from. Not connected yet (see
/// [smartPaymentsEnabled]); swap in the API source once the server has it.
final paymentLinkSourceProvider = Provider<PaymentLinkSource>(
  (ref) => const PendingPaymentLinkSource(),
);

final paymentFlowProvider = Provider<PaymentFlow>(
  (ref) => PaymentFlow(links: ref.watch(paymentLinkSourceProvider)),
);

Future<void> _pay(BuildContext context, WidgetRef ref, int orderId) async {
  // No purchases on iOS (the app shows no prices or subscriptions there).
  if (PlatformUtils.isIOS) return;
  try {
    final route = await ref.read(paymentFlowProvider).pay(orderId);
    if (route != null) SmartShellHooks.openHash?.call(route);
  } on PaymentUnavailableException {
    if (context.mounted) {
      AppToast.showError(context, PaymentUnavailableException.message);
    }
  }
}
