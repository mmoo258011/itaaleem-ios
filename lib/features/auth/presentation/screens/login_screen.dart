import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart'
    show serverText;
import 'package:itaaleem/core/localization/generated/app_localizations.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/widgets/app_input.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/core/widgets/auth_shell.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/auth/presentation/widgets/device_lock_dialog.dart';
import 'package:itaaleem/features/parent/presentation/screens/parent_home_screen.dart';
import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    final failure = await ref
        .read(authControllerProvider.notifier)
        .login(
          mobile: _mobileController.text.trim(),
          password: _passwordController.text,
        );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (failure is ServerFailure && failure.isDeviceLock) {
      await showDeviceLockDialog(context, ref, message: failure.message);
      return;
    }
    if (failure != null) {
      AppToast.showError(
        context,
        failure.message.isNotEmpty ? failure.message : l10n.genericError,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final parentAccessEnabled =
        ref.watch(appSettingsProvider).valueOrNull?.parentAccessEnabled ??
        false;

    return Form(
      key: _formKey,
      child: AuthShell(
        title: 'منصة أونلاين',
        subtitle: serverText(
          context,
          'welcome',
          'مرحبًا بك في رحلتك التعليمية',
        ),
        headerFactor: 0.35,
        badgeSize: 90,
        fields: [
          // iOS: one field for phone *or* email (detected on submit — an
          // "@" means email). Android keeps the phone-only field.
          if (PlatformUtils.flexibleSignUp)
            AppInput(
              label: 'رقم التليفون أو البريد الإلكتروني',
              controller: _mobileController,
              prefixIcon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return l10n.fieldRequired;
                if (looksLikeEmail(v)) {
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)
                      ? null
                      : 'البريد الإلكتروني غير صحيح';
                }
                return RegExp(r'^[0-9]{8,15}$').hasMatch(v)
                    ? null
                    : 'اكتب رقم تليفون صحيح أو بريد إلكتروني';
              },
            )
          else
            AppInput(
              label: 'رقم الهاتف',
              controller: _mobileController,
              prefixIcon: Icons.phone_iphone_rounded,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.fieldRequired;
                }
                return null;
              },
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppInput(
                label: 'كلمة المرور',
                controller: _passwordController,
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l10n.fieldRequired;
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => context.push(forgotPasswordPath),
                  style: TextButton.styleFrom(
                    foregroundColor: context.palette.primary,
                  ),
                  child: const Text('نسيت كلمة المرور؟'),
                ),
              ),
            ],
          ),
        ],
        action: AuthGradientButton(
          'تسجيل الدخول',
          onPressed: _submitting ? null : _submit,
          loading: _submitting,
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AuthFooterLink(
              prompt: 'مفيش حساب؟',
              action: 'سجل حساب جديد',
              onTap: () => context.go(registerPath),
            ),
            if (parentAccessEnabled)
              TextButton.icon(
                onPressed: () => context.push(parentAuthPath),
                icon: const Icon(Icons.family_restroom_rounded, size: 18),
                label: const Text('دخول ولي أمر'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
