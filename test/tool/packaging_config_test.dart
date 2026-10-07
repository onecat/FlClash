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
}
