import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/network/connectivity_provider.dart';
import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';
import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';
import 'package:itaaleem/features/update/presentation/providers/update_providers.dart';

/// Loads that would otherwise stay failed until a restart, tried again.
/// Only failed ones: a good answer is never refetched here.
void retryFailedLoads(
  ProviderReader read,
  void Function(ProviderOrFamily) invalidate,
) {
  retryFailedCenters(read);
  if (read(remoteAppSettingsProvider).hasError) {
    invalidate(remoteAppSettingsProvider);
  }
  if (read(appVersionInfoProvider).hasError) invalidate(appVersionInfoProvider);
}

/// Kept alive by [App]: [retryFailedLoads] when the connection comes back
/// and when the app returns from the background.
final loadRecoveryProvider = Provider<void>((ref) {
  void retry() => retryFailedLoads(ref.read, ref.invalidate);
  ref.listen(connectivityStatusProvider.select((s) => s.valueOrNull), (
    prev,
    next,
  ) {
    if (prev == false && next == true) retry();
  });
  final lifecycle = AppLifecycleListener(onResume: retry);
  ref.onDispose(lifecycle.dispose);
});
