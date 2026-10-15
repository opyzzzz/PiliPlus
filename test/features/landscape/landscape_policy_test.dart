import 'package:PiliPlus/features/landscape/landscape_policy.dart';
import 'package:PiliPlus/models/common/landscape_mode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LandscapePolicy.sameOrientations', () {
    test('treats separate lists with equal ordered values as equal', () {
      final first = [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft];
      final second = [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft];

      expect(identical(first, second), isFalse);
      expect(LandscapePolicy.sameOrientations(first, second), isTrue);
    });

    test('treats different values as unequal', () {
      expect(
        LandscapePolicy.sameOrientations(
          const [DeviceOrientation.portraitUp],
          const [DeviceOrientation.portraitDown],
        ),
        isFalse,
      );
    });

    test('preserves order when comparing requests', () {
      expect(
        LandscapePolicy.sameOrientations(
          const [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft],
          const [DeviceOrientation.landscapeLeft, DeviceOrientation.portraitUp],
        ),
        isFalse,
      );
    });

    test('treats empty lists as equal', () {
      expect(
        LandscapePolicy.sameOrientations(
          const <DeviceOrientation>[],
          const <DeviceOrientation>[],
        ),
        isTrue,
      );
    });
  });

  group('LandscapePolicy.resolveOrientations', () {
    test('preserves requested orientations when disabled', () {
      const requested = [DeviceOrientation.portraitDown];
      expect(
        LandscapePolicy.resolveOrientations(LandscapeMode.disabled, requested),
        same(requested),
      );
    });

    test('uses left landscape for normal mode', () {
      expect(
        LandscapePolicy.resolveOrientations(
          LandscapeMode.landscape,
          const [DeviceOrientation.portraitUp],
        ),
        const [DeviceOrientation.landscapeLeft],
      );
    });

    test('uses right landscape for reverse mode', () {
      expect(
        LandscapePolicy.resolveOrientations(
          LandscapeMode.reverseLandscape,
          const [DeviceOrientation.portraitUp],
        ),
        const [DeviceOrientation.landscapeRight],
      );
    });
  });

  group('LandscapePolicy.orientationsFor', () {
    test('restores all orientations when disabled and horizontal is enabled', () {
      expect(
        LandscapePolicy.orientationsFor(
          LandscapeMode.disabled,
          horizontalScreen: true,
        ),
        const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
    });

    test('restores portrait only when disabled and horizontal is disabled', () {
      expect(
        LandscapePolicy.orientationsFor(
          LandscapeMode.disabled,
          horizontalScreen: false,
        ),
        const [DeviceOrientation.portraitUp],
      );
    });

    test('keeps explicit landscape modes independent of horizontal setting', () {
      expect(
        LandscapePolicy.orientationsFor(
          LandscapeMode.landscape,
          horizontalScreen: false,
        ),
        const [DeviceOrientation.landscapeLeft],
      );
      expect(
        LandscapePolicy.orientationsFor(
          LandscapeMode.reverseLandscape,
          horizontalScreen: true,
        ),
        const [DeviceOrientation.landscapeRight],
      );
    });
  });
}
