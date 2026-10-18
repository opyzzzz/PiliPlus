import 'package:flutter/services.dart';

/// Bridges Android hardware keys that the platform may consume before Flutter's
/// Focus system receives them. Keys are only intercepted after explicit opt-in.
abstract final class MediaKeyShortcutBridge {
  static const MethodChannel _channel = MethodChannel(
    'piliplus/media_key_shortcuts',
  );
  static bool _enabled = false;
  static bool _handlerInstalled = false;

  static Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    _installHandler();
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // This bridge is Android-specific; other platforms use normal key events.
    } on PlatformException {
      // A transient channel failure must not break settings interaction.
    }
  }

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
        87 => LogicalKeyboardKey.mediaTrackNext,
        88 => LogicalKeyboardKey.mediaTrackPrevious,
        _ => null,
      };
      final physicalKeyId = switch (keyCode) {
        24 => 0x000700e9,
        25 => 0x000700ea,
        87 => 0x000c00b5,
        88 => 0x000c00b6,
        _ => null,
      };
      if (logicalKey == null || physicalKeyId == null) return;
      final physicalKey = PhysicalKeyboardKey(physicalKeyId);
      final event = switch (action) {
        'down' => KeyDownEvent(
          physicalKey: physicalKey,
          logicalKey: logicalKey,
          timeStamp: Duration.zero,
        ),
        'repeat' => KeyRepeatEvent(
          physicalKey: physicalKey,
          logicalKey: logicalKey,
          timeStamp: Duration.zero,
        ),
        'up' => KeyUpEvent(
          physicalKey: physicalKey,
          logicalKey: logicalKey,
          timeStamp: Duration.zero,
        ),
        _ => null,
      };
      if (event != null) {
        HardwareKeyboard.instance.handleKeyEvent(event);
      }
    });
  }
}
