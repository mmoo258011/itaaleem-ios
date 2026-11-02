import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/update/presentation/providers/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

/// Shown in place of every other screen — including login — while
/// `force_update` is true on `GET /public/app-version`. [PopScope] blocks
/// the back button, and there is no other route out: the only action is
/// opening [UpdateStatus.updateUrl] in an external app store/browser.
/// Coming back from the background re-checks the version, so the screen
/// lets go by itself once the server drops the requirement (or the check
/// fails — see [updateStatusProvider]).
class ForceUpdateScreen extends ConsumerStatefulWidget {
  const ForceUpdateScreen({super.key});

  @override
  ConsumerState<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends ConsumerState<ForceUpdateScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(appVersionInfoProvider);
    }
  }

  Future<void> _openUpdateUrl(BuildContext context, String? url) async {
    if (url == null || url.isEmpty) {
      url = PlatformUtils.isIOS ? appStoreFallbackUrl : playStoreFallbackUrl;
    }
    final uri = Uri.tryParse(url);
    final launched = uri != null
        ? await launchUrlSafely(uri, mode: LaunchMode.externalApplication)
        : false;
    if (!launched && context.mounted) {
      AppToast.showError(context, 'تعذر فتح رابط التحديث');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(updateStatusProvider).valueOrNull;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: context.palette.brandGradient),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.all(24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 48,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: context.palette.onPrimary.withValues(
                                alpha: 0.18,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.system_update_rounded,
                              color: context.palette.onPrimary,
                              size: 52,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'يجب تحديث التطبيق',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: context.palette.onPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            (status?.message != null &&
                                    status!.message!.isNotEmpty)
                                ? status.message!
                                : 'يتوفر إصدار جديد من التطبيق، برجاء التحديث للمتابعة',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: context.palette.onPrimary.withValues(
                                    alpha: 0.9,
                                  ),
                                ),
                          ),
                          if (status != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'الإصدار الحالي ${status.currentVersion} • الإصدار الجديد ${status.latestVersion}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: context.palette.onPrimary.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                            ),
                          ],
                          const SizedBox(height: 36),
                          FilledButton.icon(
                            onPressed: () =>
                                _openUpdateUrl(context, status?.updateUrl),
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('تحميل التحديث'),
                            style: FilledButton.styleFrom(
                              backgroundColor: context.palette.surface,
                              foregroundColor: context.palette.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
