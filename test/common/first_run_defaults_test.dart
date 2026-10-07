import 'package:fl_clash/common/first_run_defaults.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyWindowsFirstRunDefaults', () {
    test('enables requested Windows settings on a fresh install', () {
      const config = Config(
        themeProps: defaultThemeProps,
        appSettingProps: AppSettingProps(
          autoLaunch: false,
          autoRun: false,
          silentLaunch: true,
        ),
        networkProps: NetworkProps(systemProxy: false),
      );

      final result = applyWindowsFirstRunDefaults(
        config,
        isFreshInstall: true,
        isStoreAvailable: true,
        isWindows: true,
      );

      expect(result.appSettingProps.autoLaunch, isTrue);
      expect(result.appSettingProps.autoRun, isTrue);
      expect(result.networkProps.systemProxy, isTrue);
      expect(result.appSettingProps.silentLaunch, isTrue);
    });

    test('does not overwrite an existing Windows install', () {
      const config = Config(
        themeProps: defaultThemeProps,
        appSettingProps: AppSettingProps(autoLaunch: false, autoRun: false),
        networkProps: NetworkProps(systemProxy: false),
      );

      final result = applyWindowsFirstRunDefaults(
        config,
        isFreshInstall: false,
        isStoreAvailable: true,
        isWindows: true,
      );

      expect(result, config);
    });

    test('does not change settings when the store is unavailable', () {
      const config = Config(
        themeProps: defaultThemeProps,
        appSettingProps: AppSettingProps(autoLaunch: false, autoRun: false),
        networkProps: NetworkProps(systemProxy: false),
      );

      final result = applyWindowsFirstRunDefaults(
        config,
        isFreshInstall: true,
        isStoreAvailable: false,
        isWindows: true,
      );

      expect(result, config);
    });

    test('does not change a fresh install on another platform', () {
      const config = Config(
        themeProps: defaultThemeProps,
        appSettingProps: AppSettingProps(autoLaunch: false, autoRun: false),
        networkProps: NetworkProps(systemProxy: false),
      );

      final result = applyWindowsFirstRunDefaults(
        config,
        isFreshInstall: true,
        isStoreAvailable: true,
        isWindows: false,
      );

      expect(result, config);
    });

    test('preserves unrelated configuration', () {
      const config = Config(
        currentProfileId: 42,
        overrideDns: true,
        themeProps: defaultThemeProps,
        appSettingProps: AppSettingProps(
          locale: 'zh_CN',
          autoLaunch: false,
          autoRun: false,
          minimizeOnExit: false,
        ),
        networkProps: NetworkProps(
          systemProxy: false,
          bypassDomain: ['example.com'],
        ),
      );

      final result = applyWindowsFirstRunDefaults(
        config,
        isFreshInstall: true,
        isStoreAvailable: true,
        isWindows: true,
      );

      expect(result.currentProfileId, 42);
      expect(result.overrideDns, isTrue);
      expect(result.appSettingProps.locale, 'zh_CN');
      expect(result.appSettingProps.minimizeOnExit, isFalse);
      expect(result.networkProps.bypassDomain, ['example.com']);
    });
  });
}
