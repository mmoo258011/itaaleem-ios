import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/services/fcm_service.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_button.dart';
import 'package:itaaleem/core/widgets/app_empty_state.dart';
import 'package:itaaleem/core/widgets/app_error_state.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/center/data/datasources/centers_remote_data_source.dart';
import 'package:itaaleem/features/grade_change/grade_change_api.dart';
import 'package:itaaleem/features/grade_change/grade_change_refresh.dart';

const gradeChangePath = '/grade-change';

/// Shown before sending — the one thing the student must know.
const gradeChangeWarning =
    'بعد موافقة السنتر، اشتراكات وأكواد الكورس الحالي هتتقفل، وهتحتاج كود جديد أو تفعيل من السنتر للكورس الجديد';

/// After a successful `POST /centers/join`: home, then — if the server kept
/// the old grade and opened a grade-change request — that request's status
/// on top, with the server's notice. `false` for a plain join (the caller
/// shows its own success message).
bool goHomeAfterJoin(BuildContext context, WidgetRef ref, CenterJoinResult r) {
  final router = GoRouter.of(context);
  router.go(homePath);
  if (r.request == null) {
    if (r.notice != null) AppToast.showInfo(context, r.notice!);
    return r.notice != null;
  }
  ref.invalidate(gradeChangeStatusProvider);
  router.push(gradeChangePath);
  AppToast.showInfo(
    context,
    r.notice ?? 'طلب نقلك اتبعت للسنتر وهو قيد المراجعة',
  );
  return true;
}

/// Foreground push types (`content_type` refined); a provider so tests can
/// feed their own.
final gradeChangePushesProvider = Provider<Stream<String>>(
  (ref) => FcmService.foregroundTypes,
);

/// How often an open screen re-asks a pending request's status.
const gradeChangePollInterval = Duration(seconds: 30);

/// «تغيير الكورس»: the current course, pick another, optional reason, a
/// clear warning, confirm → send → follow the request's status.
class GradeChangeScreen extends ConsumerStatefulWidget {
  const GradeChangeScreen({super.key});

  @override
  ConsumerState<GradeChangeScreen> createState() => _GradeChangeScreenState();
}

class _GradeChangeScreenState extends ConsumerState<GradeChangeScreen> {
  int? _selected;
  final _reason = TextEditingController();
  bool _busy = false;

  /// «طلب جديد» pressed on a finished request: show the form instead.
  bool _composing = false;

  /// While a request is pending: every [gradeChangePollInterval], on
  /// resume, and on a `grade_change` push. All stop once it's decided.
  Timer? _poll;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<String>? _pushes;

  @override
  void dispose() {
    _stopWatching();
    _reason.dispose();
    super.dispose();
  }

  void _watchPending(bool pending) {
    if (!pending) return _stopWatching();
    if (_poll != null) return;
    _poll = Timer.periodic(gradeChangePollInterval, (_) => _check());
    _lifecycle = AppLifecycleListener(onResume: _check);
    _pushes = ref
        .read(gradeChangePushesProvider)
        .where((t) => t == 'grade_change')
        .listen((_) => _check());
  }

  void _stopWatching() {
    _poll?.cancel();
    _poll = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _pushes?.cancel();
    _pushes = null;
  }

  /// Quiet: a failed check keeps what's shown; only a changed status
  /// reloads the screen.
  Future<void> _check() async {
    try {
      final r = await ref.read(gradeChangeApiProvider).status();
      if (!mounted || _poll == null) return;
      final shown = ref.read(gradeChangeStatusProvider).valueOrNull;
      if (r?.id != shown?.id || r?.status != shown?.status) _reload();
    } catch (_) {}
  }

  void _reload() {
    ref.invalidate(gradeChangeStatusProvider);
    ref.invalidate(gradeChangeOptionsProvider);
  }

  Future<void> _submit(GradeRef target) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد طلب النقل'),
        content: Text(
          'هتطلب النقل لـ «${target.name}».\n\n$gradeChangeWarning',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(gradeChangeApiProvider)
          .submit(target.id, reason: _reason.text);
      if (!mounted) return;
      AppToast.showSuccess(context, 'تم إرسال الطلب للسنتر');
      setState(() {
        _composing = false;
        _selected = null;
        _reason.clear();
      });
      _reload();
    } catch (e) {
      if (mounted) AppToast.showError(context, _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: const Text('متأكد إنك عايز تلغي طلب النقل؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.palette.error),
            child: const Text('إلغاء الطلب'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(gradeChangeApiProvider).cancel();
      if (mounted) AppToast.showSuccess(context, 'اتلغى الطلب');
      _reload();
    } catch (e) {
      if (mounted) AppToast.showError(context, _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object e) => e is GradeChangeRefused
      ? e.message
      : e is GradeChangeUnavailable
      ? 'تغيير الكورس مش متاح دلوقتي'
      : failureOf(e).message;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(gradeChangeStatusProvider);
    final options = ref.watch(gradeChangeOptionsProvider);

    // A finished move (approved / reverted): bring the whole app over.
    ref.listen(gradeChangeStatusProvider, (_, next) {
      final r = next.valueOrNull;
      if (r != null) syncAfterGradeChange(ref, r);
    });

    final pending =
        (status.valueOrNull ?? options.valueOrNull?.pendingRequest)
            ?.isPending ??
        false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _watchPending(pending);
    });

    Widget body;
    final error = status.error ?? options.error;
    if (error != null) {
      body = error is GradeChangeUnavailable
          ? const AppEmptyState(
              icon: Icons.swap_horiz_rounded,
              title: 'تغيير الكورس مش متاح دلوقتي',
              subtitle: 'تواصل مع المركز لو محتاج تنتقل لكورس تاني',
            )
          : AppErrorState(
              title: 'تعذر تحميل البيانات',
              message: failureOf(error).message,
              retryLabel: 'حاول تاني',
              onRetry: _reload,
            );
    } else if (!status.hasValue || !options.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final request = status.value ?? options.value!.pendingRequest;
      final showStatus = request != null && (request.isPending || !_composing);
      body = RefreshIndicator(
        onRefresh: () async {
          _reload();
          await ref
              .read(gradeChangeStatusProvider.future)
              .catchError((_) => null);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          children: [
            _CurrentCourse(grade: options.value!.currentGrade),
            const SizedBox(height: AppSpacing.lg),
            if (showStatus)
              GradeChangeStatusCard(
                request: request,
                busy: _busy,
                onCancel: _cancel,
                onNewRequest: () => setState(() => _composing = true),
              )
            else
              _form(options.value!),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('تغيير الكورس')),
      body: AppBackground(child: SafeArea(child: body)),
    );
  }

  Widget _form(GradeChangeOptions data) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (data.options.isEmpty) {
      return const AppEmptyState(
        icon: Icons.info_outline_rounded,
        title: 'مفيش كورسات تانية',
        subtitle: 'مفيش كورس تاني متاح للنقل في السنتر ده',
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      );
    }
    final target = data.options.where((g) => g.id == _selected).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'عايز تنتقل لأنهي كورس؟',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: RadioGroup<int>(
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
            child: Column(
              children: [
                for (final grade in data.options)
                  RadioListTile<int>(value: grade.id, title: Text(grade.name)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _reason,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: 'السبب (اختياري)',
            hintText: 'مثلاً: نجحت ونقلت للسنة اللي بعدها',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Notice(
          icon: Icons.warning_amber_rounded,
          text: gradeChangeWarning,
          background: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton.primary(
          'إرسال الطلب',
          loading: _busy,
          onPressed: target == null || _busy ? null : () => _submit(target),
        ),
      ],
    );
  }
}

class _CurrentCourse extends StatelessWidget {
  const _CurrentCourse({required this.grade});

  final GradeRef? grade;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: scheme.primaryContainer,
              child: Icon(
                Icons.school_outlined,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'كورسك الحالي',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    grade?.name ?? '—',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The request's state with the one action that fits it.
class GradeChangeStatusCard extends StatelessWidget {
  const GradeChangeStatusCard({
    super.key,
    required this.request,
    required this.onCancel,
    required this.onNewRequest,
    this.busy = false,
  });

  final GradeChangeRequest request;
  final VoidCallback onCancel;
  final VoidCallback onNewRequest;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final to = request.toGrade?.name;
    final from = request.fromGrade?.name;
    final (icon, color, title, detail) = switch (request.status) {
      GradeChangeStatus.pending => (
        Icons.hourglass_top_rounded,
        scheme.primary,
        'قيد المراجعة',
        to == null ? 'طلبك عند السنتر' : 'طلب النقل لـ «$to» عند السنتر',
      ),
      GradeChangeStatus.approved => (
        Icons.check_circle_rounded,
        Colors.green.shade600,
        to == null ? 'اتنقلت للكورس الجديد' : 'اتنقلت لـ «$to»',
        'موادك وامتحاناتك اتحدّثت للكورس الجديد',
      ),
      GradeChangeStatus.rejected => (
        Icons.cancel_rounded,
        scheme.error,
        'اترفض الطلب',
        request.rejectReason == null ? null : 'السبب: ${request.rejectReason}',
      ),
      GradeChangeStatus.cancelled => (
        Icons.block_rounded,
        scheme.onSurfaceVariant,
        'اتلغى الطلب',
        null,
      ),
      GradeChangeStatus.reverted => (
        Icons.undo_rounded,
        scheme.tertiary,
        'اتلغى النقل',
        from == null ? 'رجعت لكورسك القديم' : 'رجعت لكورسك القديم «$from»',
      ),
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
            if (request.reason != null && request.isPending) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'سببك: ${request.reason}',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            switch (request.status) {
              GradeChangeStatus.pending => AppButton.secondary(
                'إلغاء الطلب',
                loading: busy,
                color: scheme.error,
                onPressed: busy ? null : onCancel,
              ),
              GradeChangeStatus.rejected || GradeChangeStatus.cancelled =>
                AppButton.primary('طلب جديد', onPressed: onNewRequest),
              GradeChangeStatus.approved || GradeChangeStatus.reverted =>
                AppButton.text('طلب نقل تاني', onPressed: onNewRequest),
            },
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Cairo',
                color: foreground,
                fontWeight: FontWeight.w600,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
