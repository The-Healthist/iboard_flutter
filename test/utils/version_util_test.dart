import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/utils/version_util.dart';

void main() {
  group('VersionUtil.compareVersions', () {
    test('compares versions with different segment lengths', () {
      expect(VersionUtil.compareVersions('1.2', '1.2.0'), 0);
      expect(VersionUtil.compareVersions('1.2.1', '1.2'), 1);
      expect(VersionUtil.compareVersions('1.2', '1.2.1'), -1);
    });

    test('uses numeric prefixes for semver-style suffixes', () {
      expect(VersionUtil.compareVersions('1.2.3-beta', '1.2.2'), 1);
      expect(VersionUtil.compareVersions('1.2.3+4', '1.2.3'), 0);
    });
  });

  group('VersionUtil.compareBuildNumbers', () {
    test('trims build numbers and treats invalid values as zero', () {
      expect(VersionUtil.compareBuildNumbers(' 10 ', '2'), 1);
      expect(VersionUtil.compareBuildNumbers('bad', '1'), -1);
      expect(VersionUtil.compareBuildNumbers('bad', 'also-bad'), 0);
    });
  });

  group('VersionUtil.needsUpdate', () {
    test('detects remote build update when versions match', () {
      expect(VersionUtil.needsUpdate('1.2.3', '1', '1.2.3', '2'), isTrue);
      expect(VersionUtil.needsUpdate('1.2.3', '2', '1.2.3', '1'), isFalse);
    });
  });
}
