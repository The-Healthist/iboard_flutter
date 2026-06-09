import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/dual_pdf_announcement_widget.dart';

void main() {
  group('debugBuildDualAnnouncementFrames', () {
    test('fits page images without cropping or distortion', () {
      expect(debugDualAnnouncementPageFit, BoxFit.contain);
    });

    test('pairs flattened PDF pages two at a time', () {
      final frames = debugBuildDualAnnouncementFrames(
        <String>['1.1', '2.1', '2.2', '3.1', '3.2'],
      );

      expect(
        frames,
        <List<String?>>[
          <String?>['1.1', '2.1'],
          <String?>['2.2', '3.1'],
          <String?>['3.2', null],
        ],
      );
    });

    test('supports custom slot counts', () {
      final frames = debugBuildDualAnnouncementFrames(
        <int>[1, 2, 3, 4, 5],
        slotsPerFrame: 3,
      );

      expect(
        frames,
        <List<int?>>[
          <int?>[1, 2, 3],
          <int?>[4, 5, null],
        ],
      );
    });
  });
}
