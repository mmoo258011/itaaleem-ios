import 'dart:async';

import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/widgets/app_card.dart';
import 'package:itaaleem/core/widgets/app_input.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/center/data/datasources/centers_remote_data_source.dart';
import 'package:itaaleem/features/center/data/dummy/center_dummy_data.dart';
import 'package:itaaleem/features/center/domain/entities/center_model.dart';
import 'package:itaaleem/features/center/presentation/screens/center_profile_screen.dart';
import 'package:itaaleem/features/center/presentation/utils/center_color.dart';
import 'package:itaaleem/features/smart_ui/completion/link_referral.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:itaaleem/core/design/smart_brand_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

/// Standalone route wrapper around [CenterSearchBody] (own [Scaffold] +
/// app bar) — kept for any direct/deep-link navigation to the search flow.
/// [HomeScreen] embeds [CenterSearchBody] directly instead, as its "لم
/// ينضم بعد" state, so students aren't confined to this screen to join.
class CenterSearchScreen extends StatelessWidget {
  const CenterSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ابحث عن سنترك')),
      body: const AppBackground(child: SafeArea(child: CenterSearchBody())),
    );
  }
}

/// Code-only center search + join entry point: the student enters the
/// center's own code (handed to them by their teacher/center) rather than
/// browsing or searching a list — `GET /centers?code=`. Tapping "انضم لهذا
/// السنتر" on a found center pushes [CenterProfileScreen], which in turn
/// pushes [SelectGradeScreen] to actually confirm the join.
class CenterSearchBody extends ConsumerStatefulWidget {
  const CenterSearchBody({super.key});

  @override
  ConsumerState<CenterSearchBody> createState() => _CenterSearchBodyState();
}

class _CenterSearchBodyState extends ConsumerState<CenterSearchBody> {
  final _codeController = TextEditingController();

  /// Around the result/not-found/error card, scrolled into view after a
  /// search so the keyboard never hides it.
  final _resultKey = GlobalKey();
  bool _searching = false;
  CenterModel? _foundCenter;
  bool _notFound = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // A center's link (Play referrer / copied code on iOS): fill the code in
    // and look it up, once.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (ref.read(authControllerProvider).valueOrNull?.isDemo ?? false) {
        return;
      }
      final code = await const LinkReferralStore().takeCenterCode(context);
      if (!mounted || code == null || _codeController.text.isNotEmpty) return;
      _codeController.text = code.toUpperCase();
      unawaited(_searchByCode());
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _searchByCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _searching = true;
      _foundCenter = null;
      _notFound = false;
      _errorMessage = null;
    });

    // Demo ("دخول تجريبي"): any code returns the same local demo center —
    // there's no real backend to look one up against.
    final isDemo =
        ref.read(authControllerProvider).valueOrNull?.isDemo ?? false;
    if (isDemo) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() {
        _searching = false;
        _foundCenter = centerDummyData.first;
      });
      _revealResult();
      return;
    }

    try {
      final center = await ref
          .read(centersRemoteDataSourceProvider)
          .getCenterByCode(code)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _searching = false;
        _foundCenter = center;
        _notFound = center == null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final failure = failureOf(e);
      setState(() {
        _searching = false;
        _errorMessage = failure is NetworkFailure
            ? 'تأكد من اتصالك بالإنترنت'
            : failure.message;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _errorMessage = 'استغرق البحث وقتاً طويلاً، حاول مرة أخرى';
      });
    }
    _revealResult();
  }

  /// Once the keyboard has closed and the card is laid out, scrolls it in.
  void _revealResult() {
    if (!mounted) return;
    // The keyboard takes a moment to animate out and resize the viewport.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      final target = _resultKey.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) => SmartBrandTheme(
    child: Builder(
      builder: (context) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: _buildBranded(context),
      ),
    ),
  );

  Widget _buildBranded(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(
        AppSpacing.xl,
      ).add(EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom)),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xl),
          const Reveal(child: BrandIconTile(icon: Icons.vpn_key_rounded)),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'انضم لسنترك',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'ادخل الكود اللي المدرس أو السنتر اداهولك',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Reveal(
            index: 2,
            child: BrandCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  AppInput(
                    controller: _codeController,
                    label: 'كود السنتر',
                    hint: 'مثال: AX-204',
                    prefixIcon: Icons.vpn_key_rounded,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchByCode(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  GradientButton(
                    label: 'بحث عن السنتر',
                    loading: _searching,
                    onPressed: _searching ? null : withTapSound(_searchByCode),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          KeyedSubtree(
            key: _resultKey,
            child: _foundCenter != null
                ? Reveal(
                    key: ValueKey(_foundCenter!.id),
                    child: _CenterResultCard(center: _foundCenter!),
                  )
                : _notFound
                ? const _CenterNotFoundCard()
                : _errorMessage != null
                ? _CenterErrorCard(message: _errorMessage!)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _CenterResultCard extends StatelessWidget {
  const _CenterResultCard({required this.center});

  final CenterModel center;

  @override
  Widget build(BuildContext context) {
    final color = parseCenterColor(center.primaryColor);

    return AppCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Hero(
                tag: 'center-logo-${center.id}',
                child: Container(
                  width: 60,
                  height: 60,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: DesignTokens.brandGradient(
                      Theme.of(context).colorScheme,
                    ),
                  ),
                  child: CircleAvatar(
                    backgroundColor: color,
                    foregroundImage:
                        (center.logo == null || center.logo!.isEmpty)
                        ? null
                        : CachedNetworkImageProvider(center.logo!),
                    onForegroundImageError:
                        (center.logo == null || center.logo!.isEmpty)
                        ? null
                        : (_, _) {},
                    child: Text(
                      center.initial,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: context.palette.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      center.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    StatusPill(label: center.code, dense: true),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: context.palette.warning,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          center.rating.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.palette.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.people_alt_rounded,
                          size: 14,
                          color: context.palette.textTertiary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${center.studentsCount} طالب',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.palette.textTertiary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          JoinCenterButton(center: center),
        ],
      ),
    );
  }
}

class _CenterNotFoundCard extends StatelessWidget {
  const _CenterNotFoundCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 32,
            color: context.palette.error,
          ),
          const SizedBox(height: 10),
          Text(
            'مفيش سنتر بالكود ده',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: context.palette.error,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'تأكد من الكود وجرب تاني',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterErrorCard extends StatelessWidget {
  const _CenterErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        children: [
          Icon(Icons.wifi_off_rounded, size: 32, color: context.palette.error),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.palette.error,
            ),
          ),
        ],
      ),
    );
  }
}
