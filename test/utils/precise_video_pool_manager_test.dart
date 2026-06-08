import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/utils/precise_video_pool_manager.dart';

void main() {
  group('VideoPoolResourcePolicy.selectDecoderToRelease', () {
    test('ignores playing and protected decoders', () {
      final now = DateTime.utc(2026, 6, 8, 12);

      expect(
        VideoPoolResourcePolicy.selectDecoderToRelease(
          initializedKeys: ['topAd_a', 'fullAd_b', 'other_c'],
          playingKeys: {'topAd_a'},
          protectedKeys: {'fullAd_b'},
          usageCounts: {
            'topAd_a': 1,
            'fullAd_b': 1,
            'other_c': 10,
          },
          lastUsed: {
            'other_c': now.subtract(const Duration(minutes: 1)),
          },
          now: now,
        ),
        'other_c',
      );
    });

    test('prefers lower usage, then oldest last-used time', () {
      final now = DateTime.utc(2026, 6, 8, 12);

      expect(
        VideoPoolResourcePolicy.selectDecoderToRelease(
          initializedKeys: ['a', 'b', 'c'],
          playingKeys: const {},
          protectedKeys: const {},
          usageCounts: {
            'a': 3,
            'b': 1,
            'c': 1,
          },
          lastUsed: {
            'b': now.subtract(const Duration(minutes: 1)),
            'c': now.subtract(const Duration(minutes: 5)),
          },
          now: now,
        ),
        'c',
      );
    });

    test('returns null when every initialized decoder is protected', () {
      final now = DateTime.utc(2026, 6, 8, 12);

      expect(
        VideoPoolResourcePolicy.selectDecoderToRelease(
          initializedKeys: ['topAd_a', 'fullAd_b'],
          playingKeys: {'topAd_a'},
          protectedKeys: {'fullAd_b'},
          usageCounts: {
            'topAd_a': 1,
            'fullAd_b': 1,
          },
          lastUsed: const {},
          now: now,
        ),
        isNull,
      );
    });
  });

  group('VideoPoolResourcePolicy.selectPlayingKeyToPause', () {
    test('prefers higher usage, then oldest last-used time', () {
      final now = DateTime.utc(2026, 6, 8, 12);

      expect(
        VideoPoolResourcePolicy.selectPlayingKeyToPause(
          playingKeys: ['a', 'b', 'c'],
          availableKeys: {'a', 'b', 'c'},
          usageCounts: {
            'a': 1,
            'b': 4,
            'c': 4,
          },
          lastUsed: {
            'b': now.subtract(const Duration(minutes: 1)),
            'c': now.subtract(const Duration(minutes: 5)),
          },
          now: now,
        ),
        'c',
      );
    });

    test('skips keys that are no longer in the controller pool', () {
      final now = DateTime.utc(2026, 6, 8, 12);

      expect(
        VideoPoolResourcePolicy.selectPlayingKeyToPause(
          playingKeys: ['stale', 'active'],
          availableKeys: {'active'},
          usageCounts: {
            'stale': 99,
            'active': 1,
          },
          lastUsed: const {},
          now: now,
        ),
        'active',
      );
    });

    test('returns null when no playing keys are available', () {
      final now = DateTime.utc(2026, 6, 8, 12);

      expect(
        VideoPoolResourcePolicy.selectPlayingKeyToPause(
          playingKeys: ['stale'],
          availableKeys: const {},
          usageCounts: {'stale': 1},
          lastUsed: const {},
          now: now,
        ),
        isNull,
      );
    });
  });
}
