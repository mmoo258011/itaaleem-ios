import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_card.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/parent/data/parent_api.dart';
import 'package:itaaleem/features/parent/data/parent_models.dart';
import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';

/// `GET /parent-code` — the code plus how many guardians follow it.
final parentCodeProvider = FutureProvider.autoDispose<ParentCodeInfo>((ref) {
  return ref.read(studentExtrasApiProvider).getParentCode();
});

/// "كود متابعة ولي الأمر" in the student's profile. Renders nothing unless
/// the global switch is on and `/profile` carried `user.parent_code`.
class ParentCodeCard extends ConsumerStatefulWidget {
  const ParentCodeCard({super.key});

  @override
  ConsumerState<ParentCodeCard> createState() => _ParentCodeCardState();
}

class _ParentCodeCardState extends ConsumerState<ParentCodeCard> {
  bool _regenerating = false;

  Future<void> _regenerate(int linked) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تجديد كود المتابعة'),
        content: Text(
          linked > 0
              ? 'هيتعمل كود جديد، وأولياء الأمور المربوطين دلوقتي ($linked) '
                    'هيتفك ربطهم ومش هيقدروا يتابعوك غير لما يضيفوا الكود الجديد.'
              : 'هيتعمل كود جديد، وأي ولي أمر مربوط بالكود القديم هيتفك ربطه '
                    'ومش هيقدر يتابعك غير لما يضيف الكود الجديد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('تجديد الكود'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _regenerating = true);
    try {
      final info = await ref
          .read(studentExtrasApiProvider)
          .regenerateParentCode();
      if (!mounted) return;
      ref.invalidate(parentCodeProvider);
      AppToast.showSuccess(context, info.message ?? 'تم تجديد كود المتابعة');
      // `user.parent_code` in the profile changed too.
      await ref.read(authControllerProvider.notifier).refreshProfile();
    } on ParentApiException catch (e) {
      if (mounted) AppToast.showError(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        ref.watch(appSettingsProvider).valueOrNull?.parentAccessEnabled ??
        false;
    final profileCode = ref.watch(
      authControllerProvider.select((s) => s.valueOrNull?.parentCode),
    );
    if (!enabled || profileCode == null) return const SizedBox.shrink();

    final info = ref.watch(parentCodeProvider).valueOrNull;
    final code = info?.parentCode.isNotEmpty == true
        ? info!.parentCode
        : profileCode;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.family_restroom_rounded, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'كود متابعة ولي الأمر',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'ادّي الكود ده لولي أمرك عشان يتابع تقدّمك ونتايجك من التطبيق.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(
                  code,
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              info == null
                  ? ' '
                  : info.linkedParentsCount == 0
                  ? 'مفيش ولي أمر مربوط لسه'
                  : 'عدد أولياء الأمور المربوطين: ${info.linkedParentsCount}',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) {
                        AppToast.showSuccess(context, 'تم نسخ الكود');
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('نسخ'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _regenerating
                        ? null
                        : () => _regenerate(info?.linkedParentsCount ?? 0),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                    icon: _regenerating
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('تجديد'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
