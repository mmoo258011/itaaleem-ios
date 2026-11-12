import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:itaaleem/core/design/smart_brand_theme.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/auth/presentation/widgets/logout_confirm.dart';
import 'package:itaaleem/features/smart_ui/completion/link_referral.dart';
import 'package:itaaleem/features/smart_ui/completion/profile_completion.dart';

final profileCompletionApiProvider = Provider<ProfileCompletionApi>(
  (ref) => ProfileCompletionApi(ref.watch(dioClientProvider)),
);

final governoratesProvider = FutureProvider<List<Governorate>>(
  (ref) => ref.watch(profileCompletionApiProvider).governorates(),
);

/// Shown after joining a smart-UI center while `profile_completion.required`
/// is true: governorate, two-part name, and optionally the parent's phone
/// and an invite code. Like the forced password change, the router keeps
/// the student here until the refreshed profile no longer requires it;
/// «تسجيل الخروج» is the only other way out.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _parentPhone = TextEditingController();
  final _referral = TextEditingController();
  String? _governorate;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    final student = ref.read(authControllerProvider).valueOrNull;
    _name.text = student?.fullName ?? '';
    const LinkReferralStore().pendingRef().then((code) {
      if (mounted && code != null && _referral.text.isEmpty) {
        _referral.text = code;
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _parentPhone.dispose();
    _referral.dispose();
    super.dispose();
  }

  // Only what the server says is missing (`profile_completion.missing`):
  // anything the student already gave (e.g. a name at sign-up) isn't
  // asked again. Without the list, both are asked.
  bool get _askGovernorate => _completion?.needsGovernorate ?? true;
  bool get _askName => _completion?.needsName ?? true;
  ProfileCompletion? get _completion =>
      ref.read(authControllerProvider).valueOrNull?.profileCompletion;

  Future<void> _submit() async {
    setState(() => _fieldErrors = const {});
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = await ref
          .read(profileCompletionApiProvider)
          .complete(
            governorate: _askGovernorate ? _governorate : null,
            name: _askName ? _name.text : null,
            parentPhone: _parentPhone.text,
            referralCode: _referral.text,
          );
      final referral = body['referral']?.toString();
      await const LinkReferralStore().clearRef();
      await ref
          .read(authControllerProvider.notifier)
          .applyProfileCompletion(body);
      if (!mounted) return;
      AppToast.showSuccess(
        context,
        referral == 'ignored'
            ? 'تم حفظ البيانات (كود الدعوة مش هيتحسب للحساب ده)'
            : 'تم حفظ البيانات',
      );
      // The router moves on once the profile no longer requires this.
    } on ProfileCompletionErrors catch (e) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = e.fields;
        _error = e.fields.isEmpty ? e.message : null;
      });
      _formKey.currentState?.validate();
    } catch (e) {
      if (mounted) setState(() => _error = failureOf(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = ref.watch(authControllerProvider).valueOrNull;
    final askGovernorate = _askGovernorate;
    final askName = _askName;
    final governorates =
        ref.watch(governoratesProvider).valueOrNull ?? fallbackGovernorates;

    InputDecoration field(String label, IconData icon, {String? hint}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
        );
    String? server(String key) => _fieldErrors[key];
    final fields = <Widget>[
      if (askGovernorate) ...[
        DropdownButtonFormField<String>(
          initialValue: _governorate,
          isExpanded: true,
          decoration: field('المحافظة', Icons.location_on_rounded),
          items: [
            for (final g in governorates)
              DropdownMenuItem(value: g.key, child: Text(g.name)),
          ],
          onChanged: (v) => setState(() => _governorate = v),
          validator: (v) =>
              server('governorate') ?? (v == null ? 'اختار المحافظة' : null),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (askName) ...[
        TextFormField(
          controller: _name,
          textInputAction: TextInputAction.next,
          decoration: field(
            'الاسم',
            Icons.person_rounded,
            hint: 'الاسم ثنائي على الأقل',
          ),
          validator: (v) => server('name') ?? validateFullName(v),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      TextFormField(
        controller: _parentPhone,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
        ],
        decoration: field('رقم ولي الأمر (اختياري)', Icons.phone_rounded),
        validator: (v) =>
            server('parent_phone') ??
            validateParentPhone(v, studentMobile: student?.mobile ?? ''),
      ),
      const SizedBox(height: AppSpacing.md),
      TextFormField(
        controller: _referral,
        textInputAction: TextInputAction.done,
        inputFormatters: [LengthLimitingTextInputFormatter(16)],
        decoration: field('كود الدعوة (اختياري)', Icons.card_giftcard_rounded),
        validator: (_) => server('referral_code'),
        onFieldSubmitted: (_) => _busy ? null : _submit(),
      ),
      const SizedBox(height: AppSpacing.lg),
    ];

    return PopScope(
      canPop: false,
      child: SmartBrandTheme(
        child: Builder(builder: (context) => _scaffold(context, fields)),
      ),
    );
  }

  Widget _scaffold(BuildContext context, List<Widget> fields) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('كمّل بياناتك'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Center(child: BrandIconTile(icon: Icons.badge_rounded)),
              const SizedBox(height: AppSpacing.base),
              Text(
                'محتاجين شوية بيانات قبل ما تكمل',
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.lg),
              BrandCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...fields,
                    if (_error != null) ...[
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(color: scheme.error),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    GradientButton(
                      label: 'حفظ',
                      loading: _busy,
                      onPressed: _busy ? null : withTapSound(_submit),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: _busy ? null : () => confirmAndLogout(context, ref),
                icon: Icon(Icons.logout_rounded, color: scheme.error),
                label: Text(
                  'تسجيل الخروج',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
