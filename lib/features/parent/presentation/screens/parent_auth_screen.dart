import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_button.dart';
import 'package:itaaleem/core/widgets/app_input.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/parent/presentation/guardian_controller.dart';

/// "دخول ولي الأمر": two tabs — "أول مرة" (`POST /parent/register`, with the
/// student's follow-up code) and "عندي حساب" (`POST /parent/login`). On
/// success the router moves to the guardian home by itself.
class ParentAuthScreen extends StatelessWidget {
  const ParentAuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          title: const Text(
            'دخول ولي الأمر',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          bottom: TabBar(
            labelStyle: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo'),
            labelColor: scheme.primary,
            unselectedLabelColor: scheme.onSurfaceVariant,
            indicatorColor: scheme.primary,
            tabs: const [
              Tab(text: 'أول مرة'),
              Tab(text: 'عندي حساب'),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(children: [_RegisterForm(), _LoginForm()]),
        ),
      ),
    );
  }
}

String? _validateMobile(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'رقم الموبايل مطلوب';
  if (!RegExp(r'^01[0-9]{9}$').hasMatch(v)) {
    return 'رقم الموبايل يجب أن يكون 11 رقماً ويبدأ بـ 01';
  }
  return null;
}

final _mobileFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(11),
];

class _Intro extends StatelessWidget {
  const _Intro(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.family_restroom_rounded, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterForm extends ConsumerStatefulWidget {
  const _RegisterForm();

  @override
  ConsumerState<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends ConsumerState<_RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;

  @override
  void dispose() {
    for (final c in [_name, _mobile, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final error = await ref
        .read(guardianControllerProvider.notifier)
        .register(
          mobile: _mobile.text.trim(),
          parentCode: _code.text.trim(),
          password: _password.text,
          passwordConfirmation: _confirm.text,
          name: _name.text.trim(),
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (error != null) AppToast.showError(context, error.displayMessage);
  }

  @override
  Widget build(BuildContext context) {
    final visibility = IconButton(
      icon: Icon(
        _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        size: 20,
      ),
      onPressed: () => setState(() => _obscure = !_obscure),
    );
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const _Intro(
            'اطلب من ابنك كود المتابعة من صفحة حسابه في التطبيق، '
            'واكتبه هنا مع رقم موبايلك.',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppInput(
            label: 'الاسم (اختياري)',
            controller: _name,
            prefixIcon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          AppInput(
            label: 'رقم الموبايل',
            controller: _mobile,
            prefixIcon: Icons.phone_iphone_rounded,
            keyboardType: TextInputType.phone,
            inputFormatters: _mobileFormatters,
            textInputAction: TextInputAction.next,
            validator: _validateMobile,
          ),
          const SizedBox(height: AppSpacing.md),
          AppInput(
            label: 'كود المتابعة',
            controller: _code,
            prefixIcon: Icons.qr_code_rounded,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v?.trim().isEmpty ?? true) ? 'كود المتابعة مطلوب' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          AppInput(
            label: 'كلمة المرور',
            controller: _password,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscure,
            suffixIcon: visibility,
            textInputAction: TextInputAction.next,
            validator: (v) => (v?.length ?? 0) < 6
                ? 'كلمة المرور يجب أن تكون 6 أحرف على الأقل'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          AppInput(
            label: 'تأكيد كلمة المرور',
            controller: _confirm,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            validator: (v) =>
                v != _password.text ? 'تأكيد كلمة المرور غير متطابق' : null,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(
            'إنشاء الحساب',
            loading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _LoginForm extends ConsumerStatefulWidget {
  const _LoginForm();

  @override
  ConsumerState<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;

  @override
  void dispose() {
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final error = await ref
        .read(guardianControllerProvider.notifier)
        .login(mobile: _mobile.text.trim(), password: _password.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (error != null) AppToast.showError(context, error.displayMessage);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const _Intro('ادخل برقم موبايلك وكلمة المرور اللي اخترتها.'),
          const SizedBox(height: AppSpacing.lg),
          AppInput(
            label: 'رقم الموبايل',
            controller: _mobile,
            prefixIcon: Icons.phone_iphone_rounded,
            keyboardType: TextInputType.phone,
            inputFormatters: _mobileFormatters,
            textInputAction: TextInputAction.next,
            validator: _validateMobile,
          ),
          const SizedBox(height: AppSpacing.md),
          AppInput(
            label: 'كلمة المرور',
            controller: _password,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscure,
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            validator: (v) =>
                (v?.isEmpty ?? true) ? 'كلمة المرور مطلوبة' : null,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(
            'تسجيل الدخول',
            loading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
