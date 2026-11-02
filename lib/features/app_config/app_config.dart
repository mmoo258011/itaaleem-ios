import 'package:flutter/material.dart';

/// `GET /app-config` — everything the dashboard can change without a new
/// build. Every field is optional; [AppConfig.empty] (a failed call, a 404
/// from an older server, a malformed body) means "behave exactly like the
/// built-in defaults".
class AppConfig {
  const AppConfig({
    this.cacheTtl = defaultCacheTtl,
    this.maintenance,
    this.features = const {},
    this.texts = const {},
    this.links = const {},
    this.menuItems = const [],
    this.homeCards = const [],
    this.rating = const RatingConfig(),
  });

  static const empty = AppConfig();
  static const defaultCacheTtl = Duration(minutes: 5);

  final Duration cacheTtl;

  /// `null` when the server didn't send `maintenance` — the old
  /// `/public/settings` flag then decides.
  final MaintenanceInfo? maintenance;

  /// Only the keys the server actually sent — a missing key falls back to the
  /// old source (`/public/settings`) or the built-in default.
  final Map<String, bool> features;
  final Map<String, String> texts;
  final Map<String, String> links;
  final List<ConfigItem> menuItems;
  final List<ConfigItem> homeCards;

  /// `rating` isn't sent by the server yet; the defaults apply until it is.
  final RatingConfig rating;

  bool? feature(String key) => features[key];

  String text(String key, String fallback) => texts[key] ?? fallback;

  String link(String key, String fallback) => links[key] ?? fallback;

  /// Accepts the body itself or one wrapped in `data`.
  factory AppConfig.fromJson(Object? raw, {required bool isIOS}) {
    if (raw is! Map) return empty;
    final json = raw['data'] is Map ? raw['data'] as Map : raw;

    final ttl = _asInt(json['cache_ttl']);
    final maintenance = json['maintenance'];

    final features = <String, bool>{};
    final rawFeatures = json['features'];
    if (rawFeatures is Map) {
      rawFeatures.forEach((key, value) {
        final flag = value is Map ? value['enabled'] : value;
        if (flag is bool) features['$key'] = flag;
        if (flag is num) features['$key'] = flag != 0;
      });
    }

    final links = <String, String>{};
    _stringMap(json['links']).forEach((key, value) {
      // `tel:` only where the contract puts phone numbers.
      if (_isHttpsUrl(value) ||
          (key.endsWith('phone') && _isTelUrl(value)) ||
          (key.endsWith('email') && _isEmail(value))) {
        links[key] = value;
      }
    });

    List<ConfigItem> items(Object? list, {bool requireLink = true}) {
      final out = <ConfigItem>[];
      if (list is List) {
        for (final e in list) {
          final item = e is Map
              ? ConfigItem.fromJson(e, requireLink: requireLink)
              : null;
          if (item == null || !item.visibleOn(isIOS: isIOS)) continue;
          if (isIOS && item.hasPurchaseWording) continue;
          out.add(item);
        }
      }
      // Stable: equal `order` keeps the server's order.
      final indexed = out.asMap().entries.toList()
        ..sort((a, b) {
          final byOrder = a.value.order.compareTo(b.value.order);
          return byOrder != 0 ? byOrder : a.key.compareTo(b.key);
        });
      return [for (final e in indexed) e.value];
    }

    return AppConfig(
      cacheTtl: ttl != null && ttl >= 0
          ? Duration(seconds: ttl)
          : defaultCacheTtl,
      maintenance: maintenance is Map
          ? MaintenanceInfo(
              enabled:
                  maintenance['enabled'] == true || maintenance['enabled'] == 1,
              title: _asNonEmpty(maintenance['title']),
              message: _asNonEmpty(maintenance['message']),
            )
          : null,
      features: features,
      texts: _stringMap(json['texts'])
        ..removeWhere((_, value) => isIOS && mentionsPurchase(value)),
      links: links,
      menuItems: items(json['menu_items']),
      homeCards: items(json['home_cards'], requireLink: false),
      rating: RatingConfig.fromJson(json['rating']),
    );
  }
}

class RatingConfig {
  const RatingConfig({this.enabled = true, this.intervalDays = 7});

  final bool enabled;
  final int intervalDays;

  factory RatingConfig.fromJson(Object? raw) {
    if (raw is! Map) return const RatingConfig();
    final days = _asInt(raw['interval_days']);
    return RatingConfig(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      intervalDays: days != null && days > 0 ? days : 7,
    );
  }
}

class MaintenanceInfo {
  const MaintenanceInfo({this.enabled = false, this.title, this.message});

  final bool enabled;
  final String? title;
  final String? message;
}

/// One `menu_items[]` / `home_cards[]` entry.
class ConfigItem {
  const ConfigItem({
    required this.title,
    this.url,
    this.id,
    this.type = 'webview',
    this.subtitle,
    this.icon,
    this.imageUrl,
    this.buttonLabel,
    this.platforms,
    this.order = 0,
  });

  final int? id;
  final String title;

  /// What to open; `null` for a home card with `action: null` (shown, not
  /// tappable).
  final String? url;

  /// `webview`، `external`، `whatsapp` or `phone` — see `openConfigLink`.
  final String type;
  final String? subtitle;
  final String? icon;
  final String? imageUrl;
  final String? buttonLabel;

  /// `null` (absent) = every platform.
  final List<String>? platforms;
  final int order;

  bool get hasPurchaseWording =>
      mentionsPurchase(title) ||
      mentionsPurchase(subtitle ?? '') ||
      mentionsPurchase(buttonLabel ?? '');

  bool visibleOn({required bool isIOS}) =>
      platforms == null || platforms!.contains(isIOS ? 'ios' : 'android');

  /// `null` when there's nothing usable to show. Menu items need a link;
  /// home cards may have `action: null`.
  static ConfigItem? fromJson(Map json, {bool requireLink = true}) {
    if (json['enabled'] == false || json['is_active'] == false) return null;
    final title = _asNonEmpty(json['title']);
    if (title == null) return null;
    final action = json['action'];
    final hasAction = json.containsKey('action');
    final type =
        (_asNonEmpty(action is Map ? action['type'] : json['type']) ??
                'webview')
            .toLowerCase();
    final rawUrl = action is Map
        ? _asNonEmpty(action['url'])
        : (_asNonEmpty(json['url']) ?? _asNonEmpty(json['link']));
    final url =
        rawUrl != null &&
            (_isHttpsUrl(rawUrl) || (type == 'phone' && _isTelUrl(rawUrl)))
        ? rawUrl
        : null;
    if (url == null && (rawUrl != null || requireLink || !hasAction)) {
      return null;
    }
    final platforms = json['platforms'];
    return ConfigItem(
      id: _asInt(json['id']),
      title: title,
      url: url,
      type: type,
      subtitle: _asNonEmpty(json['subtitle']),
      icon: _asNonEmpty(json['icon']),
      imageUrl: _isHttpsUrl(json['image']) ? json['image'] as String : null,
      buttonLabel: _asNonEmpty(json['button']),
      platforms: platforms is List
          ? [for (final p in platforms) '$p'.trim().toLowerCase()]
          : null,
      order: _asInt(json['order']) ?? 0,
    );
  }
}

/// Icon names the dashboard may use. Anything else → [defaultConfigIcon].
const configIcons = <String, IconData>{
  'link': Icons.link_rounded,
  'web': Icons.language_rounded,
  'info': Icons.info_outline_rounded,
  'help': Icons.help_outline_rounded,
  'support': Icons.support_agent_outlined,
  'star': Icons.star_outline_rounded,
  'book': Icons.menu_book_outlined,
  'school': Icons.school_outlined,
  'video': Icons.play_circle_outline_rounded,
  'live': Icons.live_tv_outlined,
  'file': Icons.description_outlined,
  'calendar': Icons.event_outlined,
  'news': Icons.campaign_outlined,
  'gift': Icons.card_giftcard_outlined,
  'trophy': Icons.emoji_events_outlined,
  'chat': Icons.chat_bubble_outline_rounded,
  'phone': Icons.phone_outlined,
  'mail': Icons.mail_outline_rounded,
  'whatsapp': Icons.chat_outlined,
  'facebook': Icons.facebook_rounded,
  'privacy': Icons.privacy_tip_outlined,
  'settings': Icons.settings_outlined,
  'person': Icons.person_outline_rounded,
  'download': Icons.download_outlined,
  'quiz': Icons.quiz_outlined,
  'certificate': Icons.workspace_premium_outlined,
  'email': Icons.mail_outline_rounded,
  'document': Icons.description_outlined,
  'location': Icons.location_on_outlined,
  'bell': Icons.notifications_none_rounded,
  'youtube': Icons.smart_display_outlined,
  'telegram': Icons.send_outlined,
  'instagram': Icons.camera_alt_outlined,
  'tiktok': Icons.music_note_outlined,
};

/// App Store rule: nothing on iOS may mention prices, subscribing or paying.
/// Used to drop such server-sent texts/items on iOS only.
///
/// Arabic words match as whole words only (with the usual و/ف/ب/ل/ال
/// prefixes and a few suffixes), so «الدفعة» / «دفعات» / «مدفوع» /
/// «سعرات» don't trigger it. Diacritics and tatweel are ignored, and
/// أ/إ/آ count as ا.
const _ar = r'[؀-ۿ]';
const _pre = r'(?:و|ف)?(?:ب|ل|ال|بال|لل)?';
final _purchaseWording = RegExp(
  '(?<!$_ar)$_pre(?:'
  // دفع، ادفع، الدفع، يدفع، للدفع، ادفعوا
  r'(?:ا|ي|ت|ن)?دفع(?:وا|ي)?'
  // اشترك، اشتركوا، يشترك، الاشتراك، اشتراكات، اشتراكك
  r'|اشترك(?:وا|ي)?|(?:ي|ت|ن)شترك(?:وا|ي)?'
  r'|اشتراك(?:ات|ك|كم|ها|ه|اتك|اتي)?'
  // سعر، السعر، بسعر، اسعار، سعره
  r'|سعر(?:ه|ها|هم|ك)?|اسعار(?:ه|ها|هم|ك|نا)?'
  // جنيه، جنيهات، شراء، اشتري، يشتري
  r'|جنيه(?:ات|ا)?|شراء|(?:ا|ي|ت|ن)شتري(?:ه|ها|وا)?'
  ')(?!$_ar)'
  r'|ج\s*\.\s*م'
  r'|\$'
  r'|\b(?:EGP|pay(?:s|ing|ment|ments)?|paid|buy(?:s|ing)?|price[sd]?|pricing'
  r'|purchase\w*|subscri\w*)\b',
  caseSensitive: false,
);

String _normalizeArabic(String text) =>
    text.replaceAll(RegExp(r'[ً-ٰٟـ]'), '').replaceAll(RegExp('[أإآ]'), 'ا');

bool mentionsPurchase(String text) =>
    _purchaseWording.hasMatch(_normalizeArabic(text));

const defaultConfigIcon = Icons.link_rounded;

IconData configIcon(String? name) =>
    configIcons[name?.trim().toLowerCase()] ?? defaultConfigIcon;

String? _asNonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}');

bool _isHttpsUrl(Object? value) {
  if (value is! String) return false;
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

bool _isEmail(String value) => RegExp(
  r'^(mailto:)?[^@\s:/]+@[^@\s:/]+\.[a-z]{2,}$',
  caseSensitive: false,
).hasMatch(value);

bool _isTelUrl(Object? value) =>
    value is String && RegExp(r'^tel:\+?[0-9]{6,15}$').hasMatch(value.trim());

Map<String, String> _stringMap(Object? raw) {
  final out = <String, String>{};
  if (raw is Map) {
    raw.forEach((key, value) {
      final v = _asNonEmpty(value);
      if (v != null) out['$key'] = v;
    });
  }
  return out;
}
