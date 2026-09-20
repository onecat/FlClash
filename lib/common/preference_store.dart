import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

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
  final Lock _writeLock = Lock();

  JsonPreferenceStore._(this.file, this._values);

  static Future<JsonPreferenceStore> open(File file) async {
    final backup = File('${file.path}.bak');
    final temp = File('${file.path}.tmp');

    if (await file.exists()) {
      try {
        final values = await _readValues(file);
        await backup.safeDelete();
        await temp.safeDelete();
        return JsonPreferenceStore._(file, values);
      } catch (primaryError, primaryStackTrace) {
        if (await backup.exists()) {
          try {
            final values = await _readValues(backup);
            await _restoreBackup(file, backup);
            await temp.safeDelete();
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
      await temp.safeDelete();
      return JsonPreferenceStore._(file, values);
    }

    await temp.safeDelete();
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
      await backup.safeDelete();
    } catch (_) {
      if (!await file.exists() && movedOriginal && await backup.exists()) {
        await backup.rename(file.path);
      }
      await temp.safeDelete();
      rethrow;
    }
  }

  Future<bool> _flush() {
    return _writeLock.synchronized(() async {
      await _atomicWrite(json.encode(_values));
      return true;
    });
  }

  @override
  int? getInt(String key) => _values[key] is int ? _values[key] as int : null;

  @override
  String? getString(String key) =>
      _values[key] is String ? _values[key] as String : null;

  @override
  Future<bool> setInt(String key, int value) async {
    _values[key] = value;
    return _flush();
  }

  @override
  Future<bool> setString(String key, String value) async {
    _values[key] = value;
    return _flush();
  }

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return _flush();
  }

  @override
  Future<bool> clear() async {
    _values.clear();
    return _flush();
  }
}
