import 'dart:io';

import 'package:fl_clash/common/preference_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File file;

  setUp(() {
    root = Directory.systemTemp.createTempSync('portable-preferences-test');
    file = File('${root.path}${Platform.pathSeparator}preferences.json');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('round-trips JSON preference values', () async {
    final store = await JsonPreferenceStore.open(file);

    expect(await store.setInt('version', 7), isTrue);
    expect(await store.setString('config', '{"mode":"rule"}'), isTrue);

    final reopened = await JsonPreferenceStore.open(file);
    expect(reopened.getInt('version'), 7);
    expect(reopened.getString('config'), '{"mode":"rule"}');
  });

  test('serializes concurrent writes without losing values', () async {
    final store = await JsonPreferenceStore.open(file);

    await Future.wait([
      store.setInt('first', 1),
      store.setString('second', 'two'),
      store.setInt('third', 3),
    ]);

    final reopened = await JsonPreferenceStore.open(file);
    expect(reopened.getInt('first'), 1);
    expect(reopened.getString('second'), 'two');
    expect(reopened.getInt('third'), 3);
  });

  test('recovers the backup after interruption before replacement', () async {
    final backup = File('${file.path}.bak');
    await backup.writeAsString('{"version":4}', flush: true);

    final store = await JsonPreferenceStore.open(file);

    expect(store.getInt('version'), 4);
    expect(await file.exists(), isTrue);
    expect(await backup.exists(), isFalse);
  });

  test('recovers a valid backup when the primary file is corrupt', () async {
    final backup = File('${file.path}.bak');
    await file.writeAsString('{broken', flush: true);
    await backup.writeAsString('{"version":5}', flush: true);

    final store = await JsonPreferenceStore.open(file);

    expect(store.getInt('version'), 5);
    expect(await file.readAsString(), '{"version":5}');
    expect(await backup.exists(), isFalse);
  });

  test('preserves call order across clear and set operations', () async {
    final store = await JsonPreferenceStore.open(file);
    await store.setInt('old', 1);

    await Future.wait([
      store.clear(),
      store.setInt('new', 2),
    ]);

    final reopened = await JsonPreferenceStore.open(file);
    expect(reopened.getInt('old'), isNull);
    expect(reopened.getInt('new'), 2);
  });

  test('rejects a non-object payload without a usable backup', () async {
    await file.writeAsString('[]', flush: true);

    await expectLater(
      JsonPreferenceStore.open(file),
      throwsA(isA<FormatException>()),
    );
  });
}
