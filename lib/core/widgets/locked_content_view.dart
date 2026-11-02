import 'package:flutter/material.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart'
    show serverText;
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/features/activation/presentation/screens/activation_screen.dart'
    show pushActivationScreen;
import 'package:itaaleem/features/subscriptions/presentation/widgets/contact_center_access_sheet.dart'
    show lockedContentMessage;

/// Shown in place of content the student hasn't unlocked (a 403
/// `{locked: true}` or `has_access: false`): a lock, the subscribers-only
/// message and "تفعيل بكود". On iOS (subscriptions hidden) only "contact the
/// center", no activation button.
class LockedContentView extends StatelessWidget {
  const LockedContentView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hide = PlatformUtils.hideSubscriptions;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: scheme.primaryContainer,
              child: Icon(
                Icons.lock_rounded,
                size: 36,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hide
                  ? serverText(context, 'locked_content', lockedContentMessage)
                  : lockedForSubscribersMessage,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (!hide) ...[
              const SizedBox(height: AppSpacing.lg),
              const ActivateWithCodeButton(),
            ],
          ],
        ),
      ),
    );
  }
}

/// "تفعيل بكود" → the activation screen. Renders nothing on iOS.
class ActivateWithCodeButton extends StatelessWidget {
  const ActivateWithCodeButton({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (PlatformUtils.hideSubscriptions) return const SizedBox.shrink();
    return FilledButton.tonalIcon(
      style: dense
          ? FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(48, 36),
            )
          : null,
      onPressed: pushActivationScreen,
      icon: const Icon(Icons.vpn_key_rounded, size: 18),
      label: const Text('تفعيل بكود'),
    );
  }
}
