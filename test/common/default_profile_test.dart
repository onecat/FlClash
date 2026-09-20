import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/default_profile.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('does nothing outside Windows', () async {
    final store = _FakeDefaultProfileStore(root);

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: false,
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
      store: store,
    );

    expect(config.currentProfileId, isNull);
    expect(store.loadCount, 0);
    expect(store.createCount, 0);
  });

  test('marks existing profiles initialized', () async {
    final store = _FakeDefaultProfileStore(root)
      ..profiles.add(_profile(99, 'existing'));

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps, currentProfileId: 99),
      isWindows: true,
      store: store,
    );
    final marker = await store.markerFile();

    expect(config.currentProfileId, 99);
    expect(store.createCount, 0);
    expect(await marker.exists(), isTrue);
  });

  test('creates and selects direct profile on first init', () async {
    final store = _FakeDefaultProfileStore(root);

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      store: store,
    );
    final profileFile = await store.profileFile(store.profiles.single);
    final marker = await store.markerFile();

    expect(config.currentProfileId, 7);
    expect(store.savedConfig?.currentProfileId, 7);
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
      store: store,
    );
    store.profiles.clear();
    store.savedConfig = null;

    final config = await ensureDefaultDirectProfile(
      const Config(themeProps: defaultThemeProps),
      isWindows: true,
      store: store,
    );

    expect(config.currentProfileId, isNull);
    expect(store.profiles, isEmpty);
    expect(store.createCount, 1);
    expect(store.savedConfig, isNull);
  });

  test('rolls back only new profile when config saving fails', () async {
    final store = _FakeDefaultProfileStore(
      root,
      saveConfigResult: false,
      injectUnrelatedProfileOnSaveFailure: true,
    );

    await expectLater(
      ensureDefaultDirectProfile(
        const Config(themeProps: defaultThemeProps),
        isWindows: true,
        store: store,
      ),
      throwsA(isA<StateError>()),
    );
    final failedFile = await store.profileFile(
      _profile(7, defaultDirectProfileLabel),
    );
    final marker = await store.markerFile();

    expect(store.removedIds, [7]);
    expect(store.profiles.map((profile) => profile.id), [99]);
    expect(await failedFile.exists(), isFalse);
    expect(await marker.exists(), isFalse);
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
  final bool saveConfigResult;
  final bool injectUnrelatedProfileOnSaveFailure;
  final List<Profile> profiles = [];
  final List<int> removedIds = [];

  int loadCount = 0;
  int createCount = 0;
  Config? savedConfig;

  _FakeDefaultProfileStore(
    this.root, {
    this.available = true,
    this.saveConfigResult = true,
    this.injectUnrelatedProfileOnSaveFailure = false,
  });

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
    return _profile(7, defaultDirectProfileLabel);
  }

  @override
  Future<File> profileFile(Profile profile) async {
    return File(
      '${root.path}${Platform.pathSeparator}profiles'
      '${Platform.pathSeparator}${profile.id}.yaml',
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
    savedConfig = config;
    if (!saveConfigResult && injectUnrelatedProfileOnSaveFailure) {
      profiles.add(_profile(99, 'unrelated'));
    }
    return saveConfigResult;
  }

  @override
  Future<File> markerFile() async {
    return File(
      '${root.path}${Platform.pathSeparator}profile-initialized.flag',
    );
  }
}
