import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';

Future<({Config config, List<Profile> profiles})> ensureDefaultDirectProfile({
  required Config config,
  required bool isWindows,
}) async {
  final profiles = await database.profilesDao.query().get();
  if (!shouldCreateDefaultDirectProfile(
    isWindows: isWindows,
    hasProfiles: profiles.isNotEmpty,
  )) {
    return (config: config, profiles: profiles);
  }

  final profile = Profile.normal(
    label: defaultDirectProfileLabel,
  ).copyWith(autoUpdate: false, lastUpdateDate: DateTime.now());
  final file = await profile.file;
  try {
    await file.safeWriteAsString(defaultDirectProfileYaml);
    await database.profiles.put(profile.toCompanion());
    final nextConfig = config.copyWith(currentProfileId: profile.id);
    final saved = await preferences.saveConfig(nextConfig);
    if (!saved) {
      throw StateError('failed to persist default profile selection');
    }
    return (config: nextConfig, profiles: [profile]);
  } catch (_) {
    await database.profilesDao.setAll(const []);
    await file.safeDelete();
    rethrow;
  }
}
