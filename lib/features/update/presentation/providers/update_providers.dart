import 'package:itaaleem/core/utils/result.dart';
import 'package:itaaleem/features/update/data/repositories/update_repository_impl.dart';
import 'package:itaaleem/features/update/domain/entities/app_version_info.dart';
import 'package:itaaleem/features/update/domain/usecases/get_app_version_usecase.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/device/device_identity_service.dart'
    show appVersionParts;
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:shared_preferences/shared_preferences.dart';

final getAppVersionUseCaseProvider = Provider<GetAppVersionUseCase>((ref) {
  return GetAppVersionUseCase(ref.watch(updateRepositoryProvider));
});

/// `GET /public/app-version`, checked after splash and re-checked when
/// [ForceUpdateScreen] comes back from the background.
final appVersionInfoProvider = FutureProvider<AppVersionInfo>((ref) async {
  final useCase = ref.watch(getAppVersionUseCaseProvider);
  final result = await useCase();
  return switch (result) {
    Ok<AppVersionInfo>(:final value) => value,
    Err<AppVersionInfo>(:final failure) => throw failure,
  };
});

/// Whether the installed build (`package_info_plus`) is behind the
/// published one, and if so whether the update is mandatory. Resolves to
/// `null` when there's nothing to show (up to date, or the version check
/// itself failed — network, 5xx, timeout, malformed body). Fails open so a
/// flaky endpoint never locks students out; a failed *re*-check (e.g. on
/// resume from [ForceUpdateScreen]) also resolves to `null`, releasing it.
final updateStatusProvider = FutureProvider<UpdateStatus?>((ref) async {
  try {
    final info = await ref.watch(appVersionInfoProvider.future);
    final installed = await appVersionParts();
    return computeUpdateStatus(
      info,
      currentVersion: installed.version,
      currentBuild: int.tryParse(installed.build),
      isIOS: PlatformUtils.isIOS,
    );
  } catch (_) {
    return null;
  }
});

/// The pure decision behind [updateStatusProvider]:
/// - newer when `latest_version` is ahead (numeric, segment by segment), or
///   the same version with a higher `latest_build`;
/// - forced only when newer *and* `force_update` is true, or when the
///   installed build is below `min_build`.
UpdateStatus? computeUpdateStatus(
  AppVersionInfo info, {
  required String currentVersion,
  required int? currentBuild,
  required bool isIOS,
}) {
  if (currentVersion.isEmpty) return null;
  final belowMinBuild =
      info.minBuild != null &&
      currentBuild != null &&
      currentBuild < info.minBuild!;
  var newer =
      info.latestVersion.isNotEmpty &&
      isNewerVersion(info.latestVersion, currentVersion);
  if (!newer &&
      info.latestBuild != null &&
      currentBuild != null &&
      (info.latestVersion.isEmpty ||
          compareVersions(info.latestVersion, currentVersion) == 0)) {
    newer = info.latestBuild! > currentBuild;
  }
  if (!newer && !belowMinBuild) return null;
  return UpdateStatus(
    forceUpdate: belowMinBuild || (newer && info.forceUpdate),
    latestVersion: info.latestVersion.isEmpty
        ? currentVersion
        : info.latestVersion,
    latestBuild: info.latestBuild,
    currentVersion: currentVersion,
    message: info.message,
    updateUrl: resolveUpdateUrl(info, isIOS: isIOS),
  );
}

/// Where "تحديث" leads: the server's `update_url`, else this platform's
/// store, else the website. On iOS a Play link in `update_url` is ignored.
String resolveUpdateUrl(AppVersionInfo info, {required bool isIOS}) {
  bool usable(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !isAllowedLaunchUri(uri)) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return isIOS
        ? !host.contains('play.google.com')
        : !host.contains('apps.apple.com');
  }

  final store = isIOS
      ? (info.appStoreUrl ?? appStoreFallbackUrl)
      : (info.playStoreUrl ?? playStoreFallbackUrl);
  for (final url in [info.updateUrl, store]) {
    if (usable(url)) return url!;
  }
  return websiteFallbackUrl;
}

const playStoreFallbackUrl =
    'https://play.google.com/store/apps/details?id=com.itaaleem.app';
const appStoreFallbackUrl = 'https://apps.apple.com/app/id6820105054';
const websiteFallbackUrl = 'https://itaaleem.com/app';

/// Compares two dotted version strings (`"1.2.10"` vs `"1.3.0"`)
/// numerically, segment by segment — a plain string compare would get
/// `"1.9.0" > "1.10.0"` wrong.
int compareVersions(String a, String b) {
  List<int> segments(String v) => v
      .split('.')
      .map((part) => int.tryParse(RegExp(r'^\d+').stringMatch(part) ?? '') ?? 0)
      .toList();

  final aSegments = segments(a);
  final bSegments = segments(b);
  final length = aSegments.length > bSegments.length
      ? aSegments.length
      : bSegments.length;

  for (var i = 0; i < length; i++) {
    final x = i < aSegments.length ? aSegments[i] : 0;
    final y = i < bSegments.length ? bSegments[i] : 0;
    if (x != y) return x > y ? 1 : -1;
  }
  return 0;
}

bool isNewerVersion(String latest, String current) =>
    compareVersions(latest, current) > 0;

class UpdateStatus {
  const UpdateStatus({
    required this.forceUpdate,
    required this.latestVersion,
    required this.currentVersion,
    this.latestBuild,
    this.message,
    this.updateUrl,
  });

  final bool forceUpdate;
  final String latestVersion;
  final int? latestBuild;
  final String currentVersion;
  final String? message;
  final String? updateUrl;

  /// Identifies this update for "don't offer it again" on the banner.
  String get key =>
      latestBuild == null ? latestVersion : '$latestVersion+$latestBuild';
}

/// The optional update the student closed the banner for — persisted, so
/// the same version is never offered again (a newer one is).
final dismissedUpdateProvider =
    StateNotifierProvider<DismissedUpdateNotifier, String?>(
      (ref) => DismissedUpdateNotifier(),
    );

class DismissedUpdateNotifier extends StateNotifier<String?> {
  DismissedUpdateNotifier() : super(null) {
    _load();
  }

  static const _prefsKey = 'update_banner_dismissed_version';
  bool _dismissedThisSession = false;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      if (mounted && !_dismissedThisSession) state = stored;
    } catch (_) {}
  }

  Future<void> dismiss(String key) async {
    _dismissedThisSession = true;
    state = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, key);
    } catch (_) {}
  }
}
