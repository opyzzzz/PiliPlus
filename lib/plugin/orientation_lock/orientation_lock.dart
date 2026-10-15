import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

abstract final class OrientationLockPlatform {
  static const _channel = MethodChannel(
    'com.example.piliplus/orientation_lock',
  );

  static Future<void> _orientationQueue = Future<void>.value();

  static Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('requestOverlayPermission');
    } on PlatformException catch (e) {
      SmartDialog.showToast(e.message ?? '无法请求悬浮窗权限');
    }
  }

  static Future<void> setOrientation(String mode) {
    if (!Platform.isAndroid) return Future<void>.value();

    // Keep native service requests in order; a fast second tap must not
    // overwrite the result callback for the previous request.
    final request = _orientationQueue.catchError((_) {}).then((_) async {
      await _channel.invokeMethod<bool>(
        'setOrientation',
        <String, Object>{'mode': mode},
      );
    });
    _orientationQueue = request;
    return request;
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await setOrientation('default');
    } on PlatformException catch (e) {
      SmartDialog.showToast(e.message ?? '释放方向锁定失败');
    }
  }
}

class OrientationLockButton extends StatelessWidget {
  const OrientationLockButton({required this.showControls, super.key});

  final bool showControls;

  static const _modes = <({String value, String label, IconData icon})>[
    (value: 'default', label: '默认', icon: Icons.screen_rotation_outlined),
    (value: 'portrait', label: '竖屏', icon: Icons.stay_current_portrait),
    (value: 'landscape', label: '横屏', icon: Icons.stay_current_landscape),
    (value: 'reverseLandscape', label: '反向横屏', icon: Icons.screen_rotation),
  ];

  Future<void> _applyMode(String mode) async {
    try {
      await OrientationLockPlatform.setOrientation(mode);
      await GStorage.setting.put(SettingBoxKey.orientationLockMode, mode);
    } on PlatformException catch (e) {
      SmartDialog.showToast(e.message ?? '方向锁定失败');
    } catch (_) {
      SmartDialog.showToast('方向锁定失败');
    }
  }

  PopupMenuItem<String> _buildModeItem(
    ({String value, String label, IconData icon}) mode,
    String selectedMode,
    ColorScheme colorScheme,
  ) {
    final selected = mode.value == selectedMode;
    return PopupMenuItem<String>(
      value: mode.value,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mode.icon, size: 18,
            color: selected ? colorScheme.secondary : Colors.white),
          const SizedBox(width: 10),
          Text(mode.label, style: TextStyle(fontSize: 13,
            color: selected ? colorScheme.secondary : Colors.white)),
          if (selected) ...[
            const SizedBox(width: 12),
            Icon(Icons.check, size: 16, color: colorScheme.secondary),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid || !showControls ||
        !GStorage.setting.get(SettingBoxKey.orientationLockEnabled,
            defaultValue: false)) {
      return const SizedBox.shrink();
    }

    final layout = GStorage.setting.get(
      SettingBoxKey.orientationLockMenuLayout, defaultValue: 0);
    final selectedMode = GStorage.setting.get(
      SettingBoxKey.orientationLockMode, defaultValue: 'default');
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      tooltip: '方向锁定',
      requestFocus: false,
      initialValue: selectedMode,
      color: Colors.black.withValues(alpha: 0.8),
      onSelected: _applyMode,
      itemBuilder: (menuContext) {
        if (layout == 0) {
          final availableWidth = MediaQuery.sizeOf(menuContext).width - 32;
          return [
            PopupMenuItem<String>(
              enabled: false,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              height: 58,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: availableWidth.clamp(120.0, 360.0),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final mode in _modes)
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => Navigator.of(menuContext).pop(mode.value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(mode.icon, size: 18,
                                  color: mode.value == selectedMode
                                      ? colorScheme.secondary : Colors.white),
                                const SizedBox(height: 4),
                                Text(mode.label, style: TextStyle(fontSize: 12,
                                  color: mode.value == selectedMode
                                      ? colorScheme.secondary : Colors.white)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ];
        }
        return _modes.map(
          (mode) => _buildModeItem(mode, selectedMode, colorScheme),
        ).toList();
      },
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0x45000000),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        child: const SizedBox(
          width: 40, height: 40,
          child: Icon(Icons.screen_rotation_outlined,
            size: 20, color: Colors.white),
        ),
      ),
    );
  }
}
