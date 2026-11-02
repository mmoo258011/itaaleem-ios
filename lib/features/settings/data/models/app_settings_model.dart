import 'package:itaaleem/features/settings/domain/entities/app_settings.dart';

class AppSettingsModel extends AppSettings {
  const AppSettingsModel({
    super.appName,
    super.whatsappGroup,
    super.whatsappNumber,
    super.facebookUrl,
    super.youtubeUrl,
    super.telegramUrl,
    super.websiteUrl,
    super.supportPhone,
    super.supportEmail,
    super.aboutText,
    super.maintenanceMode,
    super.maintenanceMessage,
    super.aiEnabled,
    super.sequentialMode,
    super.rateAppEnabled,
    super.rateAppUrl,
    super.parentAccessEnabled,
    super.termsEnabled,
    super.liveEnabled,
  });

  factory AppSettingsModel.fromJson(
    Map<String, dynamic> json, {
    Object? rateApp,
  }) {
    final rate = rateApp is Map ? rateApp : json['rate_app'];
    final rateUrl = rate is Map ? _asNonEmpty(rate['url']) : null;
    return AppSettingsModel(
      appName: _asNonEmpty(json['app_name']),
      whatsappGroup: _asNonEmpty(json['whatsapp_group']),
      whatsappNumber: _asNonEmpty(json['whatsapp_number']),
      facebookUrl: _asNonEmpty(json['facebook_url']),
      youtubeUrl: _asNonEmpty(json['youtube_url']),
      telegramUrl: _asNonEmpty(json['telegram_url']),
      websiteUrl: _asNonEmpty(json['website_url']),
      supportPhone: _asNonEmpty(json['support_phone']),
      supportEmail: _asNonEmpty(json['support_email']),
      aboutText: _asNonEmpty(json['about_text']),
      maintenanceMode: json['maintenance_mode'] == true,
      maintenanceMessage: _asNonEmpty(json['maintenance_message']),
      aiEnabled: json['ai_enabled'] == true,
      sequentialMode: json['sequential_mode'] == true,
      rateAppEnabled: rate is Map && rate['enabled'] == true,
      rateAppUrl:
          rateUrl != null &&
              (rateUrl.startsWith('https://') || rateUrl.startsWith('http://'))
          ? rateUrl
          : null,
      parentAccessEnabled: json['parent_access_enabled'] == true,
      termsEnabled: json['terms_enabled'] == true,
      liveEnabled: json['live_enabled'] == true,
    );
  }

  static String? _asNonEmpty(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
