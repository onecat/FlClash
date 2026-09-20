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

const _initializationMarker = 'initialized\n';

abstract interface class DefaultProfileStore {
  Future<bool> get isAvailable;

  Future<List<Profile>> loadProfiles();

  Profile createProfile();

  Future<File> profileFile(Profile profile);

  Future<void> saveProfile(Profile profile);

  Future<void> removeProfile(int id);

  Future<bool> saveConfig(Config config);

  Future<File> markerFile();
}

Future<Config> ensureDefaultDirectProfile(
  Config config, {
  bool? isWindows,
  required DefaultProfileStore store,
}) async {
  if (!(isWindows ?? Platform.isWindows) || !await store.isAvailable) {
    return config;
  }

  final marker = await store.markerFile();
  if (await _hasInitializationMarker(marker)) {
    return config;
  }

  final profiles = await store.loadProfiles();
  if (profiles.isNotEmpty) {
    await _writeInitializationMarker(marker);
    return config;
  }

  final profile = store.createProfile().copyWith(
    autoUpdate: false,
    lastUpdateDate: DateTime.now(),
  );
  final file = await store.profileFile(profile);
  var profileSaveAttempted = false;
  var configSaveAttempted = false;

  try {
    await file.safeWriteAsString(defaultDirectProfileYaml);
    profileSaveAttempted = true;
    await store.saveProfile(profile);

    final nextConfig = config.copyWith(currentProfileId: profile.id);
    configSaveAttempted = true;
    if (!await store.saveConfig(nextConfig)) {
      throw StateError('failed to persist default profile selection');
    }

    await _writeInitializationMarker(marker);
    return nextConfig;
  } catch (error, stackTrace) {
    await marker.safeDelete();

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

    try {
      await file.safeDelete();
    } catch (cleanupError) {
      commonPrint.log(
        'Failed to roll back default profile file: $cleanupError',
        logLevel: LogLevel.warning,
      );
    }

    Error.throwWithStackTrace(error, stackTrace);
  }
}

Future<bool> _hasInitializationMarker(File marker) async {
  try {
    return await marker.readAsString() == _initializationMarker;
  } on FileSystemException {
    return false;
  }
}

Future<void> _writeInitializationMarker(File marker) async {
  await marker.parent.create(recursive: true);
  await marker.writeAsString(_initializationMarker, flush: true);
}
