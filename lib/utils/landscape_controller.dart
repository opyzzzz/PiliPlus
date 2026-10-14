import 'package:PiliPlus/models/common/landscape_mode.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

typedef OrientationApplier =
    Future<void>? Function(List<DeviceOrientation> orientations);

/// Single policy entry point for the global landscape preference.
///
/// Persistence and orientation resolution live here so settings and player
/// controls cannot drift into separate implementations. The fullscreen
/// utility remains responsible for applying orientations and deduplicating
/// platform calls.
abstract final class LandscapeController {
  static Future<void> setMode(LandscapeMode mode) =>
      GStorage.setting.put(SettingBoxKey.landscapeMode, mode.index);

  static Future<void> toggle() => setMode(
    Pref.landscapeMode == LandscapeMode.landscape
        ? LandscapeMode.reverseLandscape
        : LandscapeMode.landscape,
  );

  static Future<void> disable() => setMode(LandscapeMode.disabled);

  static List<DeviceOrientation> resolveOrientations(
    List<DeviceOrientation> requested,
  ) => switch (Pref.landscapeMode) {
    LandscapeMode.disabled => requested,
    LandscapeMode.landscape => const [.landscapeLeft],
    LandscapeMode.reverseLandscape => const [.landscapeRight],
  };

  /// Applies the global preference. When disabled, preserve the app's
  /// configured default orientation policy (including tablet adaptation).
  static Future<void>? apply(OrientationApplier applyOrientations) =>
      switch (Pref.landscapeMode) {
        LandscapeMode.disabled =>
          Pref.horizontalScreen
              ? applyOrientations(const [
                  .portraitUp,
                  .portraitDown,
                  .landscapeLeft,
                  .landscapeRight,
                ])
              : applyOrientations(const [.portraitUp]),
        LandscapeMode.landscape =>
          applyOrientations(const [.landscapeLeft]),
        LandscapeMode.reverseLandscape =>
          applyOrientations(const [.landscapeRight]),
      };
}
