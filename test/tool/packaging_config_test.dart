import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('Linux packaging teardown', () {
    for (final format in ['deb', 'rpm']) {
      test('$format removes the Helper unit only on a real uninstall', () {
        final config =
            loadYaml(
                  File(
                    'linux/packaging/$format/make_config.yaml',
                  ).readAsStringSync(),
                )
                as YamlMap;
        final scripts = (config['postuninstall_scripts'] as YamlList)
            .cast<String>();

        expect(scripts.first, contains('exit 0'));
        expect(
          scripts,
          contains('rm -f /etc/systemd/system/flclash-helper.service'),
        );
        expect(
          scripts.any((script) => script.contains('systemctl daemon-reload')),
          isTrue,
        );
      });
    }
  });

  test('rpm keeps the Core bytes the Helper was built against', () {
    final config =
        loadYaml(
              File('linux/packaging/rpm/make_config.yaml').readAsStringSync(),
            )
            as YamlMap;
    final macros = (config['spec_macros'] as YamlList).cast<String>();

    expect(macros, contains('%global debug_package %{nil}'));
    expect(macros, contains('%global __os_install_post %{nil}'));
  });

  test('Windows portable marker is decided at install time', () {
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();

    expect(cmake, contains(r'\${CMAKE_INSTALL_CONFIG_NAME}'));
    expect(cmake, contains('portable.flag'));
  });

  test('Windows installer clears a stale portable marker only', () {
    final script = File(
      'windows/packaging/exe/inno_setup.iss',
    ).readAsStringSync();

    expect(script, contains('[InstallDelete]'));
    expect(script, contains(r'Type: files; Name: "{app}\\portable.flag"'));
    expect(
      script,
      isNot(contains(r'Type: filesandordirs; Name: "{app}\\userdata"')),
    );
    expect(script, contains(r'Excludes: "portable.flag,userdata\\*"'));
  });

  group('Windows distribution artifacts', () {
    final workflow = loadYaml(
      File('.github/workflows/build.yaml').readAsStringSync(),
    ) as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    final steps = (jobs['windows-portable-build'] as YamlMap)['steps']
        as YamlList;

    YamlMap stepNamed(String name) => steps
        .cast<YamlMap>()
        .singleWhere((step) => step['name'] == name);

    test('both distributions are built together', () {
      final build = stepNamed('Build Windows distribution packages');
      expect(build['run'], contains('--targets exe,zip'));
    });

    test('the packages are verified before upload', () {
      final verify = stepNamed('Verify Windows distribution packages');
      final script = verify['run'] as String;
      expect(script, contains('Expected exactly one Windows portable ZIP'));
      expect(script, contains('Expected exactly one Windows installer EXE'));
      expect(script, contains('FlClashHelperService.exe'));
      expect(script, contains('portable.flag'));
      expect(script, contains('userdata/'));
    });

    test('portable and setup upload separate files', () {
      final portable = stepNamed('Upload Windows portable artifact');
      final setup = stepNamed('Upload Windows setup artifact');
      final portableConfig = portable['with'] as YamlMap;
      final setupConfig = setup['with'] as YamlMap;

      expect(portable['uses'], 'actions/upload-artifact@v4');
      expect(setup['uses'], 'actions/upload-artifact@v4');
      expect(portableConfig['name'], 'FlClash-windows-amd64-portable');
      expect(
        portableConfig['path'],
        './dist/FlClash-*-windows-amd64.zip',
      );
      expect(setupConfig['name'], 'FlClash-windows-amd64-setup');
      expect(
        setupConfig['path'],
        './dist/FlClash-*-windows-amd64-setup.exe',
      );
      expect(portableConfig['if-no-files-found'], 'error');
      expect(setupConfig['if-no-files-found'], 'error');
    });
  });
}
