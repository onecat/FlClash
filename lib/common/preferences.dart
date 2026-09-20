import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/boot_record.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/system_dns.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class _PreferenceStore {
  int? getInt(String key);
  String? getString(String key);
  Future<bool> setInt(String key, int value);
  Future<bool> setString(String key, String value);
  Future<bool> remove(String key);
  Future<bool> clear();
}

class _SharedPreferencesStore implements _PreferenceStore {
  final SharedPreferences _preferences;

  _SharedPreferencesStore(this._preferences);

  @override
  int? getInt(String key) => _preferences.getInt(key);

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<bool> setInt(String key, int value) => _preferences.setInt(key, value);

  @override
  Future<bool> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<bool> remove(String key) => _preferences.remove(key);

  @override
  Future<bool> clear() => _preferences.clear();
}

class _JsonPreferenceStore implements _PreferenceStore {
  final File file;
  final Map<String, Object?> _values;

  _JsonPreferenceStore._(this.file, this._values);

  static Future<_JsonPreferenceStore> open(File file) async {
    if (!await file.exists()) {
      return _JsonPreferenceStore._(file, <String, Object?>{});
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return _JsonPreferenceStore._(file, <String, Object?>{});
    }
    final decoded = json.decode(raw);
    if (decoded is! Map) {
      throw const FormatException('portable preferences must be a JSON object');
    }
    return _JsonPreferenceStore._(
      file,
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<bool> _flush() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(_values), flush: true);
    return true;
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

class Preferences {
  static Preferences? _instance;
  Completer<_PreferenceStore?> _storeCompleter = Completer();

  Future<bool> get isInit async =>
      await _storeCompleter.future != null;

  Preferences._internal() {
    if (appPath.isPortable) {
      appPath.sharedPreferencesPath
          .then((path) => _JsonPreferenceStore.open(File(path)))
          .then((value) => _storeCompleter.complete(value))
          .onError((_, _) => _storeCompleter.complete(null));
      return;
    }
    SharedPreferences.getInstance()
        .then((value) => _SharedPreferencesStore(value))
        .then((value) => _storeCompleter.complete(value))
        .onError((_, _) => _storeCompleter.complete(null));
  }

  factory Preferences() {
    _instance ??= Preferences._internal();
    return _instance!;
  }

  Future<int> getVersion() async {
    final preferences = await _storeCompleter.future;
    return preferences?.getInt('version') ?? 0;
  }

  Future<void> setVersion(int version) async {
    final preferences = await _storeCompleter.future;
    await preferences?.setInt('version', version);
  }

  Future<void> saveShareState(SharedState shareState) async {
    final preferences = await _storeCompleter.future;
    await preferences?.setString('sharedState', json.encode(shareState));
  }

  Future<Map<String, Object?>?> getConfigMap() async {
    try {
      final preferences = await _storeCompleter.future;
      final configString = preferences?.getString(configKey);
      if (configString == null) return null;
      final Map<String, Object?>? configMap = json.decode(configString);
      return configMap;
    } catch (e) {
      commonPrint.log(
        'getConfigMap error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<Map<String, Object?>?> getClashConfigMap() async {
    try {
      final preferences = await _storeCompleter.future;
      final clashConfigString = preferences?.getString(clashConfigKey);
      if (clashConfigString == null) return null;
      return json.decode(clashConfigString);
    } catch (e) {
      commonPrint.log(
        'getClashConfigMap error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> clearClashConfig() async {
    try {
      final preferences = await _storeCompleter.future;
      await preferences?.remove(clashConfigKey);
      return;
    } catch (e) {
      commonPrint.log(
        'clearClashConfig error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return;
    }
  }

  Future<Config?> getConfig() async {
    final configMap = await getConfigMap();
    if (configMap == null) {
      return null;
    }
    return Config.fromJson(configMap);
  }

  Future<bool> saveConfig(Config config) async {
    final preferences = await _storeCompleter.future;
    return preferences?.setString(configKey, json.encode(config)) ?? false;
  }

  Future<SystemDnsRecord?> getSystemDnsRecord() async {
    try {
      final sharedPreferencesIns = await _storeCompleter.future;
      final raw = sharedPreferencesIns?.getString(systemDnsRecordKey);
      if (raw == null) {
        return null;
      }
      return SystemDnsRecord.fromJson(json.decode(raw));
    } catch (e) {
      commonPrint.log(
        'getSystemDnsRecord error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> saveSystemDnsRecord(SystemDnsRecord record) async {
    final sharedPreferencesIns = await _storeCompleter.future;
    await sharedPreferencesIns?.setString(
      systemDnsRecordKey,
      json.encode(record),
    );
  }

  Future<void> clearSystemDnsRecord() async {
    final sharedPreferencesIns = await _storeCompleter.future;
    await sharedPreferencesIns?.remove(systemDnsRecordKey);
  }

  Future<BootRecord?> getBootRecord() async {
    try {
      final sharedPreferencesIns = await _storeCompleter.future;
      final raw = sharedPreferencesIns?.getString(bootRecordKey);
      if (raw == null) {
        return null;
      }
      return BootRecord.fromJson(json.decode(raw));
    } catch (e) {
      commonPrint.log(
        'getBootRecord error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> saveBootRecord(BootRecord record) async {
    final sharedPreferencesIns = await _storeCompleter.future;
    await sharedPreferencesIns?.setString(bootRecordKey, json.encode(record));
  }

  Future<void> clearPreferences() async {
    final sharedPreferencesIns = await _storeCompleter.future;
    await sharedPreferencesIns?.clear();
  }
}

final preferences = Preferences();
