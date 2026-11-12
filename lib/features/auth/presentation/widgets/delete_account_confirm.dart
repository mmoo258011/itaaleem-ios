import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';

/// «حذف الحساب»: confirms, then `DELETE /account`. On success the session
/// is cleared and the router goes to `/login` (like logout). Shared by
/// «حسابي» and the smart UI's `delete_account`. [onBusy] tracks the request.
Future<void> confirmAndDeleteAccount(
  BuildContext context,
  WidgetRef ref, {
  ValueChanged<bool>? onBusy,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('حذف الحساب'),
      content: const Text(
        'هل أنت متأكد من حذف حسابك؟ لا يمكن التراجع عن هذا الإجراء',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: context.palette.error),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  onBusy?.call(true);
  final failure = await ref
      .read(authControllerProvider.notifier)
      .deleteAccount();
  onBusy?.call(false);

  if (failure != null && context.mounted) {
    AppToast.showError(
      context,
      failure.message.isNotEmpty
          ? failure.message
          : 'تعذر حذف الحساب، حاول مرة أخرى',
    );
  }
}
