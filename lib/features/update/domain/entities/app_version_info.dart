/// `GET /public/app-version` — the currently published app version and
/// whether updating to it is mandatory. Answered per platform from the
/// `X-Platform` header.
class AppVersionInfo {
  const AppVersionInfo({
    required this.latestVersion,
    this.forceUpdate = false,
    this.updateUrl,
    this.message,
    this.latestBuild,
    this.minBuild,
    this.playStoreUrl,
    this.appStoreUrl,
  });

  final String latestVersion;
  final bool forceUpdate;
  final String? updateUrl;
  final String? message;

  /// Optional: the published build number — a newer build of the same
  /// [latestVersion] counts as an update too.
  final int? latestBuild;

  /// Optional: builds below this must update, whatever [forceUpdate] says.
  final int? minBuild;

  final String? playStoreUrl;
  final String? appStoreUrl;
}
