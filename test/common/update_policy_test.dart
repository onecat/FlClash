import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/models/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom update policy uses the fork and disables automatic checks', () {
    expect(repository, 'onecat/FlClash');
    expect(defaultAppSettingProps.autoCheckUpdate, isFalse);
  });

  test('theme defaults to following the system', () {
    expect(defaultThemeProps.themeMode, ThemeMode.system);
  });
}
