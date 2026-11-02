/// App-wide settings from `GET /public/settings`: contact/social links,
/// the "about" text, and the maintenance-mode gate.
class AppSettings {
  const AppSettings({
    this.appName,
    this.whatsappGroup,
    this.whatsappNumber,
    this.facebookUrl,
    this.youtubeUrl,
    this.telegramUrl,
    this.websiteUrl,
    this.supportPhone,
    this.supportEmail,
    this.aboutText,
    this.maintenanceMode = false,
    this.maintenanceTitle,
    this.maintenanceMessage,
    this.aiEnabled = false,
    this.sequentialMode = false,
    this.rateAppEnabled = false,
    this.rateAppUrl,
    this.parentAccessEnabled = false,
    this.termsEnabled = false,
    this.liveEnabled = false,
  });

  final String? appName;
  final String? whatsappGroup;
  final String? whatsappNumber;
  final String? facebookUrl;
  final String? youtubeUrl;
  final String? telegramUrl;
  final String? websiteUrl;
  final String? supportPhone;
  final String? supportEmail;
  final String? aboutText;
  final bool maintenanceMode;
  final String? maintenanceTitle;
  final String? maintenanceMessage;

  /// Whether "المساعد الذكي" (`POST /ai/ask`) is turned on server-side.
  final bool aiEnabled;

  /// Whether a lecture stays locked until the previous one in its list is
  /// completed — see `isSequentiallyLocked`. Off (every unlocked lecture
  /// playable in any order) until the backend turns it on.
  final bool sequentialMode;

  /// `rate_app.enabled` — shows "قيّم التطبيق". Off when absent.
  final bool rateAppEnabled;

  /// `rate_app.url` — the store page (only ever `http(s)`).
  final String? rateAppUrl;

  /// `settings.parent_access_enabled` — the global switch for "متابعة ولي
  /// الأمر". Off when absent.
  final bool parentAccessEnabled;

  /// `settings.terms_enabled` — the global switch for grouping subjects by
  /// term (`GET /subjects-by-term`). Off when absent.
  final bool termsEnabled;

  /// `settings.live_enabled` — the global switch for "البث المباشر". Off
  /// when absent.
  final bool liveEnabled;
}
