import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/device/device_identity_service.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/widgets/app_input.dart';
import 'package:itaaleem/core/widgets/auth_shell.dart';
import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

/// "نسيت كلمة المرور": sends `POST /forgot-password` with the student's phone
/// number or email. If the server doesn't support it (404/405/501) the student
/// is sent to contact the center administration instead; any other failure
/// (no connection, unknown account, validation) shows its own message so the
/// button never appears to do nothing.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static const _unsupportedStatuses = {404, 405, 501};

  static const _receivedMessage =
      'تم استلام طلبك. لو الرقم مسجل، هيتواصل معاك السنتر على رقمك قريباً.';

  final _identifier = TextEditingController();
  bool _busy = false;
  String? _success;
  String? _error;
  bool _showContact = false;

  @override
  void dispose() {
    _identifier.dispose();
    super.dispose();
  }

  bool _looksLikeEmail(String value) => value.contains('@');

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final value = _identifier.text.trim();
    if (value.isEmpty) {
      setState(() {
        _error = 'اكتب رقم الهاتف أو البريد الإلكتروني';
        _success = null;
        _showContact = false;
      });
      return;
    }
    final isEmail = _looksLikeEmail(value);
    if (isEmail && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      setState(() {
        _error = 'البريد الإلكتروني غير صحيح';
        _success = null;
        _showContact = false;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _success = null;
      _showContact = false;
    });
    try {
      final device = await ref
          .read(deviceIdentityServiceProvider)
          .getIdentity();
      await ref
          .read(dioClientProvider)
          .post<dynamic>(
            ApiEndpoints.forgotPassword,
            data: {
              if (isEmail) 'email': value else 'mobile': value,
              'device_id': device.deviceId,
              'device_model': device.deviceModel,
            },
          );
      if (!mounted) return;
      setState(() => _success = _receivedMessage);
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      if (_unsupportedStatuses.contains(status)) {
        // The route itself is missing (older server) — contact the center.
        setState(() => _showContact = true);
      } else if (status == 429 || e.response == null) {
        // Rate limit / no network: the request wasn't taken.
        setState(() => _error = failureOf(e).message);
      } else {
        // Any other answer (e.g. an unknown number) reads the same, so the
        // screen never reveals whether a number is registered.
        setState(() => _success = _receivedMessage);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'حدث خطأ ما، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrlSafely(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final whatsapp = settings?.whatsappNumber;
    final phone = settings?.supportPhone;
    final colorScheme = Theme.of(context).colorScheme;

    return AuthShell(
      title: 'استعادة كلمة المرور',
      subtitle: 'هنساعدك ترجع لحسابك',
      headerFactor: 0.2,
      badgeSize: 64,
      onBack: () => Navigator.of(context).maybePop(),
      fields: [
        const Text(
          'اكتب رقم هاتفك أو بريدك الإلكتروني وسنساعدك في استعادة حسابك.',
          style: TextStyle(fontSize: 14),
        ),
        AppInput(
          label: 'رقم الهاتف أو البريد الإلكتروني',
          controller: _identifier,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _busy ? null : _send(),
          prefixIcon: Icons.alternate_email_rounded,
        ),
      ],
      action: AuthGradientButton(
        'إرسال',
        loading: _busy,
        onPressed: _busy ? null : _send,
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_success != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: context.palette.success,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_success!, style: const TextStyle())),
              ],
            ),
          if (_error != null)
            Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            ),
          if (_showContact) ...[
            const Text(
              'للاستعادة تواصل مع إدارة السنتر',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.md),
            if (whatsapp == null && phone == null)
              const Text(
                'لا تتوفر أرقام تواصل حالياً، تواصل مع السنتر مباشرة.',
                style: TextStyle(),
              ),
            if (whatsapp != null)
              OutlinedButton.icon(
                onPressed: () => _open(
                  'https://wa.me/${whatsapp.replaceAll(RegExp('[^0-9]'), '')}',
                ),
                icon: const Icon(Icons.chat_rounded),
                label: Text('واتساب: $whatsapp'),
              ),
            if (phone != null)
              OutlinedButton.icon(
                onPressed: () => _open('tel:$phone'),
                icon: const Icon(Icons.call_rounded),
                label: Text('اتصال: $phone'),
              ),
          ],
        ],
      ),
    );
  }
}
