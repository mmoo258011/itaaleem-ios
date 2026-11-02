import 'dart:io';

import 'package:itaaleem/core/storage/secure_storage_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// The device payload sent alongside `register`/`login` per APP_SPEC.md
/// (`device_id`, `device_name`, `device_model`, `operating_system`).
class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.deviceModel,
    required this.operatingSystem,
    this.platform = 'unknown',
    this.osVersion = '',
    this.appVersion = '',
  });

  final String deviceId;
  final String deviceName;
  final String deviceModel;
  final String operatingSystem;

  /// `android` / `ios`.
  final String platform;

  /// Bare OS version (`14`, `17.5`).
  final String osVersion;

  /// `{version}+{build}` of this app.
  final String appVersion;

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'device_name': deviceName,
    'device_model': deviceModel,
    'operating_system': operatingSystem,
    'platform': platform,
    if (osVersion.isNotEmpty) 'os_version': osVersion,
    if (appVersion.isNotEmpty) 'app_version': appVersion,
  };
}

/// `{version}+{build}` from package_info_plus — cached; empty if it fails.
Future<String> appVersionString() => _appVersion ??= () async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty
        ? info.version
        : '${info.version}+${info.buildNumber}';
  } catch (_) {
    return '';
  }
}();
Future<String>? _appVersion;

/// `(version, build)` from package_info_plus — cached; empty strings if it
/// fails.
Future<({String version, String build})> appVersionParts() =>
    _appVersionParts ??= () async {
      try {
        final info = await PackageInfo.fromPlatform();
        return (version: info.version, build: info.buildNumber);
      } catch (_) {
        return (version: '', build: '');
      }
    }();
Future<({String version, String build})>? _appVersionParts;

/// Generates (once) and persists a stable, app-scoped UUID device id — not
/// a raw OS identifier — plus a human-readable device name and platform
/// string, per plan §3/§8.
class DeviceIdentityService {
  DeviceIdentityService(this._secureStorage, {DeviceInfoPlugin? deviceInfo})
    : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final SecureStorageService _secureStorage;
  final DeviceInfoPlugin _deviceInfo;

  DeviceIdentity? _cached;

  Future<DeviceIdentity> getIdentity() async {
    final cached = _cached;
    if (cached != null) return cached;

    final deviceId = await _getOrCreateDeviceId();
    final deviceName = await _resolveDeviceName();
    final deviceModel = await _resolveDeviceModel();
    final operatingSystem = await _resolveOperatingSystem();

    final identity = DeviceIdentity(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceModel: deviceModel,
      operatingSystem: operatingSystem,
      platform: Platform.isAndroid
          ? 'android'
          : (Platform.isIOS ? 'ios' : Platform.operatingSystem),
      osVersion: operatingSystem == 'unknown'
          ? ''
          : operatingSystem.replaceFirst(RegExp(r'^(Android|iOS) '), ''),
      appVersion: await appVersionString(),
    );
    _cached = identity;
    return identity;
  }

  static const _channel = MethodChannel('com.itaaleem.app/device');

  /// Android: the hardware `ANDROID_ID`, which survives uninstall/reinstall
  /// so the server's one-device limit can't be bypassed by reinstalling.
  /// Elsewhere (or if it's unavailable): a persisted UUID (the iOS keychain
  /// already survives a reinstall).
  Future<String> _getOrCreateDeviceId() async {
    if (Platform.isAndroid) {
      try {
        final androidId = await _channel.invokeMethod<String>('androidId');
        if (androidId != null && androidId.isNotEmpty)
          return 'android-$androidId';
      } catch (_) {
        // Fall back to the persisted UUID below.
      }
    }
    final existing = await _secureStorage.readDeviceId();
    if (existing != null && existing.isNotEmpty) return existing;

    final newId = const Uuid().v4();
    await _secureStorage.writeDeviceId(newId);
    return newId;
  }

  Future<String> _resolveDeviceName() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return '${info.manufacturer} ${info.model}'.trim();
      }
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return info.name.trim();
      }
    } catch (_) {
      // Fall through to the generic fallback below.
    }
    return 'Unknown device';
  }

  Future<String> _resolveDeviceModel() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return info.model;
      }
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return info.utsname.machine;
      }
    } catch (_) {
      // Fall through to the generic fallback below.
    }
    return 'unknown';
  }

  Future<String> _resolveOperatingSystem() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return 'Android ${info.version.release}';
      }
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return 'iOS ${info.systemVersion}';
      }
    } catch (_) {
      // Fall through to the generic fallback below.
    }
    return 'unknown';
  }
}

final deviceIdentityServiceProvider = Provider<DeviceIdentityService>((ref) {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return DeviceIdentityService(secureStorage);
});
