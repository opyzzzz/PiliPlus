import 'dart:async';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';

import 'orientation_lock_mode.dart';
import 'orientation_lock_platform.dart';

/// The single business entry point for orientation-lock state transitions.
///
/// Settings can still be changed by legacy widgets. The Hive listener routes
/// those external changes back through this controller and its serialized
/// operation queue.
class OrientationLockController {
  OrientationLockController._() {
    _settingsSubscription = GStorage.setting.watch().listen(_onSettingChanged);
  }

  static final OrientationLockController instance = OrientationLockController._();

  StreamSubscription<BoxEvent>? _settingsSubscription;
  Future<void> _operationQueue = Future<void>.value();
  bool _disposed = false;
  int _internalDisabledWrites = 0;
  int _internalModeWrites = 0;

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
        await OrientationLockPlatform.release();
      });

  /// Resumes a suspended lock only if it is still enabled and has a concrete
  /// selected mode. Native lifecycle code may also restore on foregrounding;
  /// platform requests are serialized to keep those transitions deterministic.
  Future<void> resume() => _enqueue(() async {
        if (!_suspended) return;
        _suspended = false;
        if (shouldApply) {
          await OrientationLockPlatform.apply(selectedMode);
        }
      });

  void _onSettingChanged(BoxEvent event) {
    if (_disposed) return;

    if (event.key == SettingBoxKey.orientationLockEnabled && event.value == false) {
      if (_internalDisabledWrites > 0) {
        _internalDisabledWrites--;
        return;
      }
      unawaited(_enqueue(() async {
        await OrientationLockPlatform.release();
        await _writeMode(OrientationLockMode.system);
      }).catchError((Object error) async {
        // Preserve the enabled state if native release fails, allowing retry.
        await GStorage.setting.put(SettingBoxKey.orientationLockEnabled, true);
      }));
      return;
    }

    if (event.key == SettingBoxKey.orientationLockMode) {
      if (_internalModeWrites > 0) {
        _internalModeWrites--;
        return;
      }
      // Legacy settings widgets that write the mode directly are reconciled
      // through this controller as well. A disabled feature never applies it.
      unawaited(_enqueue(() async {
        if (!enabled || _suspended) return;
        final mode = selectedMode;
        if (mode == OrientationLockMode.system) {
          await OrientationLockPlatform.release();
        } else {
          await OrientationLockPlatform.apply(mode);
        }
      }).catchError((Object error) {
        // The initiating legacy UI has no Future to await; avoid an uncaught
        // asynchronous error. Explicit controller calls still report failures.
      }));
    }
  }

  Future<void> _writeMode(OrientationLockMode mode) async {
    _internalModeWrites++;
    try {
      await GStorage.setting.put(SettingBoxKey.orientationLockMode, mode.wireValue);
    } catch (_) {
      _internalModeWrites--;
      rethrow;
    }
  }

  Future<void> _writeEnabled(bool value) async {
    _internalDisabledWrites++;
    try {
      await GStorage.setting.put(SettingBoxKey.orientationLockEnabled, value);
    } catch (_) {
      _internalDisabledWrites--;
      rethrow;
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
