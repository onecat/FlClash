const defaultDirectProfileLabel = '直连';

const defaultDirectProfileYaml = '''
mixed-port: 7890
mode: rule
allow-lan: false
log-level: error

proxies: []
proxy-groups: []

rules:
  - MATCH,DIRECT
''';

bool shouldCreateDefaultDirectProfile({
  required bool isWindows,
  required bool hasProfiles,
}) {
  return isWindows && !hasProfiles;
}
