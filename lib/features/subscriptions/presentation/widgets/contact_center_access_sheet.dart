import 'package:flutter/material.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart'
    show serverText;
import 'package:go_router/go_router.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

/// iOS replacement for every "subscribe / request a subscription" sheet
/// (see `PlatformUtils.hideSubscriptions`): no prices, no packages, no
/// subscribe button — just how to get access, plus a shortcut to the
/// center's contact details (WhatsApp / phone on [contactCenterPath]).
const lockedContentMessage = 'للوصول لهذا المحتوى، تواصل مع إدارة المركز';

Future<void> showContactCenterAccessSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      final text = Theme.of(sheetContext).textTheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 32,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              lockedContentMessage,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () {
                Navigator.of(sheetContext).pop();
                // The root navigator's context: the caller may be gone by
                // now, and back must return to the screen underneath as is.
                (rootNavigatorKey.currentContext ?? context).push<void>(
                  contactCenterPath,
                );
              },
              icon: const Icon(Icons.support_agent_rounded),
              label: Text(
                serverText(context, 'contact_center', 'تواصل مع المركز'),
              ),
            ),
          ],
        ),
      );
    },
  );
}
