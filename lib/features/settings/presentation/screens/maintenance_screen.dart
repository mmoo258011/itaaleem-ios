import 'dart:async';

import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

/// Shown in place of every screen except the login screen while
/// `maintenance.enabled` (`GET /app-config`) or `maintenance_mode`
/// (`GET /public/settings`) is true. Re-checks every 30 seconds and on
/// resume, so it lifts by itself once the server turns maintenance off.
class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => reloadAppSettings(ref),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final title = settings?.maintenanceTitle;
    final message = settings?.maintenanceMessage;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: context.palette.brandGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: context.palette.onPrimary.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.build_circle_rounded,
                      color: context.palette.onPrimary,
                      size: 52,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    (title != null && title.isNotEmpty)
                        ? title
                        : 'التطبيق تحت الصيانة حالياً',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: context.palette.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    (message != null && message.isNotEmpty)
                        ? message
                        : 'نعمل حالياً على تحسين التطبيق، سنعود قريباً',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.palette.onPrimary.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 36),
                  OutlinedButton.icon(
                    onPressed: () => reloadAppSettings(ref),
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: context.palette.onPrimary,
                    ),
                    label: Text(
                      'إعادة المحاولة',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.palette.onPrimary,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: context.palette.onPrimary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () => context.go(loginPath),
                    child: Text(
                      'تسجيل الدخول',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.palette.onPrimary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
