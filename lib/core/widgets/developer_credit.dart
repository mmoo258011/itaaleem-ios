import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/providers/package_info_provider.dart';

/// The quiet footer under «حسابي» and the login screen: who built the
/// platform, and the app version.
class DeveloperCredit extends ConsumerWidget {
  const DeveloperCredit({super.key});

  static const credit = 'تم تطوير هذه المنصة بواسطة محمود القناص';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(packageInfoProvider).valueOrNull?.version;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(credit, textAlign: TextAlign.center, style: style),
        if (version != null) ...[
          const SizedBox(height: 2),
          Text(
            'منصة أونلاين v$version',
            textAlign: TextAlign.center,
            style: style,
          ),
        ],
      ],
    );
  }
}
