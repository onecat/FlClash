import 'dart:io';

import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';

import 'default_profile.dart';
import 'path.dart';
import 'preferences.dart';
import 'task.dart';

typedef MigrationTransform =
    Future<MigrationData> Function(Map<String, Object?> configMap);

typedef MigrationFinalize =
    Future<Config> Function(Config config, {required bool isFreshInstall});

Future<Config> _identityFinalize(
  Config config, {
  required bool isFreshInstall,
}) async => config;

abstract interface class MigrationStore {
  /// False when the backing store could not be opened at all, as opposed to a
  /// store that opened but holds nothing.
  Future<bool> get isAvailable;

  Future<Map<String, Object?>?> getConfigMap();

  Future<int> getVersion();

  Future<Map<String, Object?>?> getClashConfigMap();

  Future<void> restore(MigrationData data);

  Future<bool> saveConfig(Config config);

  Future<void> clearClashConfig();

  Future<void> setVersion(int version);
}

class _AppMigrationStore implements MigrationStore {
  const _AppMigrationStore();

  @override
  Future<bool> get isAvailable => preferences.isInit;

  @override
  Future<Map<String, Object?>?> getConfigMap() => preferences.getConfigMap();

  @override
  Future<int> getVersion() => preferences.getVersion();

  @override
  Future<Map<String, Object?>?> getClashConfigMap() =>
      preferences.getClashConfigMap();

  @override
  Future<void> restore(MigrationData data) {
    return database.restore(
      data.profiles,
      data.scripts,
      data.rules,
      data.links,
      data.proxyGroups,
    );
  }

  @override
  Future<bool> saveConfig(Config config) => preferences.saveConfig(config);

  @override
  Future<void> clearClashConfig() => preferences.clearClashConfig();

  @override
  Future<void> setVersion(int version) => preferences.setVersion(version);
}

class _AppDefaultProfileStore implements DefaultProfileStore {
  const _AppDefaultProfileStore();

  @override
  Future<bool> get isAvailable => preferences.isInit;

  @override
  Future<List<Profile>> loadProfiles() => database.profilesDao.query().get();

  @override
  Profile createProfile() => Profile.normal(label: defaultDirectProfileLabel);

  @override
  Future<File> profileFile(int profileId) async {
    return File(await appPath.getProfilePath(profileId.toString()));
  }

  @override
  Future<void> saveProfile(Profile profile) async {
    await database.profiles.put(profile.toCompanion());
  }

  @override
  Future<void> removeProfile(int id) async {
    await database.profilesDao.removeById(id);
  }

  @override
  Future<bool> saveConfig(Config config) => preferences.saveConfig(config);

  @override
  Future<File> markerFile() async {
    return File(await appPath.defaultProfileMarkerPath);
  }
}

Future<Config> _ensureAppDefaultDirectProfile(
  Config config, {
  required bool isFreshInstall,
}) {
  return ensureDefaultDirectProfile(
    config,
    isFreshInstall: isFreshInstall,
    store: const _AppDefaultProfileStore(),
  );
}

class Migration {
  final MigrationStore _store;
  final MigrationTransform _migrateV0;
  final MigrationFinalize _finalize;

  Migration({
    required MigrationStore store,
    MigrationTransform? migrateV0,
    MigrationFinalize? finalize,
  }) : _store = store,
       _migrateV0 = migrateV0 ?? oldToNowTask,
       _finalize = finalize ?? _identityFinalize;

  static const currentVersion = 1;

  Future<Config> run() async {
    final configMap = await _store.getConfigMap();
    var oldVersion = await _store.getVersion();
    final isFreshInstall = configMap == null && oldVersion == 0;
    Config? config;
    if (oldVersion > currentVersion) {
      throw StateError(
        'Local data version $oldVersion is newer than $currentVersion.',
      );
    }
    if (oldVersion == currentVersion) {
      try {
        config = Config.realFromJson(configMap);
      } catch (_) {
        if (!_isV0(configMap)) {
          throw StateError(
            'Local data is damaged. A reset is required to fix this issue.',
          );
        }
        oldVersion = 0;
      }
      if (config != null) {
        final storedDavPassword = _getStoredDavPassword(configMap);
        final hasPlainTextDavPassword =
            storedDavPassword != null &&
            storedDavPassword == config.davProps?.password;
        if (hasPlainTextDavPassword && !await _store.saveConfig(config)) {
          throw StateError('Failed to obfuscate the legacy WebDAV password');
        }
        return _finalize(config, isFreshInstall: isFreshInstall);
      }
    }

    MigrationData data = MigrationData(configMap: configMap);
    var shouldClearClashConfig = false;
    if (oldVersion == 0) {
      final clashConfigMap = await _store.getClashConfigMap();
      if (_isV0(configMap) && configMap != null) {
        final legacyConfigMap = Map<String, Object?>.from(configMap);
        if (clashConfigMap != null) {
          legacyConfigMap['patchClashConfig'] = clashConfigMap;
          shouldClearClashConfig = true;
        }
        data = await _migrateV0(legacyConfigMap);
      } else if (clashConfigMap != null) {
        final currentConfigMap = Map<String, Object?>.from(
          configMap ?? const {},
        );
        currentConfigMap.putIfAbsent('patchClashConfig', () => clashConfigMap);
        data = MigrationData(configMap: currentConfigMap);
        shouldClearClashConfig = true;
      }
    }

    config = Config.realFromJson(data.configMap);
    await _store.restore(data);
    config = await _finalize(config, isFreshInstall: isFreshInstall);
    if (!await _store.saveConfig(config)) {
      // An unopenable store is reported later by the corrupt-cache dialog,
      // which offers a reset; failing here would hide that path.
      if (await _store.isAvailable) {
        throw StateError('Failed to save migrated preferences');
      }
      return config;
    }
    if (shouldClearClashConfig) {
      await _store.clearClashConfig();
    }
    await _store.setVersion(currentVersion);
    return config;
  }
}

bool _isV0(Map<String, Object?>? configMap) =>
    configMap?['proxiesStyle'] != null;

String? _getStoredDavPassword(Map<String, Object?>? configMap) {
  final dav = configMap?['davProps'] ?? configMap?['dav'];
  if (dav is! Map) {
    return null;
  }
  final password = dav['password'];
  return password is String && password.isNotEmpty ? password : null;
}

final migration = Migration(
  store: const _AppMigrationStore(),
  finalize: _ensureAppDefaultDirectProfile,
);
