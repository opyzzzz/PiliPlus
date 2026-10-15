import 'dart:async';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';

import 'orientation_lock_mode.dart';
import 'orientation_lock_platform.dart';

/// The single business entry point for orientation-lock state transitions.
///
/// Settings can still be changed by legacy settings widgets. The Hive listener
/// treats those writes as external state changes and reconciles native state.
class OrientationLockController {
  OrientationLockController._() {
    _settingsSubscription = GStorage.setting.watch().listen(_onSettingChanged);
  }

  static final OrientationLockController instance = OrientationLockController._();

  StreamSubscription<BoxEvent>? _settingsSubscription;
  Future<void> _operationQueue = Future<void>.value();
  bool _disposed = false;

  bool get enabled =>
      GStorage.setting.get(SettingBoxKey.orientationLockEnabled, defaultValue: false) == true;

  OrientationLockMode get selectedMode {
    final value = GStorage.setting.get(
      SettingBoxKey.orientationLockMode,
      defaultValue: OrientationLockMode.system.wireValue,
    );
    return OrientationLockMode.values.firstWhere(
      (mode) => mode.wireValue == value,
      orElse: () => OrientationLockMode.system,
    );
  }

  /// Disabling is transactional: release native state before persisting the
  /// disabled state. Re-enabling never reapplies a previous orientation.
  Future<void> setEnabled(bool value) => _enqueue(() async {
        if (!value) {
          await OrientationLockPlatform.release();
          await GStorage.setting.put(
            SettingBoxKey.orientationLockMode,
            OrientationLockMode.system.wireValue,
          );
          await GStorage.setting.put(SettingBoxKey.orientationLockEnabled, false);
          return;
        }

        await GStorage.setting.put(SettingBoxKey.orientationLockEnabled, true);
        // Deliberately do not restore the old mode on enable.
      });

  Future<void> applyMode(OrientationLockMode mode) => _enqueue(() async {
        if (!enabled) {
          throw PlatformException(
            code: 'orientation_lock_disabled',
            message: '请先启用方向锁定',
          );
        }

        if (mode == OrientationLockMode.system) {
          await OrientationLockPlatform.release();
        } else {
          await OrientationLockPlatform.apply(mode);
        }
        await GStorage.setting.put(SettingBoxKey.orientationLockMode, mode.wireValue);
      });

  void _onSettingChanged(BoxEvent event) {
    if (_disposed ||
        (event.key != SettingBoxKey.orientationLockEnabled &&
            event.key != SettingBoxKey.orientationLockMode)) {
      return;
    }

    // The settings page currently writes directly to Hive. Reconcile those
    // external changes through the same serialized native-operation queue.
    if (event.key == SettingBoxKey.orientationLockEnabled && event.value == false) {
      unawaited(_enqueue(() async {
        await OrientationLockPlatform.release();
        await GStorage.setting.put(
          SettingBoxKey.orientationLockMode,
          OrientationLockMode.system.wireValue,
        );
      }).catchError((Object error) async {
        // Do not leave the UI claiming the feature is disabled when native
        // release failed; preserve the previous enabled state for retry.
        await GStorage.setting.put(SettingBoxKey.orientationLockEnabled, true);
        Error.throwWithStackTrace(error, StackTrace.current);
      }));
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operationQueue.catchError((Object _) {}).then((_) => operation());
    _operationQueue = next;
    return next;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _settingsSubscription?.cancel();
    _settingsSubscription = null;
  }
}
