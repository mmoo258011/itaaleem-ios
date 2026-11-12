import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';

export 'package:itaaleem/features/smart_ui/smart_ui_session.dart';

/// Set when the smart UI failed while the network was up: the student goes
/// back to the native app until the next launch (memory only, on purpose).
final smartUiFallbackProvider = StateProvider<bool>((ref) => false);

/// Whether the signed-in student lands on the smart UI instead of `/home`.
final opensSmartShellProvider = Provider<bool>((ref) {
  final student = ref.watch(authControllerProvider).valueOrNull;
  return (student?.opensSmartUi ?? false) &&
      !ref.watch(smartUiFallbackProvider);
});
