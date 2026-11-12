import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/providers/package_info_provider.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/developer_credit.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart';
import 'package:itaaleem/features/app_config/in_app_web_screen.dart';
import 'package:itaaleem/features/home/presentation/screens/account_tab.dart'
    show privacyLink;

/// «معلومات التطبيق», opened by the smart UI's `app_info`: the app's name,
/// version and build, who built it, support, and the same privacy (and,
/// when `app-config` has one, terms) links as «حسابي».
class AppInfoScreen extends ConsumerWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(packageInfoProvider).valueOrNull;
    final config = ref.watch(currentAppConfigProvider);
    final terms = config.link('terms', config.link('terms_url', ''));
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('معلومات التطبيق')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.school_rounded,
                    size: 64,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              info?.appName.isNotEmpty == true ? info!.appName : 'منصة أونلاين',
              textAlign: TextAlign.center,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (info != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'الإصدار ${info.version} (${info.buildNumber})',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.support_agent_rounded),
                    title: const Text('التواصل والدعم'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => context.push<void>(supportPath),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('سياسة الخصوصية'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => openConfigLink(context, privacyLink(ref)),
                  ),
                  if (terms.isNotEmpty) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.gavel_rounded),
                      title: const Text('الشروط والأحكام'),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => openConfigLink(context, terms),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const DeveloperCredit(),
          ],
        ),
      ),
    );
  }
}
