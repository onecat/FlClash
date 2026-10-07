import 'dart:io';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

import 'file.dart';
import 'print.dart';

const defaultDirectProfileLabel = '直连';

const defaultDirectProfileYaml = '''
mixed-port: 7890
mode: rule
allow-lan: false
log-level: error

proxies: []
proxy-groups: []

rules:
  - MATCH,DIRECT
''';

const _initializedMarker = 'initialized\n';
const _pendingMarkerPrefix = 'pending:';

abstract interface class DefaultProfileStore {
  Future<bool> get isAvailable;

  Future<List<Profile>> loadProfiles();

  Profile createProfile();

  Future<File> profileFile(int profileId);

  Future<void> saveProfile(Profile profile);

  Future<void> removeProfile(int id);

  Future<bool> saveConfig(Config config);

  Future<File> markerFile();
}

Future<Config> ensureDefaultDirectProfile(
  Config config, {
  bool? isWindows,
  required bool isFreshInstall,
  required DefaultProfileStore store,
}) async {
  if (!(isWindows ?? Platform.isWindows) || !await store.isAvailable) {
    return config;
  }

  final marker = await store.markerFile();
  final markerState = await _readInitializationMarker(marker);
  if (markerState == _initializedMarker) {
    return config;
  }

  final profiles = await store.loadProfiles();
  final pendingProfileId = _pendingProfileId(markerState);
  if (pendingProfileId != null) {
    Profile? pendingProfile;
    for (final profile in profiles) {
      if (profile.id == pendingProfileId) {
        pendingProfile = profile;
        break;
      }
    }
    if (pendingProfile != null) {
      final nextConfig = config.currentProfileId == pendingProfileId
          ? config
          : config.copyWith(currentProfileId: pendingProfileId);
      if (nextConfig != config && !await store.saveConfig(nextConfig)) {
        throw StateError('failed to recover default profile selection');
      }
      await _writeMarker(marker, _initializedMarker);
      return nextConfig;
    }
    await _deleteProfileFileBestEffort(store, pendingProfileId);
  }

  final shouldCreate = isFreshInstall || markerState != null;
  if (profiles.isNotEmpty || !shouldCreate) {
    await _writeInitializationMarkerBestEffort(marker);
    return config;
  }

  final profile = store.createProfile().copyWith(
    autoUpdate: false,
    lastUpdateDate: DateTime.now(),
  );
  await _writeMarker(marker, '$_pendingMarkerPrefix${profile.id}\n');

  File? file;
  var profileSaveAttempted = false;
  var configSaveAttempted = false;

  try {
    file = await store.profileFile(profile.id);
    await file.safeWriteAsString(defaultDirectProfileYaml);
    profileSaveAttempted = true;
    await store.saveProfile(profile);

    final nextConfig = config.copyWith(currentProfileId: profile.id);
    configSaveAttempted = true;
    if (!await store.saveConfig(nextConfig)) {
      throw StateError('failed to persist default profile selection');
    }

    await _writeMarker(marker, _initializedMarker);
    return nextConfig;
  } catch (error, stackTrace) {
    if (configSaveAttempted) {
      try {
        if (!await store.saveConfig(config)) {
          commonPrint.log(
            'Failed to roll back the default profile selection',
            logLevel: LogLevel.warning,
          );
        }
      } catch (cleanupError) {
        commonPrint.log(
          'Failed to roll back the default profile selection: $cleanupError',
          logLevel: LogLevel.warning,
        );
      }
    }

    if (profileSaveAttempted) {
      try {
        await store.removeProfile(profile.id);
      } catch (cleanupError) {
        commonPrint.log(
          'Failed to roll back default profile metadata: $cleanupError',
          logLevel: LogLevel.warning,
        );
      }
    }

    if (file != null) {
      try {
        await file.safeDelete();
      } catch (cleanupError) {
        commonPrint.log(
          'Failed to roll back default profile file: $cleanupError',
          logLevel: LogLevel.warning,
        );
      }
    }

    Error.throwWithStackTrace(error, stackTrace);
  }
}

int? _pendingProfileId(String? markerState) {
  if (markerState == null ||
      !markerState.startsWith(_pendingMarkerPrefix) ||
      !markerState.endsWith('\n')) {
    return null;
  }
  return int.tryParse(
    markerState.substring(_pendingMarkerPrefix.length, markerState.length - 1),
  );
}

Future<String?> _readInitializationMarker(File marker) async {
  try {
    return await marker.readAsString();
  } on FileSystemException {
    return null;
  }
}

Future<void> _writeMarker(File marker, String value) async {
  await marker.parent.create(recursive: true);
  await marker.writeAsString(value, flush: true);
}

Future<void> _writeInitializationMarkerBestEffort(File marker) async {
  try {
    await _writeMarker(marker, _initializedMarker);
  } catch (error) {
    commonPrint.log(
      'Failed to persist the default profile initialization marker: $error',
      logLevel: LogLevel.warning,
    );
  }
}

Future<void> _deleteProfileFileBestEffort(
  DefaultProfileStore store,
  int profileId,
) async {
  try {
    final file = await store.profileFile(profileId);
    await file.safeDelete();
  } catch (error) {
    commonPrint.log(
      'Failed to clean up pending default profile file: $error',
      logLevel: LogLevel.warning,
    );
  }
}
