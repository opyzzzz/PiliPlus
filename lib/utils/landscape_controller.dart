import 'package:PiliPlus/features/landscape/landscape_feature.dart';
import 'package:PiliPlus/models/common/landscape_mode.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

/// Compatibility forwarding layer. New code should depend on
/// [LandscapeFeature] directly.
typedef OrientationApplier = LandscapeOrientationApplier;

@Deprecated('Use LandscapeFeature.setMode instead.')
abstract final class LandscapeController {
  @Deprecated('Use LandscapeFeature.setMode instead.')
  static Future<void> setMode(LandscapeMode mode) =>
      LandscapeFeature.setMode(mode);

  @Deprecated('Use LandscapeFeature.toggle instead.')
  static Future<void> toggle() => LandscapeFeature.toggle();

  @Deprecated('Use LandscapeFeature.disable instead.')
  static Future<void> disable() => LandscapeFeature.disable();

  @Deprecated('Use LandscapeFeature.resolveOrientations instead.')
  static List<DeviceOrientation> resolveOrientations(
    List<DeviceOrientation> requested,
  ) => LandscapeFeature.resolveOrientations(requested);

  @Deprecated('Use LandscapeFeature.apply instead.')
  static Future<void>? apply(OrientationApplier applyOrientations) =>
      LandscapeFeature.apply(applyOrientations);
}
