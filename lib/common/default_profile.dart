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
  if (await marker.exists()) {
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

  try {
    await file.safeWriteAsString(defaultDirectProfileYaml);
    profileSaveAttempted = true;
    await store.saveProfile(profile);

    final nextConfig = config.copyWith(currentProfileId: profile.id);
    if (!await store.saveConfig(nextConfig)) {
      throw StateError('failed to persist default profile selection');
    }

    await _writeInitializationMarker(marker);
    return nextConfig;
  } catch (error, stackTrace) {
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

Future<void> _writeInitializationMarker(File marker) async {
  try {
    await marker.safeWriteAsString('initialized\n');
  } catch (error) {
    commonPrint.log(
      'Failed to persist the default profile initialization marker: $error',
      logLevel: LogLevel.warning,
    );
  }
}
