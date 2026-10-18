import 'package:flutter/services.dart';

import 'package:PiliPlus/plugin/pl_player/models/shortcut_action.dart';
import 'package:PiliPlus/services/shortcut_service.dart';

/// Bridges Android hardware keys that the platform may consume before Flutter's
/// Focus system receives them. Only keys that are actually bound are intercepted.
abstract final class MediaKeyShortcutBridge {
  static const MethodChannel _channel = MethodChannel('piliplus/media_key_shortcuts');
  static bool _enabled = false;
  static bool _handlerInstalled = false;
  static bool _lastEnabled = false;
  static Set<int> _lastKeyCodes = <int>{};

  static Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await sync();
  }

  /// Push the current opt-in and restricted bindings to Android.
  /// Unbound media/volume keys retain their normal system behavior.
  static Future<void> sync() async {
    _installHandler();
    final enabled = _enabled;
    final keyCodes = <int>{};
    if (enabled) {
      for (final action in ShortcutAction.values) {
        final binding = ShortcutService.bindingOf(action);
        if (binding != null) {
          final code = _androidKeyCode(binding.key);
          if (code != null) keyCodes.add(code);
        }
      }
      for (final id in ShortcutService.comboIds) {
        final binding = ShortcutService.comboBindingOf(id);
        if (binding != null) {
          final code = _androidKeyCode(binding.key);
          if (code != null) keyCodes.add(code);
        }
      }
    }
    if (enabled == _lastEnabled && _sameSet(keyCodes, _lastKeyCodes)) return;
    _lastEnabled = enabled;
    _lastKeyCodes = keyCodes;
    try {
      await _channel.invokeMethod<void>('setEnabled', {
        'enabled': enabled,
        'keyCodes': keyCodes.toList(growable: false),
      });
    } on MissingPluginException {
      // Android-specific bridge; other platforms use normal key events.
    } on PlatformException {
      // A transient channel failure must not break shortcut configuration.
    }
  }

  static bool _sameSet(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  static int? _androidKeyCode(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.audioVolumeUp => 24,
    LogicalKeyboardKey.audioVolumeDown => 25,
    LogicalKeyboardKey.audioVolumeMute => 164,
    LogicalKeyboardKey.mediaPlayPause => 85,
    LogicalKeyboardKey.mediaTrackNext => 87,
    LogicalKeyboardKey.mediaTrackPrevious => 88,
    _ => null,
  };

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'keyEvent' || !_enabled) return;
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      final keyCode = args['keyCode'] as int?;
      final action = args['action'] as String?;
      final logicalKey = switch (keyCode) {
        24 => LogicalKeyboardKey.audioVolumeUp,
        25 => LogicalKeyboardKey.audioVolumeDown,
        164 => LogicalKeyboardKey.audioVolumeMute,
        85 => LogicalKeyboardKey.mediaPlayPause,
        87 => LogicalKeyboardKey.mediaTrackNext,
        88 => LogicalKeyboardKey.mediaTrackPrevious,
        _ => null,
      };
      final physicalKeyId = switch (keyCode) {
        24 => 0x000700e9,
        25 => 0x000700ea,
        164 => 0x000700e2,
        85 => 0x000c00cd,
        87 => 0x000c00b5,
        88 => 0x000c00b6,
        _ => null,
      };
      if (logicalKey == null || physicalKeyId == null) return;
      final physicalKey = PhysicalKeyboardKey(physicalKeyId);
      final event = switch (action) {
        'down' => KeyDownEvent(physicalKey: physicalKey, logicalKey: logicalKey, timeStamp: Duration.zero),
        'repeat' => KeyRepeatEvent(physicalKey: physicalKey, logicalKey: logicalKey, timeStamp: Duration.zero),
        'up' => KeyUpEvent(physicalKey: physicalKey, logicalKey: logicalKey, timeStamp: Duration.zero),
        _ => null,
      };
      if (event != null) HardwareKeyboard.instance.handleKeyEvent(event);
    });
  }
}
