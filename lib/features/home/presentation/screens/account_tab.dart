import 'package:itaaleem/features/home/presentation/providers/content_refresh.dart';
import 'package:itaaleem/features/certificates/certificates.dart';
import 'package:itaaleem/features/news/presentation/news_routes.dart';
import 'package:itaaleem/features/news/presentation/news_providers.dart';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/features/app_config/app_config.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart';
import 'package:itaaleem/features/grade_change/grade_change_api.dart';
import 'package:itaaleem/features/grade_change/grade_change_screen.dart'
    show gradeChangePath;
import 'package:itaaleem/features/app_config/in_app_web_screen.dart';
import 'package:itaaleem/features/web_panel/open_menu_link.dart';
import 'package:itaaleem/features/center/data/models/center_json_mapper.dart';
import 'package:itaaleem/features/settings/presentation/rate_app.dart';
import 'package:itaaleem/features/parent/presentation/widgets/parent_code_card.dart';
import 'package:itaaleem/core/widgets/app_button.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/core/widgets/auth_shell.dart';
import 'package:itaaleem/core/widgets/student_avatar.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/features/activation/presentation/screens/activation_screen.dart';
import 'package:itaaleem/features/auth/domain/entities/student.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/auth/presentation/screens/edit_profile_screen.dart';
import 'package:itaaleem/features/auth/presentation/widgets/logout_confirm.dart';
import 'package:itaaleem/features/auth/presentation/widgets/pick_profile_image.dart';
import 'package:itaaleem/features/center/domain/entities/center_model.dart';
import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';
import 'package:itaaleem/features/center/presentation/utils/leave_center_dialog.dart';
import 'package:itaaleem/features/center/presentation/widgets/social_links_bar.dart';
import 'package:itaaleem/features/settings/presentation/providers/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:itaaleem/features/auth/presentation/widgets/delete_account_confirm.dart';
import 'package:itaaleem/core/widgets/developer_credit.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

String? _gradeNameOf(CenterModel center, int? gradeId) {
  if (gradeId == null) return null;
  for (final grade in center.grades) {
    if (grade.id == gradeId) return grade.name;
  }
  return null;
}

/// "حسابي" tab: profile header (with the joined center/grade), quick
/// links, grouped settings sections, and sign-out.
class AccountTab extends ConsumerWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(authControllerProvider).valueOrNull;
    final membership = ref.watch(centerMembershipProvider).valueOrNull;
    final center = membership == null
        ? null
        : ref.watch(centerByIdProvider(membership.centerId));
    final gradeName = (center != null && membership != null)
        ? _gradeNameOf(center, membership.gradeId)
        : null;

    final links = center != null && center.socialLinks.isNotEmpty
        ? center.socialLinks
        : socialLinksFromJson(student?.centerJson?['social_links']);
    final centerName =
        center?.name ?? student?.centerJson?['name']?.toString().trim();
    final centerLogo =
        center?.logo ?? ApiEndpoints.mediaUrl(student?.centerLogo);
    final rateEnabled = ref.watch(rateAppEnabledProvider);
    final config = ref.watch(currentAppConfigProvider);
    final menuItems = config.menuItems;
    final menuLinks = config.menuLinksFor('student');
    final gradeChange = ref.watch(gradeChangeAvailableProvider).valueOrNull;
    final hasCertificates =
        ref.watch(certificatesProvider).valueOrNull?.isNotEmpty ?? false;

    // The header paints under the status bar, so its icons need to be light.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          edgeOffset: MediaQuery.paddingOf(context).top,
          onRefresh: () => refreshAll(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              _Header(
                student: student,
                centerName: (centerName?.isEmpty ?? true) ? null : centerName,
                centerLogo: centerLogo,
                gradeName: gradeName,
              ),
              Center(
                child: ConstrainedBox(
                  // iPad: one readable column in the middle.
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenHorizontal,
                      AppSpacing.sectionSpacing,
                      AppSpacing.screenHorizontal,
                      AppSpacing.sectionSpacing,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ParentCodeCard(),
                        const _SectionLabel('حسابي'),
                        _MenuCard(
                          children: [
                            _MenuTile(
                              icon: Icons.person_outline_rounded,
                              label: 'تعديل البيانات',
                              onTap: () => context.push<void>(editProfilePath),
                            ),
                            _MenuTile(
                              icon: Icons.lock_outline_rounded,
                              label: 'تغيير كلمة السر',
                              onTap: () =>
                                  context.push<void>(changePasswordPath),
                            ),
                            if (!PlatformUtils.hideSubscriptions)
                              _MenuTile(
                                icon: Icons.card_membership_outlined,
                                label: 'اشتراكاتي',
                                onTap: () =>
                                    context.push<void>(mySubscriptionsPath),
                              ),
                            // An activated student can still redeem a code
                            // for more subjects — except on iOS, where
                            // unlocking content outside In-App Purchase isn't
                            // allowed.
                            if (!PlatformUtils.hideSubscriptions)
                              const _MenuTile(
                                icon: Icons.confirmation_number_outlined,
                                label: 'تفعيل كود الاشتراك',
                                onTap: pushActivationScreen,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _SectionLabel('محتوايا'),
                        _MenuCard(
                          children: [
                            if (ref.watch(newsAvailableProvider))
                              _MenuTile(
                                icon: Icons.campaign_outlined,
                                label: serverText(
                                  context,
                                  'news_title',
                                  newsDefaultTitle,
                                ),
                                onTap: () => context.push(newsPath),
                              ),
                            // Hidden until the student has at least one.
                            if (hasCertificates)
                              _MenuTile(
                                icon: Icons.workspace_premium_outlined,
                                label: 'شهاداتي',
                                onTap: () =>
                                    showCertificatesSheet(context, ref),
                              ),
                            _MenuTile(
                              icon: Icons.download_outlined,
                              label: 'التحميلات',
                              // A real GoRouter navigation — `/downloads` is
                              // one of the paths the connectivity gate keeps
                              // reachable offline, recognized by location.
                              onTap: () => context.push(downloadsPath),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _SectionLabel('السنتر'),
                        _MenuCard(
                          children: [
                            if (center != null && membership != null)
                              _MenuTile(
                                icon: Icons.support_agent_outlined,
                                label: 'تواصل مع السنتر',
                                onTap: () =>
                                    context.push<void>(contactCenterPath),
                              ),
                            _MenuTile(
                              icon: Icons.help_outline_rounded,
                              label: 'الدعم',
                              onTap: () => context.push<void>(supportPath),
                            ),
                            if (center != null && membership != null) ...[
                              // With `grade_change` on, moving goes through the
                              // center's approval (the old direct pick would
                              // silently become a request server-side).
                              _MenuTile(
                                icon: Icons.groups_outlined,
                                label: 'تغيير الكورس',
                                onTap: () => context.push<void>(
                                  // Still checking `options` with the flag on:
                                  // never fall back to the direct pick.
                                  (gradeChange ??
                                          configFeature(
                                                ref.read(
                                                  currentAppConfigProvider,
                                                ),
                                                'grade_change',
                                              ) ==
                                              true)
                                      ? gradeChangePath
                                      : '/select-grade/${center.id}',
                                ),
                              ),
                              _MenuTile(
                                icon: Icons.logout_rounded,
                                label: 'مغادرة السنتر',
                                destructive: true,
                                onTap: () => confirmLeaveCenter(
                                  context,
                                  ref,
                                  center.name,
                                ),
                              ),
                            ],
                            if (hasUsableSocialLinks(links))
                              Padding(
                                padding: const EdgeInsets.all(AppSpacing.base),
                                child: SocialLinksBar(socialLinks: links),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _SectionLabel('التطبيق'),
                        _MenuCard(
                          children: [
                            const _DarkModeTile(),
                            if (rateEnabled)
                              _MenuTile(
                                icon: Icons.star_outline_rounded,
                                label: 'قيّم التطبيق ⭐',
                                onTap: () => openRateApp(context),
                              ),
                            _MenuTile(
                              icon: Icons.privacy_tip_outlined,
                              label: 'سياسة الخصوصية',
                              onTap: () =>
                                  openConfigLink(context, privacyLink(ref)),
                            ),
                            _MenuTile(
                              icon: Icons.info_outline_rounded,
                              label: 'عن التطبيق',
                              onTap: () => context.push<void>(aboutPath),
                            ),
                            const _DeleteAccountTile(),
                          ],
                        ),
                        // `menu_items` from `GET /app-config`, under the
                        // built-in ones (already filtered for this platform).
                        if (menuItems.isNotEmpty || menuLinks.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _MenuCard(
                            children: [
                              for (final item in menuItems)
                                _MenuTile(
                                  icon: configIcon(item.icon),
                                  label: item.title,
                                  onTap: () => openConfigLink(
                                    context,
                                    item.url!,
                                    title: item.title,
                                    type: item.type,
                                  ),
                                ),
                              // `menu_links.student` (on our domain only).
                              for (final link in menuLinks)
                                _MenuTile(
                                  icon: configIcon(link.icon),
                                  label: link.title,
                                  onTap: () => openMenuLink(context, link),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        const _LogoutButton(),
                        const SizedBox(height: AppSpacing.md),
                        const Center(child: DeveloperCredit()),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _privacyUrl = 'https://api.itaaleem.com/privacy';

/// `links.privacy` from `GET /app-config`, else the built-in page.
String privacyLink(WidgetRef ref) {
  final config = ref.read(currentAppConfigProvider);
  return config.link('privacy', config.link('privacy_url', _privacyUrl));
}

class _Header extends StatelessWidget {
  const _Header({
    required this.student,
    this.centerName,
    this.centerLogo,
    this.gradeName,
  });

  final Student? student;
  final String? centerName;
  final String? centerLogo;
  final String? gradeName;

  /// Outer radius of the avatar ring — half of it sits in the gradient.
  static const _avatarRadius = 48.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final trimmedName = student?.fullName.trim() ?? '';
    final top = MediaQuery.paddingOf(context).top;
    final headerHeight = math.max(
      MediaQuery.sizeOf(context).height * 0.2,
      top + 96,
    );

    return Column(
      children: [
        Stack(
          children: [
            Column(
              children: [
                GradientWaveHeader(
                  height: headerHeight,
                  child: Padding(
                    padding: EdgeInsets.only(top: top + 14),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Text(
                        'حسابي',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.palette.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: _avatarRadius),
              ],
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: DesignTokens.brandGradient(
                      Theme.of(context).colorScheme,
                    ),
                    boxShadow: DesignTokens.softShadow(
                      Theme.of(context).colorScheme,
                      strength: 1.6,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.surface,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: _ProfileAvatar(student: student),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.md,
            AppSpacing.screenHorizontal,
            0,
          ),
          child: Column(
            children: [
              Text(
                trimmedName.isNotEmpty ? trimmedName : 'طالب',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (student?.isDemo ?? false) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accentSurface,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.science_rounded,
                        size: 12,
                        color: palette.textPrimary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'حساب تجريبي',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (student?.mobile.isNotEmpty ?? false) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  student!.mobile,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: palette.textSecondary,
                  ),
                ),
              ],
              if (centerName != null) ...[
                const SizedBox(height: 10),
                _CenterChip(
                  name: centerName!,
                  logo: centerLogo,
                  gradeName: gradeName,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: DesignTokens.cardBorder(scheme)),
        boxShadow: DesignTokens.softShadow(scheme, strength: 0.6),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                indent: 56,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.base,
        vertical: 2,
      ),
      leading: Icon(
        icon,
        size: 22,
        color: destructive ? scheme.error : scheme.primary,
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: destructive ? scheme.error : scheme.onSurface,
        ),
      ),
      trailing:
          trailing ??
          Icon(Icons.chevron_left_rounded, color: scheme.onSurfaceVariant),
    );
  }
}

class _DarkModeTile extends ConsumerWidget {
  const _DarkModeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final platformIsDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final isDark = themeMode == ThemeMode.system
        ? platformIsDark
        : themeMode == ThemeMode.dark;

    return ListTile(
      contentPadding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.base,
        vertical: 2,
      ),
      leading: Icon(
        Icons.dark_mode_outlined,
        size: 22,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text(
        'الوضع الليلي',
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Switch(
        value: isDark,
        activeTrackColor: context.palette.primary,
        onChanged: (value) =>
            ref.read(themeModeProvider.notifier).setDark(value),
      ),
    );
  }
}

/// Profile header's avatar: tapping it picks a new photo straight from
/// gallery/camera and uploads it via `PUT /profile` immediately — unlike
/// [EditProfileScreen], which stages the pick until "حفظ التغييرات".
class _ProfileAvatar extends ConsumerStatefulWidget {
  const _ProfileAvatar({required this.student});

  final Student? student;

  @override
  ConsumerState<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<_ProfileAvatar> {
  bool _uploading = false;

  Future<void> _changePhoto() async {
    final image = await pickProfileImage(context);
    if (image == null) return;

    setState(() => _uploading = true);
    final failure = await ref
        .read(authControllerProvider.notifier)
        .updateProfile(
          fullName: widget.student?.fullName ?? '',
          avatarFilePath: image.path,
        );
    if (!mounted) return;
    setState(() => _uploading = false);

    if (failure != null) {
      AppToast.showError(
        context,
        failure.message.isNotEmpty
            ? failure.message
            : 'تعذر تحديث الصورة، حاول مرة أخرى',
      );
    } else {
      AppToast.showSuccess(context, 'تم تحديث الصورة بنجاح');
    }
  }

  void _viewFullscreen(BuildContext context) {
    final url = widget.student?.avatarUrl;
    if (url == null || url.isEmpty) return;
    context.push<void>(imageViewerPath, extra: url);
  }

  @override
  Widget build(BuildContext context) {
    return StudentAvatar(
      radius: 44,
      avatarUrl: widget.student?.avatarUrl,
      isLoading: _uploading,
      showCameraBadge: true,
      initial: (widget.student?.fullName.trim().isNotEmpty ?? false)
          ? widget.student!.fullName.trim().characters.first
          : null,
      onTap: _uploading ? null : () => _viewFullscreen(context),
      onCameraTap: _uploading ? null : _changePhoto,
    );
  }
}

/// Destructive "حذف الحساب" menu tile — confirms via dialog, then calls
/// `DELETE /account`. On success the auth controller clears the session,
/// which redirects to `/login` automatically (same mechanism as logout).
class _DeleteAccountTile extends ConsumerStatefulWidget {
  const _DeleteAccountTile();

  @override
  ConsumerState<_DeleteAccountTile> createState() => _DeleteAccountTileState();
}

class _DeleteAccountTileState extends ConsumerState<_DeleteAccountTile> {
  bool _isDeleting = false;

  Future<void> _confirmDelete() => confirmAndDeleteAccount(
    context,
    ref,
    onBusy: (busy) {
      if (mounted) setState(() => _isDeleting = busy);
    },
  );

  @override
  Widget build(BuildContext context) {
    return _MenuTile(
      icon: Icons.delete_forever_rounded,
      label: 'حذف الحساب',
      destructive: true,
      onTap: _isDeleting ? null : _confirmDelete,
      trailing: _isDeleting
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.palette.error,
              ),
            )
          : null,
    );
  }
}

class _LogoutButton extends ConsumerWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggingOut = ref.watch(authControllerProvider).isLoading;

    return AppButton.secondary(
      'تسجيل الخروج',
      icon: Icons.logout_rounded,
      color: context.palette.error,
      loading: isLoggingOut,
      onPressed: isLoggingOut ? null : () => confirmAndLogout(context, ref),
    );
  }
}

/// The joined center's small logo + name (and grade) under the student.
class _CenterChip extends StatelessWidget {
  const _CenterChip({required this.name, this.logo, this.gradeName});

  final String name;
  final String? logo;
  final String? gradeName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logo = this.logo;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: scheme.primary,
            foregroundImage: logo != null && logo.isNotEmpty
                ? CachedNetworkImageProvider(logo)
                : null,
            child: Text(
              name.characters.first,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              gradeName != null ? '$name — $gradeName' : name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
