import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/models/common/landscape_mode.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart'
    show SystemChrome, MethodChannel, SystemUiOverlay, DeviceOrientation;

bool _isDesktopFullScreen = false;

@pragma('vm:notify-debugger-on-exception')
Future<void> enterDesktopFullScreen({bool inAppFullScreen = false}) async {
  if (!inAppFullScreen && !_isDesktopFullScreen) {
    _isDesktopFullScreen = true;
    try {
      await const MethodChannel(
        'com.alexmercerind/media_kit_video',
      ).invokeMethod('Utils.EnterNativeFullscreen');
    } catch (_) {}
  }
}

@pragma('vm:notify-debugger-on-exception')
Future<void> exitDesktopFullScreen() async {
  if (_isDesktopFullScreen) {
    _isDesktopFullScreen = false;
    try {
      await const MethodChannel(
        'com.alexmercerind/media_kit_video',
      ).invokeMethod('Utils.ExitNativeFullscreen');
    } catch (_) {}
  }
}

List<DeviceOrientation>? _lastOrientation;
Future<void>? _setPreferredOrientations(List<DeviceOrientation> orientations) {
  if (_lastOrientation == orientations) {
    return null;
  }
  _lastOrientation = orientations;
  return SystemChrome.setPreferredOrientations(orientations);
}

List<DeviceOrientation> _resolveOrientations(
  List<DeviceOrientation> requested,
) => switch (Pref.landscapeMode) {
  LandscapeMode.disabled => requested,
  LandscapeMode.landscape => const [.landscapeLeft],
  LandscapeMode.reverseLandscape => const [.landscapeRight],
};

Future<void>? portraitUpMode() {
  return _setPreferredOrientations(_resolveOrientations(const [.portraitUp]));
}

Future<void>? portraitDownMode() {
  return _setPreferredOrientations(_resolveOrientations(const [.portraitDown]));
}

Future<void>? landscapeLeftMode() {
  return _setPreferredOrientations(_resolveOrientations(const [.landscapeLeft]));
}

Future<void>? landscapeRightMode() {
  return _setPreferredOrientations(_resolveOrientations(const [.landscapeRight]));
}

Future<void>? fullMode() {
  return _setPreferredOrientations(
    _resolveOrientations(
      const [.portraitUp, .portraitDown, .landscapeLeft, .landscapeRight],
    ),
  );
}

/// Applies the global landscape preference, or restores the original
/// orientation policy when the preference is disabled.
Future<void>? applyLandscapeMode() => switch (Pref.landscapeMode) {
  LandscapeMode.disabled =>
    Pref.horizontalScreen ? fullMode() : portraitUpMode(),
  LandscapeMode.landscape => _setPreferredOrientations(const [.landscapeLeft]),
  LandscapeMode.reverseLandscape =>
    _setPreferredOrientations(const [.landscapeRight]),
};

bool _showSystemBar = true;
bool get showSystemBar_ => _showSystemBar;
Future<void>? hideSystemBar() {
  if (!_showSystemBar) {
    return null;
  }
  _showSystemBar = false;
  return SystemChrome.setEnabledSystemUIMode(.immersiveSticky);
}

//退出全屏显示
Future<void>? showSystemBar() {
  if (_showSystemBar) {
    return null;
  }
  _showSystemBar = true;
  return SystemChrome.setEnabledSystemUIMode(
    Platform.isAndroid && DeviceUtils.sdkInt < 29 ? .manual : .edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
}
