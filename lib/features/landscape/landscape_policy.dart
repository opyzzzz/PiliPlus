import 'package:PiliPlus/models/common/landscape_mode.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart' show DeviceOrientation;

/// Pure orientation decisions for the landscape feature.
///
/// This class deliberately does not read preferences or call platform APIs,
/// so each mode can be tested independently from storage and player lifecycle.
abstract final class LandscapePolicy {
  /// Whether two orientation requests contain the same ordered values.
  ///
  /// List equality must be structural here: separately allocated lists with
  /// identical values should not trigger duplicate platform requests.
  static bool sameOrientations(
    List<DeviceOrientation> first,
    List<DeviceOrientation> second,
  ) => listEquals(first, second);

  static List<DeviceOrientation> resolveOrientations(
    LandscapeMode mode,
    List<DeviceOrientation> requested,
  ) => switch (mode) {
    LandscapeMode.disabled => requested,
    LandscapeMode.landscape => const [.landscapeLeft],
    LandscapeMode.reverseLandscape => const [.landscapeRight],
  };

  static List<DeviceOrientation> orientationsFor(
    LandscapeMode mode, {
    required bool horizontalScreen,
  }) => switch (mode) {
    LandscapeMode.disabled => horizontalScreen
        ? const [
            .portraitUp,
            .portraitDown,
            .landscapeLeft,
            .landscapeRight,
          ]
        : const [.portraitUp],
    LandscapeMode.landscape => const [.landscapeLeft],
    LandscapeMode.reverseLandscape => const [.landscapeRight],
  };
}
