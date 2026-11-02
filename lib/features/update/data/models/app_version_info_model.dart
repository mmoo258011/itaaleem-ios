import 'package:itaaleem/features/update/domain/entities/app_version_info.dart';

/// Maps `GET /public/app-version` onto [AppVersionInfo]. Field names are
/// hedged defensively, and any field of the wrong type is read as absent —
/// a malformed body never throws past here into a forced update.
class AppVersionInfoModel extends AppVersionInfo {
  const AppVersionInfoModel({
    required super.latestVersion,
    super.forceUpdate,
    super.updateUrl,
    super.message,
    super.latestBuild,
    super.minBuild,
    super.playStoreUrl,
    super.appStoreUrl,
  });

  factory AppVersionInfoModel.fromJson(Map<String, dynamic> json) {
    String? str(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    int? integer(String key) {
      final v = json[key];
      if (v is int) return v;
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    final force = json['force_update'] ?? json['is_force_update'];
    return AppVersionInfoModel(
      latestVersion:
          str(['latest_version', 'version', 'latest', 'current_version']) ?? '',
      forceUpdate: force == true || force == 1 || force == '1',
      updateUrl: str(['update_url', 'url', 'download_url']),
      message: str(['message', 'update_message', 'description']),
      latestBuild: integer('latest_build'),
      minBuild: integer('min_build'),
      playStoreUrl: str(['play_store_url']),
      appStoreUrl: str(['app_store_url']),
    );
  }
}
