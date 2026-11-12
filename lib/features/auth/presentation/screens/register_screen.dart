import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/localization/generated/app_localizations.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/widgets/app_input.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/core/widgets/auth_shell.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:itaaleem/features/smart_ui/completion/complete_profile_screen.dart'
    show governoratesProvider, profileCompletionApiProvider;
import 'package:itaaleem/features/smart_ui/completion/link_referral.dart';
import 'package:itaaleem/features/smart_ui/completion/profile_completion.dart';
import 'package:itaaleem/features/smart_ui/completion/signup_extras.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Registration is just the student's own details — which center/grade
/// they belong to is chosen afterwards via the center-search/select-grade
/// flow, not during sign-up.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _parentPhoneController = TextEditingController();
  final _referralController = TextEditingController();
  String? _governorate;
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  /// iOS only: sign up with the phone (default) or with the email.
  bool _useEmail = false;

  /// Server-side (422) field errors from the last failed submit — keyed by
  /// the API's own field names (`name`, `mobile`, `email`, `password`).
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void dispose() {
    _fullNameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _parentPhoneController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The invite code from the center's link (Play referrer / the copied
    // `itaaleem:{code}:{ref}` on iOS), read once per install.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      const store = LinkReferralStore();
      await store.readOnce(context);
      final code = await store.pendingRef();
      if (mounted && code != null && _referralController.text.isEmpty) {
        _referralController.text = code;
      }
    });
  }

  SignupExtras get _extras => SignupExtras(
    governorate: _governorate,
    parentPhone: _parentPhoneController.text.trim().isEmpty
        ? null
        : _parentPhoneController.text.trim(),
    referralCode: _referralController.text.trim().isEmpty
        ? null
        : _referralController.text.trim(),
  );

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _submitting = true;
      _fieldErrors = const {};
    });
    final extras = _extras;
    // Kept until the server has them (see flushSignupExtras).
    await saveSignupExtras(extras);
    if (!mounted) return;
    final failure = await ref
        .read(authControllerProvider.notifier)
        .register(
          fullName: _fullNameController.text
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .join(' '),
          // iOS sends only the chosen identifier; Android both, as before.
          mobile: PlatformUtils.flexibleSignUp && _useEmail
              ? ''
              : _mobileController.text.trim(),
          email: PlatformUtils.flexibleSignUp && !_useEmail
              ? ''
              : _emailController.text.trim(),
          password: _passwordController.text,
          passwordConfirmation: _confirmPasswordController.text,
          extras: extras.toRegisterFields(),
        );
    if (failure == null) {
      // Signed in now: hand them to /profile/complete too, in case the
      // register endpoint didn't keep them.
      unawaited(flushSignupExtras(ref.read(profileCompletionApiProvider)));
      unawaited(const LinkReferralStore().clearRef());
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _fieldErrors = failure is ValidationFailure
          ? failure.fieldErrors
          : const {};
    });

    if (failure != null) {
      // Email sign-up while the server still requires a mobile number.
      final mobileRequired =
          PlatformUtils.flexibleSignUp &&
          _useEmail &&
          _fieldErrors.containsKey('mobile');
      AppToast.showError(
        context,
        mobileRequired
            ? 'التسجيل بالبريد الإلكتروني غير متاح حالياً، سجّل برقم التليفون'
            : failure.message.isNotEmpty
            ? failure.message
            : l10n.genericError,
      );
    }
  }

  String? _errorFor(String field) => _fieldErrors[field]?.first;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Form(
      key: _formKey,
      child: AuthShell(
        title: 'إنشاء حساب جديد',
        subtitle: 'ابدأ رحلتك التعليمية معنا 🚀',
        headerFactor: 0.25,
        badgeSize: 64,
        onBack: () => context.go(loginPath),
        fields: [
          AppInput(
            label: 'الاسم (ثنائي على الأقل)',
            controller: _fullNameController,
            prefixIcon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next,
            errorText: _errorFor('name'),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) {
                return l10n.fieldRequired;
              }
              final words = trimmed
                  .split(RegExp(r'\s+'))
                  .where((w) => w.isNotEmpty)
                  .toList();
              if (words.length < 2) {
                return 'يجب إدخال الاسم ثنائي على الأقل';
              }
              return null;
            },
          ),
          // iOS: choose phone or email — only the chosen field is shown
          // (and required). Android: both fields, unchanged.
          if (PlatformUtils.flexibleSignUp) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('رقم التليفون'),
                  icon: Icon(Icons.phone_iphone_rounded),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('البريد الإلكتروني'),
                  icon: Icon(Icons.email_rounded),
                ),
              ],
              selected: {_useEmail},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _useEmail = s.first),
            ),
            if (_useEmail)
              AppInput(
                label: 'البريد الإلكتروني',
                controller: _emailController,
                prefixIcon: Icons.email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                errorText: _errorFor('email'),
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return l10n.fieldRequired;
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)
                      ? null
                      : 'البريد الإلكتروني غير صحيح';
                },
              )
            else
              AppInput(
                label: 'رقم الهاتف',
                controller: _mobileController,
                prefixIcon: Icons.phone_iphone_rounded,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                errorText: _errorFor('mobile'),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return l10n.fieldRequired;
                  }
                  if (!RegExp(r'^01[0-9]{9}$').hasMatch(trimmed)) {
                    return 'رقم الهاتف لازم يكون 11 رقم ويبدأ بـ 01';
                  }
                  return null;
                },
              ),
          ] else ...[
            AppInput(
              label: 'رقم الهاتف',
              controller: _mobileController,
              prefixIcon: Icons.phone_iphone_rounded,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              errorText: _errorFor('mobile'),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) {
                  return l10n.fieldRequired;
                }
                if (!RegExp(r'^01[0-9]{9}$').hasMatch(trimmed)) {
                  return 'رقم الهاتف لازم يكون 11 رقم ويبدأ بـ 01';
                }
                return null;
              },
            ),
            AppInput(
              label: 'الإيميل (اختياري)',
              controller: _emailController,
              prefixIcon: Icons.email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              errorText: _errorFor('email'),
            ),
          ],
          AppInput(
            label: 'كلمة المرور',
            controller: _passwordController,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            errorText: _errorFor('password'),
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
              if (value.length < 6) {
                return l10n.passwordTooShort;
              }
              return null;
            },
          ),
          AppInput(
            label: 'تأكيد كلمة المرور',
            controller: _confirmPasswordController,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.next,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 20,
              ),
              onPressed: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.fieldRequired;
              }
              if (value != _passwordController.text) {
                return l10n.passwordsDontMatch;
              }
              return null;
            },
          ),
          AppInput(
            label: 'رقم ولي الأمر (اختياري)',
            controller: _parentPhoneController,
            prefixIcon: Icons.family_restroom_rounded,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            errorText: _errorFor('parent_phone'),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            validator: (v) =>
                validateParentPhone(v, studentMobile: _mobileController.text),
          ),
          DropdownButtonFormField<String>(
            initialValue: _governorate,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'المحافظة',
              prefixIcon: const Icon(Icons.location_on_outlined),
              errorText: _errorFor('governorate'),
            ),
            items: [
              for (final g
                  in ref.watch(governoratesProvider).valueOrNull ??
                      fallbackGovernorates)
                DropdownMenuItem(value: g.key, child: Text(g.name)),
            ],
            onChanged: (v) => setState(() => _governorate = v),
            validator: (v) => v == null ? 'اختار المحافظة' : null,
          ),
          AppInput(
            label: 'كود الدعوة (اختياري)',
            controller: _referralController,
            prefixIcon: Icons.card_giftcard_rounded,
            textInputAction: TextInputAction.done,
            errorText: _errorFor('referral_code'),
            inputFormatters: [LengthLimitingTextInputFormatter(16)],
            onSubmitted: (_) => _submit(),
          ),
        ],
        action: AuthGradientButton(
          'إنشاء الحساب',
          onPressed: _submitting ? null : _submit,
          loading: _submitting,
        ),
        footer: AuthFooterLink(
          prompt: 'عندك حساب؟',
          action: 'سجّل دخول',
          onTap: () => context.go(loginPath),
        ),
      ),
    );
  }
}
