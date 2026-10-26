import 'dart:io';

import 'package:fl_clash/common/default_profile.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('default-profile-test');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('default YAML parses as a direct-only profile', () {
    final yaml = loadYaml(defaultDirectProfileYaml) as YamlMap;

    expect(yaml['mode'], 'rule');
    expect(yaml['proxies'], isEmpty);
    expect(yaml['proxy-groups'], isEmpty);
    expect(yaml['rules'], ['MATCH,DIRECT']);
  });

  test('does nothing outside Windows', () async {
    final store = _FakeDefaultProfileStore(root);

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: false,
      isFreshInstall: true,
      store: store,
    );

    expect(config.currentProfileId, isNull);
    expect(store.loadCount, 0);
    expect(store.createCount, 0);
  });

  test('does nothing when preference storage is unavailable', () async {
    final store = _FakeDefaultProfileStore(root, available: false);

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      isFreshInstall: true,
      store: store,
    );

    expect(config.currentProfileId, isNull);
    expect(store.loadCount, 0);
    expect(store.createCount, 0);
  });

  test('does not create for an existing install with no profiles', () async {
    final store = _FakeDefaultProfileStore(root);

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      isFreshInstall: false,
      store: store,
    );
    final marker = await store.markerFile();

    expect(config.currentProfileId, isNull);
    expect(store.createCount, 0);
    expect(store.profiles, isEmpty);
    expect(await marker.exists(), isTrue);
  });

  test('marks existing profiles initialized', () async {
    final store = _FakeDefaultProfileStore(root)
      ..profiles.add(_profile(99, 'existing'));

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps, currentProfileId: 99),
      isWindows: true,
      isFreshInstall: true,
      store: store,
    );
    final marker = await store.markerFile();

    expect(config.currentProfileId, 99);
    expect(store.createCount, 0);
    expect(await marker.exists(), isTrue);
  });

  test('existing install survives marker write failure', () async {
    final store = _FakeDefaultProfileStore(root, failMarkerWrite: true);

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      isFreshInstall: false,
      store: store,
    );

    expect(config.currentProfileId, isNull);
    expect(store.createCount, 0);
  });

  test('creates and selects direct profile on first init', () async {
    final store = _FakeDefaultProfileStore(root);

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      isFreshInstall: true,
      store: store,
    );
    final profileFile = await store.profileFile(store.profiles.single.id);
    final marker = await store.markerFile();

    expect(config.currentProfileId, 7);
    expect(store.savedConfigs.single.currentProfileId, 7);
    expect(store.profiles.map((profile) => profile.id), [7]);
    expect(store.profiles.single.autoUpdate, isFalse);
    expect(store.createCount, 1);
    expect(await profileFile.readAsString(), contains('MATCH,DIRECT'));
    expect(await marker.exists(), isTrue);
  });

  test('does not recreate after all profiles are deleted', () async {
    final store = _FakeDefaultProfileStore(root);
    await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      isFreshInstall: true,
      store: store,
    );
    store.profiles.clear();
    store.savedConfigs.clear();

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      isFreshInstall: true,
      store: store,
    );

    expect(config.currentProfileId, isNull);
    expect(store.profiles, isEmpty);
    expect(store.createCount, 1);
    expect(store.savedConfigs, isEmpty);
  });

  test('rolls back only new profile when config saving fails', () async {
    final store = _FakeDefaultProfileStore(
      root,
      saveConfigResults: [false, true],
      injectUnrelatedProfileOnSaveFailure: true,
    );

    await expectLater(
      ensureDefaultDirectProfile(
        const Config(themeProps: defaultThemeProps),
        isWindows: true,
        isFreshInstall: true,
        store: store,
      ),
      throwsA(isA<StateError>()),
    );
    final failedFile = await store.profileFile(7);
    final marker = await store.markerFile();

    expect(store.removedIds, [7]);
    expect(store.profiles.map((profile) => profile.id), [99]);
    expect(store.savedConfigs.map((config) => config.currentProfileId), [
      7,
      null,
    ]);
    expect(await failedFile.exists(), isFalse);
    expect(await marker.readAsString(), 'pending:7\n');
  });

  test('marker write failure happens before profile mutation', () async {
    final store = _FakeDefaultProfileStore(root, failMarkerWrite: true);

    await expectLater(
      ensureDefaultDirectProfile(
        const Config(themeProps: defaultThemeProps),
        isWindows: true,
        isFreshInstall: true,
        store: store,
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(store.removedIds, isEmpty);
    expect(store.profiles, isEmpty);
    expect(store.savedConfigs, isEmpty);
  });

  test('pending profile recovers an interrupted selection', () async {
    final store = _FakeDefaultProfileStore(root)
      ..profiles.add(_profile(7, defaultDirectProfileLabel));
    final marker = await store.markerFile();
    await marker.writeAsString('pending:7\n');

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      isFreshInstall: false,
      store: store,
    );

    expect(config.currentProfileId, 7);
    expect(store.savedConfigs.single.currentProfileId, 7);
    expect(store.createCount, 0);
    expect(await marker.readAsString(), 'initialized\n');
  });

  test('partial marker retries initialization', () async {
    final store = _FakeDefaultProfileStore(root);
    final marker = await store.markerFile();
    await marker.writeAsString('partial');

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      isFreshInstall: false,
      store: store,
    );

    expect(config.currentProfileId, 7);
    expect(store.createCount, 1);
    expect(await marker.readAsString(), 'initialized\n');
  });

  test('pending orphan file is removed before retrying', () async {
    final store = _FakeDefaultProfileStore(root, nextProfileId: 8);
    final marker = await store.markerFile();
    await marker.writeAsString('pending:7\n');
    final orphan = await store.profileFile(7);
    await orphan.create(recursive: true);
    await orphan.writeAsString('orphan');

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      isFreshInstall: false,
      store: store,
    );

    expect(config.currentProfileId, 8);
    expect(await orphan.exists(), isFalse);
    expect(store.profiles.single.id, 8);
  });

  test('pending marker retries a failed first initialization', () async {
    final store = _FakeDefaultProfileStore(
      root,
      saveConfigResults: [false, true, true],
    );

    await expectLater(
      ensureDefaultDirectProfile(
        const Config(themeProps: defaultThemeProps),
        isWindows: true,
        isFreshInstall: true,
        store: store,
      ),
      throwsA(isA<StateError>()),
    );

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      isFreshInstall: false,
      store: store,
    );

    expect(config.currentProfileId, 8);
    expect(store.createCount, 2);
    final marker = await store.markerFile();
    expect(await marker.readAsString(), 'initialized\n');
  });
}

Profile _profile(int id, String label) {
  return Profile(
    id: id,
    label: label,
    autoUpdateDuration: const Duration(hours: 24),
  );
}

class _FakeDefaultProfileStore implements DefaultProfileStore {
  final Directory root;
  final bool available;
  final List<bool> saveConfigResults;
  final bool injectUnrelatedProfileOnSaveFailure;
  final bool failMarkerWrite;
  final List<Profile> profiles = [];
  final List<int> removedIds = [];
  final List<Config> savedConfigs = [];

  int loadCount = 0;
  int createCount = 0;
  int nextProfileId;

  _FakeDefaultProfileStore(
    this.root, {
    this.available = true,
    List<bool>? saveConfigResults,
    this.injectUnrelatedProfileOnSaveFailure = false,
    this.failMarkerWrite = false,
    this.nextProfileId = 7,
  }) : saveConfigResults = saveConfigResults ?? [true];

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<List<Profile>> loadProfiles() async {
    loadCount++;
    return List<Profile>.from(profiles);
  }

  @override
  Profile createProfile() {
    createCount++;
    return _profile(nextProfileId++, defaultDirectProfileLabel);
  }

  @override
  Future<File> profileFile(int profileId) async {
    return File(
      '${root.path}${Platform.pathSeparator}profiles'
      '${Platform.pathSeparator}$profileId.yaml',
    );
  }

  @override
  Future<void> saveProfile(Profile profile) async {
    profiles.add(profile);
  }

  @override
  Future<void> removeProfile(int id) async {
    removedIds.add(id);
    profiles.removeWhere((profile) => profile.id == id);
  }

  @override
  Future<bool> saveConfig(Config config) async {
    savedConfigs.add(config);
    final index = savedConfigs.length - 1;
    final result = index < saveConfigResults.length
        ? saveConfigResults[index]
        : saveConfigResults.last;
    if (!result && injectUnrelatedProfileOnSaveFailure) {
      profiles.add(_profile(99, 'unrelated'));
    }
    return result;
  }

  @override
  Future<File> markerFile() async {
    if (failMarkerWrite) {
      final blocker = File('${root.path}${Platform.pathSeparator}marker-parent')
        ..writeAsStringSync('blocked');
      return File(
        '${blocker.path}${Platform.pathSeparator}profile-initialized.flag',
      );
    }
    return File(
      '${root.path}${Platform.pathSeparator}profile-initialized.flag',
    );
  }
}
