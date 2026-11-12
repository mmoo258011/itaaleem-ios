import 'dart:async';

import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_error_state.dart';
import 'package:itaaleem/features/app_config/app_config.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/center_admin/data/center_admin_models.dart';
import 'package:itaaleem/features/center_admin/presentation/center_admin_routes.dart';
import 'package:itaaleem/features/center_admin/presentation/screens/center_students_screen.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_menu_item.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_stat_card.dart';
import 'package:itaaleem/features/center_admin/providers/center_admin_providers.dart';
import 'package:itaaleem/features/web_panel/open_menu_link.dart';

/// Home of the center-admin dashboard: center header, quick actions,
/// pending subscription requests (badge + "طلبات جديدة"), 8 counters, every
/// section grouped like the web panel, and the latest subscriptions and
/// students. The AppBar bell opens the admin's own inbox (unread badge,
/// refreshed on open and every 2 minutes while the dashboard is up).
/// Everything comes from `GET /center-admin/dashboard`, already scoped to
/// this admin's center by the server.
class CenterDashboardScreen extends ConsumerStatefulWidget {
  const CenterDashboardScreen({super.key});

  /// The web panel's groups: (title, [(icon, label, path)]).
  static const _groups = <(String, List<(IconData, String, String)>)>[
    (
      'الرئيسية',
      [
        (Icons.dashboard_rounded, 'لوحة التحكم', centerAdminPanelPath),
        (Icons.insights_rounded, 'الإحصائيات', centerAdminStatsPath),
      ],
    ),
    (
      'المحتوى',
      [
        (Icons.menu_book_rounded, 'المواد', centerAdminSubjectsPath),
        (Icons.school_rounded, 'الدكاترة', centerAdminTeachersPath),
        (Icons.play_circle_rounded, 'المحاضرات', centerAdminLecturesPath),
        (Icons.quiz_rounded, 'الامتحانات', centerAdminExamsPath),
        (Icons.folder_rounded, 'الملفات', centerAdminFilesPath),
        (Icons.view_carousel_rounded, 'البنرات', centerAdminBannersPath),
      ],
    ),
    (
      'الطلاب والاشتراكات',
      [
        (Icons.people_alt_rounded, 'الطلاب', centerAdminStudentsPath),
        (
          Icons.card_membership_rounded,
          'الاشتراكات',
          centerAdminSubscriptionsPath,
        ),
      ],
    ),
    (
      'الأكواد',
      [
        (
          Icons.vpn_key_rounded,
          'أكواد التفعيل',
          centerAdminActivationCodesPath,
        ),
      ],
    ),
    (
      'التواصل',
      [
        (Icons.inbox_rounded, 'صندوق الإشعارات', centerAdminInboxPath),
        (
          Icons.campaign_rounded,
          'إشعارات الطلاب',
          centerAdminNotificationsPath,
        ),
      ],
    ),
    (
      'الإعدادات',
      [(Icons.settings_rounded, 'الإعدادات', centerAdminSettingsPath)],
    ),
  ];

  @override
  ConsumerState<CenterDashboardScreen> createState() =>
      _CenterDashboardScreenState();
}

class _CenterDashboardScreenState extends ConsumerState<CenterDashboardScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // A fresh count on open, then every 2 minutes while the dashboard is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(centerInboxUnreadProvider);
    });
    _poll = Timer.periodic(const Duration(minutes: 2), (_) {
      if (mounted) ref.invalidate(centerInboxUnreadProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _openInbox() async {
    await context.push(centerAdminInboxPath);
    if (mounted) ref.invalidate(centerInboxUnreadProvider);
  }

  /// "إضافة طالب": name, phone, password → `POST students`.
  Future<void> _addStudent() async {
    final values = await showAdminForm(
      context,
      title: 'إضافة طالب',
      submitLabel: 'إضافة',
      fields: const [
        AdminField(
          'name',
          'اسم الطالب',
          icon: Icons.person_rounded,
          required: true,
        ),
        AdminField(
          'phone',
          'رقم الموبايل',
          icon: Icons.phone_rounded,
          keyboard: TextInputType.phone,
          required: true,
        ),
        AdminField(
          'password',
          'كلمة المرور',
          icon: Icons.lock_rounded,
          required: true,
        ),
      ],
    );
    if (values == null || !mounted) return;
    await runAdminAction(context, ref, () async {
      try {
        await ref
            .read(centerAdminRepositoryProvider)
            .create('students', values);
      } on ServerFailure catch (e) {
        // The endpoint isn't on every server yet.
        if (e.statusCode == 404 || e.statusCode == 405) {
          throw const ServerFailure('هذه الميزة غير متاحة حالياً');
        }
        rethrow;
      }
    }, success: 'تم إضافة الطالب');
  }

  Widget _menuItem(IconData icon, String label, String path, {int badge = 0}) {
    final item = AdminMenuItem(
      icon: icon,
      label: label,
      onTap: path == centerAdminInboxPath
          ? _openInbox
          : () => context.push(path),
    );
    if (badge <= 0) return item;
    return Badge(
      label: Text(badge > 99 ? '99+' : '$badge'),
      offset: const Offset(-6, 6),
      child: item,
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(centerDashboardProvider);
    final pendingAsync = ref.watch(centerPendingRequestsProvider);
    final pendingCount = pendingAsync.valueOrNull?.total ?? 0;
    final unread = ref.watch(centerInboxUnreadProvider).valueOrNull ?? 0;
    final config = ref.watch(currentAppConfigProvider);
    final menuLinks = config.menuLinksFor('center_admin');
    // «لوحة التحكم» (the web panel) only once its handoff is live.
    final panelHandoff = config.panelHandoffEnabled;
    final profileCenter = ref.watch(
      authControllerProvider.select((s) => s.valueOrNull?.centerJson),
    );
    final data = async.valueOrNull;
    final centerName =
        data?.centerName ??
        (profileCenter?['name'] is String
            ? profileCenter!['name'] as String
            : null);
    final centerLogo =
        data?.centerLogo ??
        ApiEndpoints.mediaUrl(
          (profileCenter?['logo_url'] ?? profileCenter?['logo'])?.toString(),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم السنتر'),
        actions: [
          IconButton(
            tooltip: 'طلبات الاشتراك',
            onPressed: () => context.push('$centerAdminStudentsPath?tab=2'),
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.mark_email_unread_rounded),
            ),
          ),
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: _openInbox,
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_rounded),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(centerPendingRequestsProvider);
          ref.invalidate(centerDashboardProvider);
          ref.invalidate(centerInboxUnreadProvider);
          // Errors are shown by the page itself; just end the spinner.
          await ref
              .read(centerDashboardProvider.future)
              .then<void>((_) {}, onError: (Object _) {});
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 700;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _CenterHeader(name: centerName, logo: centerLogo),
                const SizedBox(height: AppSpacing.md),
                _QuickActions(
                  unread: unread,
                  onCodes: () => context.push(centerAdminActivationCodesPath),
                  onAddStudent: _addStudent,
                  onInbox: _openInbox,
                  onSettings: () => context.push(centerAdminSettingsPath),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Newest subscription requests first — each opens activation.
                _PendingRequestsSection(async: pendingAsync),
                if (async.hasError && data == null)
                  AppErrorState(
                    message: failureOf(async.error!).message,
                    onRetry: () => ref.invalidate(centerDashboardProvider),
                  )
                else
                  _StatsGrid(stats: data?.stats, columns: wide ? 4 : 2),
                for (final (title, items) in CenterDashboardScreen._groups) ...[
                  AdminSectionTitle(title),
                  GridView.count(
                    crossAxisCount: wide ? 6 : 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.9,
                    children: [
                      for (final (icon, label, path) in items)
                        if (path != centerAdminPanelPath || panelHandoff)
                          _menuItem(
                            icon,
                            label,
                            path,
                            badge: path == centerAdminStudentsPath
                                ? pendingCount
                                : path == centerAdminInboxPath
                                ? unread
                                : 0,
                          ),
                    ],
                  ),
                ],
                // `menu_links.center_admin` from `GET /app-config`.
                if (menuLinks.isNotEmpty) ...[
                  const AdminSectionTitle('روابط'),
                  GridView.count(
                    crossAxisCount: wide ? 6 : 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.9,
                    children: [
                      for (final link in menuLinks)
                        AdminMenuItem(
                          icon: configIcon(link.icon),
                          label: link.title,
                          onTap: () => openMenuLink(context, link),
                        ),
                    ],
                  ),
                ],
                if (data != null) ...[
                  AdminSectionTitle(
                    'آخر الاشتراكات',
                    action: TextButton(
                      onPressed: () =>
                          context.push(centerAdminSubscriptionsPath),
                      child: const Text('عرض الكل'),
                    ),
                  ),
                  _RecentList(
                    items: data.recentSubscriptions,
                    empty: 'لا توجد اشتراكات حديثة',
                    builder: (r) => AdminRecordCard(
                      title: r.nestedName('student') ?? r.title,
                      leading: AdminAvatar(
                        name: r.nestedName('student') ?? r.title,
                        imageUrl: r.nested('student')?.image,
                      ),
                      lines: [
                        r.nestedName('subject') ?? r.nestedName('package'),
                        adminDate(r.date(['created_at', 'starts_at'])),
                      ],
                      trailing: adminStatusBadge(r.status),
                    ),
                  ),
                  AdminSectionTitle(
                    'آخر الطلاب المسجّلين',
                    action: TextButton(
                      onPressed: () => context.push(centerAdminStudentsPath),
                      child: const Text('عرض الكل'),
                    ),
                  ),
                  _RecentList(
                    items: data.recentStudents,
                    empty: 'لا يوجد طلاب جدد',
                    builder: (r) => AdminRecordCard(
                      title: r.title,
                      leading: AdminAvatar(name: r.title, imageUrl: r.image),
                      lines: [
                        r.phone ?? r.email,
                        'سجّل ${adminAgo(r.date(['created_at', 'joined_at']))}',
                      ],
                      onTap: () =>
                          context.push(centerAdminStudentPath(r.id), extra: r),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CenterHeader extends StatelessWidget {
  const _CenterHeader({required this.name, required this.logo});

  final String? name;
  final String? logo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return GlassCard(
      gradient: DesignTokens.brandGradient(scheme),
      radius: DesignTokens.radiusHero,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          AdminAvatar(
            name: name ?? 'س',
            imageUrl: logo,
            radius: 28,
            icon: logo == null ? Icons.apartment_rounded : null,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? 'السنتر',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimary,
                  ),
                ),
                Text(
                  'لوحة تحكم مدير السنتر',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats, required this.columns});

  /// `null` while loading — shimmer cards.
  final AdminRecord? stats;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final cards = <(IconData, String, List<String>, AdminTone, String)>[
      (
        Icons.people_alt_rounded,
        'الطلاب',
        ['students_count', 'students', 'total_students'],
        AdminTone.primary,
        centerAdminStudentsPath,
      ),
      (
        Icons.verified_rounded,
        'الطلاب المشتركين',
        ['subscribed_students_count', 'subscribed_students', 'active_students'],
        AdminTone.secondary,
        centerAdminStudentsPath,
      ),
      (
        Icons.menu_book_rounded,
        'المواد',
        ['subjects_count', 'subjects', 'total_subjects'],
        AdminTone.tertiary,
        centerAdminSubjectsPath,
      ),
      (
        Icons.school_rounded,
        'الدكاترة',
        ['teachers_count', 'teachers', 'total_teachers', 'doctors_count'],
        AdminTone.primary,
        centerAdminTeachersPath,
      ),
      (
        Icons.play_circle_rounded,
        'المحاضرات',
        [
          'lectures_count',
          'lessons_count',
          'lectures',
          'lessons',
          'total_lectures',
        ],
        AdminTone.secondary,
        centerAdminLecturesPath,
      ),
      (
        Icons.quiz_rounded,
        'الامتحانات',
        ['exams_count', 'exams', 'total_exams'],
        AdminTone.tertiary,
        centerAdminExamsPath,
      ),
      (
        Icons.card_membership_rounded,
        'الاشتراكات النشطة',
        ['active_subscriptions_count', 'active_subscriptions'],
        AdminTone.primary,
        centerAdminSubscriptionsPath,
      ),
      (
        Icons.folder_rounded,
        'الملفات',
        ['files_count', 'attachments_count', 'files', 'total_files'],
        AdminTone.secondary,
        centerAdminFilesPath,
      ),
    ];
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 2.1,
      children: [
        for (final (icon, label, keys, tone, path) in cards)
          s == null
              ? const GlassCard(
                  radius: AppRadius.xl,
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: AdminStatCardShimmer(),
                )
              : AdminStatCard(
                  icon: icon,
                  label: label,
                  value: s.number(keys),
                  tone: tone,
                  onTap: () => context.push(path),
                ),
      ],
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.items,
    required this.empty,
    required this.builder,
  });

  final List<AdminRecord> items;
  final String empty;
  final Widget Function(AdminRecord) builder;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          empty,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final r in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: builder(r),
          ),
      ],
    );
  }
}

/// "طلبات جديدة": the pending-request count and the latest three requests.
/// Hidden when there are none (or the call fails).
class _PendingRequestsSection extends StatelessWidget {
  const _PendingRequestsSection({required this.async});

  final AsyncValue<({List<AdminRecord> items, int total})> async;

  @override
  Widget build(BuildContext context) {
    final data = async.valueOrNull;
    if (data == null || data.items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        color: Color.alphaBlend(
          scheme.primaryContainer.withValues(alpha: 0.35),
          scheme.surface,
        ),
        borderColor: scheme.primary.withValues(alpha: 0.3),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.mark_email_unread_rounded, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'طلبات جديدة',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                StatusPill(
                  label: '${data.total} جديد',
                  color: scheme.error,
                  filled: true,
                  dense: true,
                ),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 36)),
                  onPressed: () =>
                      context.push('$centerAdminStudentsPath?tab=2'),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            for (final r in data.items.take(3))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: CenterRequestCard(request: r),
              ),
          ],
        ),
      ),
    );
  }
}

/// "توليد أكواد" / "إضافة طالب" / "الإشعارات" / "الإعدادات".
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.unread,
    required this.onCodes,
    required this.onAddStudent,
    required this.onInbox,
    required this.onSettings,
  });

  final int unread;
  final VoidCallback onCodes;
  final VoidCallback onAddStudent;
  final VoidCallback onInbox;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget action(
      IconData icon,
      String label,
      VoidCallback onTap, {
      int badge = 0,
    }) {
      return Expanded(
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
                horizontal: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  Badge(
                    isLabelVisible: badge > 0,
                    label: Text(badge > 99 ? '99+' : '$badge'),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(icon, color: scheme.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        action(Icons.vpn_key_rounded, 'توليد أكواد', onCodes),
        const SizedBox(width: AppSpacing.sm),
        action(Icons.person_add_alt_1_rounded, 'إضافة طالب', onAddStudent),
        const SizedBox(width: AppSpacing.sm),
        action(
          Icons.notifications_rounded,
          'الإشعارات',
          onInbox,
          badge: unread,
        ),
        const SizedBox(width: AppSpacing.sm),
        action(Icons.settings_rounded, 'الإعدادات', onSettings),
      ],
    );
  }
}
