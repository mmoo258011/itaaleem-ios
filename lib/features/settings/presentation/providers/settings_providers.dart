import 'package:itaaleem/core/utils/result.dart';
import 'package:itaaleem/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:itaaleem/features/settings/domain/entities/app_settings.dart';
import 'package:itaaleem/features/settings/domain/usecases/get_app_settings_usecase.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/features/app_config/app_config.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart';

final getAppSettingsUseCaseProvider = Provider<GetAppSettingsUseCase>((ref) {
  return GetAppSettingsUseCase(ref.watch(settingsRepositoryProvider));
});

/// `GET /public/settings` as the server sent it.
final remoteAppSettingsProvider = FutureProvider<AppSettings>((ref) async {
  final useCase = ref.watch(getAppSettingsUseCaseProvider);
  final result = await useCase();
  return switch (result) {
    Ok<AppSettings>(:final value) => value,
    Err<AppSettings>(:final failure) => throw failure,
  };
});

/// The effective settings: `/public/settings` with `GET /app-config` laid
/// over it (see [applyAppConfig]). Errors only when `/public/settings`
/// fails and `app-config` has nothing either — same as before.
final appSettingsProvider = FutureProvider<AppSettings>((ref) async {
  final config = ref.watch(currentAppConfigProvider);
  try {
    return applyAppConfig(
      await ref.watch(remoteAppSettingsProvider.future),
      config,
    );
  } catch (_) {
    if (identical(config, AppConfig.empty)) rethrow;
    return applyAppConfig(const AppSettings(), config);
  }
});

/// Retry from the maintenance screen / pull-to-refresh: both sources.
void reloadAppSettings(WidgetRef ref) {
  ref.invalidate(remoteAppSettingsProvider);
  refreshAppConfig(ref);
}
