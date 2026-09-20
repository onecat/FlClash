import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'file.dart';

abstract interface class PreferenceStore {
  int? getInt(String key);

  String? getString(String key);

  Future<bool> setInt(String key, int value);

  Future<bool> setString(String key, String value);

  Future<bool> remove(String key);

  Future<bool> clear();
}

class SharedPreferencesStore implements PreferenceStore {
  final SharedPreferences _preferences;

  SharedPreferencesStore(this._preferences);

  @override
  int? getInt(String key) => _preferences.getInt(key);

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<bool> setInt(String key, int value) =>
      _preferences.setInt(key, value);

  @override
  Future<bool> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<bool> remove(String key) => _preferences.remove(key);

  @override
  Future<bool> clear() => _preferences.clear();
}

class JsonPreferenceStore implements PreferenceStore {
  final File file;
  final Map<String, Object?> _values;
  Future<void> _writeQueue = Future<void>.value();

  JsonPreferenceStore._(this.file, this._values);

  static Future<JsonPreferenceStore> open(File file) async {
    final backup = File('${file.path}.bak');
    final temp = File('${file.path}.tmp');

    if (await file.exists()) {
      try {
        final values = await _readValues(file);
        await _bestEffortDelete(backup);
        await _bestEffortDelete(temp);
        return JsonPreferenceStore._(file, values);
      } catch (primaryError, primaryStackTrace) {
        if (await backup.exists()) {
          try {
            final values = await _readValues(backup);
            await _restoreBackup(file, backup);
            await _bestEffortDelete(temp);
            return JsonPreferenceStore._(file, values);
          } catch (_) {
            Error.throwWithStackTrace(primaryError, primaryStackTrace);
          }
        }
        Error.throwWithStackTrace(primaryError, primaryStackTrace);
      }
    }

    if (await backup.exists()) {
      final values = await _readValues(backup);
      await _restoreBackup(file, backup);
      await _bestEffortDelete(temp);
      return JsonPreferenceStore._(file, values);
    }

    await _bestEffortDelete(temp);
    return JsonPreferenceStore._(file, <String, Object?>{});
  }

  static Future<Map<String, Object?>> _readValues(File source) async {
    final raw = await source.readAsString();
    if (raw.trim().isEmpty) {
      return <String, Object?>{};
    }
    final decoded = json.decode(raw);
    if (decoded is! Map) {
      throw const FormatException('portable preferences must be a JSON object');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  static Future<void> _restoreBackup(File file, File backup) async {
    await file.safeDelete();
    await backup.rename(file.path);
  }

  static Future<void> _bestEffortDelete(File file) async {
    try {
      await file.safeDelete();
    } on FileSystemException {
      return;
    }
  }

  Future<void> _atomicWrite(String payload) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');

    await temp.writeAsString(payload, flush: true);
    var movedOriginal = false;
    try {
      if (await file.exists()) {
        await backup.safeDelete();
        await file.rename(backup.path);
        movedOriginal = true;
      }
      await temp.rename(file.path);
    } catch (error, stackTrace) {
      if (!await file.exists() && movedOriginal && await backup.exists()) {
        try {
          await backup.rename(file.path);
        } on FileSystemException {
          // The backup remains in place for recovery on the next launch.
        }
      }
      await _bestEffortDelete(temp);
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _bestEffortDelete(backup);
  }

  Future<bool> _update(void Function() mutate) {
    final operation = _writeQueue.then((_) async {
      final previous = Map<String, Object?>.from(_values);
      mutate();
      try {
        await _atomicWrite(json.encode(_values));
        return true;
      } catch (_) {
        _values
          ..clear()
          ..addAll(previous);
        rethrow;
      }
    });
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object error) {},
    );
    return operation;
  }

  @override
  int? getInt(String key) => _values[key] is int ? _values[key] as int : null;

  @override
  String? getString(String key) =>
      _values[key] is String ? _values[key] as String : null;

  @override
  Future<bool> setInt(String key, int value) {
    return _update(() {
      _values[key] = value;
    });
  }

  @override
  Future<bool> setString(String key, String value) {
    return _update(() {
      _values[key] = value;
    });
  }

  @override
  Future<bool> remove(String key) {
    return _update(() {
      _values.remove(key);
    });
  }

  @override
  Future<bool> clear() {
    return _update(_values.clear);
  }
}
