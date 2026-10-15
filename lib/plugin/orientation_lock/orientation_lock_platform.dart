import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'orientation_lock_mode.dart';
import 'orientation_lock_protocol.dart';

abstract final class OrientationLockPlatform {
  static const _channel = MethodChannel(OrientationLockProtocol.channelName);

  static Future<void> _orientationQueue = Future<void>.value();

  /// Requests overlay permission and reports whether it is already granted.
  /// Android returns false when it opens system settings; the caller must not
  /// persist the feature as enabled until a later attempt confirms permission.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>(
            OrientationLockProtocol.requestOverlayPermission,
          ) ??
          false;
    } on PlatformException catch (e) {
      SmartDialog.showToast(e.message ?? '无法请求悬浮窗权限');
      return false;
    }
  }

  static Future<void> apply(OrientationLockMode mode) => _setMode(mode);

  static Future<void> _setMode(OrientationLockMode mode) {
    if (!Platform.isAndroid) return Future<void>.value();

    // Keep native service requests in order; a fast second tap must not
    // overwrite the result callback for the previous request.
    final request = _orientationQueue.catchError((_) {}).then((_) async {
      await _channel.invokeMethod<bool>(
        OrientationLockProtocol.setOrientation,
        <String, Object>{OrientationLockProtocol.modeArgument: mode.wireValue},
      );
    });
    _orientationQueue = request;
    return request;
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    // Let the caller handle failures. A failed release must not be persisted
    // as though the feature had returned to its default state.
    await _setMode(OrientationLockMode.system);
  }
}
