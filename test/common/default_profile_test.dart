import 'package:fl_clash/common/default_profile.dart';
import 'package:test/test.dart';

void main() {
  group('default direct profile', () {
    test('is created only for an empty Windows profile store', () {
      expect(
        shouldCreateDefaultDirectProfile(isWindows: true, hasProfiles: false),
        isTrue,
      );
      expect(
        shouldCreateDefaultDirectProfile(isWindows: true, hasProfiles: true),
        isFalse,
      );
      expect(
        shouldCreateDefaultDirectProfile(isWindows: false, hasProfiles: false),
        isFalse,
      );
    });

    test('routes all traffic directly', () {
      expect(defaultDirectProfileLabel, '直连');
      expect(defaultDirectProfileYaml, contains('mode: rule'));
      expect(defaultDirectProfileYaml, contains('proxies: []'));
      expect(defaultDirectProfileYaml, contains('proxy-groups: []'));
      expect(defaultDirectProfileYaml, contains('MATCH,DIRECT'));
    });
  });
}
