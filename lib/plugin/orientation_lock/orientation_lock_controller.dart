import 'dart:async';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart';

import 'orientation_lock_mode.dart';
import 'orientation_lock_platform.dart';

/// The single business entry point for orientation-lock state transitions.
///
/// Settings can still be changed by legacy widgets. The Hive listener routes
/// those external changes back through this controller and its serialized
/// operation queue.
class OrientationLockController {
  OrientationLockController._();

  static final OrientationLockController instance = OrientationLockController._();

  Future<void> _operationQueue = Future<void>.value();

  bool _suspended = false;

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

  bool get suspended => _suspended;

  /// Whether the selected orientation should currently be applied.
  bool get shouldApply =>
      enabled && !_suspended && selectedMode != OrientationLockMode.system;

  /// Disabling releases native state before persisting the disabled state.
  /// Re-enabling never reapplies a previous orientation.
  Future<void> setEnabled(bool value) => _enqueue(() async {
        if (!value) {
          await OrientationLockPlatform.release();
          await _writeMode(OrientationLockMode.system);
          await _writeEnabled(false);
          return;
        }

        await GStorage.setting.put(SettingBoxKey.orientationLockEnabled, true);
      });

  /// Applies a user-selected mode through the one business entry point.
  Future<void> applyMode(OrientationLockMode mode) => _enqueue(() async {
        if (!enabled) {
          throw PlatformException(
            code: 'orientation_lock_disabled',
            message: '请先启用方向锁定',
          );
        }

        if (_suspended) {
          // Store the selection while suspended. It will be applied on resume.
          await _writeMode(mode);
          return;
        }

        if (mode == OrientationLockMode.system) {
          await OrientationLockPlatform.release();
        } else {
          await OrientationLockPlatform.apply(mode);
        }
        await _writeMode(mode);
      });

  /// Temporarily releases the native orientation without changing the user's
  /// enabled flag or selected mode (e.g. when entering PiP).
  Future<void> suspend() => _enqueue(() async {
        if (_suspended) return;
        _suspended = true;
        try {
          await OrientationLockPlatform.release();
        } catch (_) {
          _suspended = false;
          rethrow;
        }
      });

  /// Resumes a suspended lock only if it is still enabled and has a concrete
  /// selected mode. Native lifecycle code may also restore on foregrounding;
  /// platform requests are serialized to keep those transitions deterministic.
  Future<void> resume() => _enqueue(() async {
        if (!_suspended) return;
        _suspended = false;
        if (shouldApply) {
          try {
            await OrientationLockPlatform.apply(selectedMode);
          } catch (_) {
            _suspended = true;
            rethrow;
          }
        }
      });

  Future<void> _writeMode(OrientationLockMode mode) async {
    await GStorage.setting.put(SettingBoxKey.orientationLockMode, mode.wireValue);
  }

  Future<void> _writeEnabled(bool value) async {
    await GStorage.setting.put(SettingBoxKey.orientationLockEnabled, value);
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operationQueue.catchError((Object _) {}).then((_) => operation());
    _operationQueue = next;
    return next;
  }

}
