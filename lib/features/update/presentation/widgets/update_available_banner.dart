import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/update/presentation/providers/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:itaaleem/core/theme/app_palette.dart';

/// Slim, closeable "تحديث جديد متاح" strip shown above the bottom-nav tabs
/// whenever there's an optional (non-forced) update — see
/// [ForceUpdateScreen] for the mandatory case, gated at the router level
/// instead of shown inline like this.
class UpdateAvailableBanner extends ConsumerWidget {
  const UpdateAvailableBanner({super.key});

  Future<void> _openUpdateUrl(BuildContext context, String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    final launched = uri != null
        ? await launchUrlSafely(uri, mode: LaunchMode.externalApplication)
        : false;
    if (!launched && context.mounted) {
      AppToast.showError(context, 'تعذر فتح رابط التحديث');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateStatusProvider).valueOrNull;
    final dismissed = ref.watch(dismissedUpdateProvider);
    if (status == null || status.forceUpdate || dismissed == status.key) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      bottom: false,
      child: Container(
        margin: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          gradient: context.palette.brandGradient,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Icon(
              Icons.system_update_rounded,
              color: context.palette.onPrimary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'تحديث جديد متاح',
                    style: TextStyle(
                      color: context.palette.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  if (status.message != null && status.message!.isNotEmpty)
                    Text(
                      status.message!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.palette.onPrimary.withValues(
                          alpha: 0.85,
                        ),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _openUpdateUrl(context, status.updateUrl),
              style: TextButton.styleFrom(
                foregroundColor: context.palette.onPrimary,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('تحديث'),
            ),
            IconButton(
              onPressed: () => ref
                  .read(dismissedUpdateProvider.notifier)
                  .dismiss(status.key),
              icon: Icon(
                Icons.close_rounded,
                color: context.palette.onPrimary.withValues(alpha: 0.7),
                size: 18,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}
