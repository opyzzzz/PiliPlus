import 'package:PiliPlus/models/common/landscape_mode.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/material.dart' show BoxDecoration, BorderRadius, Color, Colors, DecoratedBox, GestureDetector, Icon, Icons, Radius, SizedBox, Tooltip, Widget, Center, HitTestBehavior;
import 'package:flutter/services.dart' show DeviceOrientation;

/// Public entry point for the landscape feature.
///
/// Preference changes and orientation policy are centralized here. The player
/// supplies its platform adapter so existing orientation deduplication and
/// lifecycle behavior remain intact.
typedef LandscapeOrientationApplier =
    Future<void>? Function(List<DeviceOrientation> orientations);

abstract final class LandscapeFeature {
  /// Build the player control for switching landscape direction.
  ///
  /// The host supplies the actions, while the feature owns the visual control
  /// and its tap/long-press affordances.
  static Widget buildToggleButton({
    required void Function() onToggle,
    required void Function() onLongPress,
  }) => Tooltip(
    message: '切换横屏方向（长按关闭）',
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0x45000000),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        onLongPress: onLongPress,
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(
              Icons.screen_rotation_outlined,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ),
  );

  /// Persist the selected global landscape mode.
  static Future<void> setMode(LandscapeMode mode) =>
      GStorage.setting.put(SettingBoxKey.landscapeMode, mode.index);

  /// Switch between normal and reverse landscape.
  static Future<void> toggle() => setMode(
    Pref.landscapeMode == LandscapeMode.landscape
        ? LandscapeMode.reverseLandscape
        : LandscapeMode.landscape,
  );

  /// Disable the forced landscape policy.
  static Future<void> disable() => setMode(LandscapeMode.disabled);

  /// Apply the global policy to a requested orientation set.
  static List<DeviceOrientation> resolveOrientations(
    List<DeviceOrientation> requested,
  ) => switch (Pref.landscapeMode) {
    LandscapeMode.disabled => requested,
    LandscapeMode.landscape => const [.landscapeLeft],
    LandscapeMode.reverseLandscape => const [.landscapeRight],
  };

  /// Apply the configured policy through the host platform adapter.
  /// When disabled, preserve the default policy, including tablet adaptation.
  static Future<void>? apply(LandscapeOrientationApplier applyOrientations) =>
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
