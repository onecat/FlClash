import 'dart:io';

import 'package:fl_clash/models/models.dart';

Config applyWindowsFirstRunDefaults(
  Config config, {
  required bool isFreshInstall,
  required bool isStoreAvailable,
  bool? isWindows,
}) {
  if (!isFreshInstall ||
      !isStoreAvailable ||
      !(isWindows ?? Platform.isWindows)) {
    return config;
  }

  return config.copyWith(
    appSettingProps: config.appSettingProps.copyWith(
      autoLaunch: true,
      autoRun: true,
    ),
    networkProps: config.networkProps.copyWith(systemProxy: true),
  );
}
