import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_button.dart';
import 'package:itaaleem/core/widgets/app_card.dart';
import 'package:itaaleem/core/widgets/app_empty_state.dart';
import 'package:itaaleem/core/widgets/app_error_state.dart';
import 'package:itaaleem/core/widgets/app_input.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/parent/data/parent_api.dart';
import 'package:itaaleem/features/parent/data/parent_models.dart';
import 'package:itaaleem/features/parent/presentation/guardian_controller.dart';
import 'package:itaaleem/features/parent/presentation/widgets/parent_format.dart';

const parentHomePath = '/parent';
const parentAuthPath = '/parent-auth';
String parentChildPath(int id) => '/parent/child/$id';

/// Guardian home: the linked children (`GET /parent/children`), "إضافة ابن"
/// by code, pull to refresh and sign-out. Nothing here opens content.
class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('عاوز تسجّل خروج من حساب ولي الأمر؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(guardianControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final guardian = ref.watch(guardianControllerProvider).valueOrNull;
    final childrenAsync = ref.watch(guardianChildrenProvider);
    // Seeded from the session while the first fetch is in flight.
    final children = childrenAsync.valueOrNull ?? guardian?.children;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text(
          'متابعة الأبناء',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: Icon(Icons.logout_rounded, color: scheme.error),
            onPressed: () => _confirmLogout(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddChildSheet(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'إضافة ابن',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(guardianChildrenProvider);
          try {
            await ref.read(guardianChildrenProvider.future);
          } catch (_) {}
        },
        child: Builder(
          builder: (context) {
            if (childrenAsync.hasError && children == null) {
              return _Fill(
                child: AppErrorState(
                  message: ParentApiException.from(
                    childrenAsync.error!,
                  ).displayMessage,
                  onRetry: () => ref.invalidate(guardianChildrenProvider),
                ),
              );
            }
            if (children == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (children.isEmpty) {
              return const _Fill(
                child: AppEmptyState(
                  icon: Icons.family_restroom_rounded,
                  title: 'مفيش طلاب متاحين للمتابعة حالياً',
                ),
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                96,
              ),
              children: [
                if (guardian != null && guardian.name.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      'أهلاً، ${guardian.name}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                for (final child in children)
                  Padding(
                    key: ValueKey(child.id),
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _ChildCard(child: child),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.child});

  final ParentChild child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: () => context.push(parentChildPath(child.id)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.school_rounded, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  child.name,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (child.course.isNotEmpty)
                  Text(
                    child.course,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (child.center.isNotEmpty)
                  Text(
                    child.center,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'آخر دخول: ${formatLastLogin(child.lastLoginAt)}',
                  style: text.labelSmall?.copyWith(color: scheme.primary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_left_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _Fill extends StatelessWidget {
  const _Fill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(height: constraints.maxHeight, child: child),
      ),
    );
  }
}

/// "إضافة ابن": `POST /parent/children {parent_code}`.
Future<void> showAddChildSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AddChildSheet(),
  );
}

class _AddChildSheet extends ConsumerStatefulWidget {
  const _AddChildSheet();

  @override
  ConsumerState<_AddChildSheet> createState() => _AddChildSheetState();
}

class _AddChildSheetState extends ConsumerState<_AddChildSheet> {
  final _code = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final message = await ref
          .read(guardianControllerProvider.notifier)
          .api
          .addChild(_code.text.trim());
      if (!mounted) return;
      ref.invalidate(guardianChildrenProvider);
      Navigator.pop(context);
      AppToast.showSuccess(context, message);
    } on ParentApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.showError(context, e.displayMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'إضافة ابن',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'اكتب كود المتابعة اللي في صفحة حساب ابنك.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppInput(
            label: 'كود المتابعة',
            controller: _code,
            autofocus: true,
            prefixIcon: Icons.qr_code_rounded,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitting ? null : _submit(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton.primary(
            'إضافة',
            loading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
