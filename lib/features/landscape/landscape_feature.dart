import 'package:PiliPlus/models/common/landscape_mode.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import 'package:PiliPlus/features/landscape/landscape_policy.dart';

/// Public entry point for the landscape feature.
///
/// Preference changes and orientation policy are centralized here. The player
/// supplies its platform adapter so existing orientation deduplication and
/// lifecycle behavior remain intact.
typedef LandscapeOrientationApplier =
    Future<void>? Function(List<DeviceOrientation> orientations);

abstract final class LandscapeFeature {
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

  /// Resolve a requested orientation set using the configured policy.
  static List<DeviceOrientation> resolveOrientations(
    List<DeviceOrientation> requested,
  ) => LandscapePolicy.resolveOrientations(Pref.landscapeMode, requested);

  /// Apply the configured policy through the host platform adapter.
  /// When disabled, preserve the default policy, including tablet adaptation.
  static Future<void>? apply(LandscapeOrientationApplier applyOrientations) =>
      applyOrientations(
        LandscapePolicy.orientationsFor(
          Pref.landscapeMode,
          horizontalScreen: Pref.horizontalScreen,
        ),
      );
}
