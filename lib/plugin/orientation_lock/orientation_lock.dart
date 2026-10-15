import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

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

  Future<void> _selectMode(BuildContext context) async {
    final layout = GStorage.setting.get(
      SettingBoxKey.orientationLockMenuLayout,
      defaultValue: 0,
    );
    final selectedMode = GStorage.setting.get(
      SettingBoxKey.orientationLockMode,
      defaultValue: 'default',
    );
    await Get.dialog<void>(
      Builder(
        builder: (dialogContext) => AlertDialog(
          title: const Text('方向锁定'),
          content: layout == 0
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final mode in _modes)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _modeButton(dialogContext, mode, selectedMode),
                        ),
                    ],
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mode in _modes)
                      SizedBox(
                        width: 124,
                        child: _modeButton(dialogContext, mode, selectedMode),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _modeButton(
    BuildContext dialogContext,
    ({String value, String label, IconData icon}) mode,
    String selectedMode,
  ) {
    return OutlinedButton.icon(
      onPressed: () async {
        Navigator.of(dialogContext).pop();
        try {
          await OrientationLockPlatform.setOrientation(mode.value);
          await GStorage.setting.put(SettingBoxKey.orientationLockMode, mode.value);
        } on PlatformException catch (e) {
          SmartDialog.showToast(e.message ?? '方向锁定失败');
        } catch (_) {
          SmartDialog.showToast('方向锁定失败');
        }
      },
      icon: Icon(mode.icon),
      label: Text(mode.label),
      style: OutlinedButton.styleFrom(
        backgroundColor: mode.value == selectedMode
            ? Theme.of(dialogContext).colorScheme.secondaryContainer
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid ||
        !showControls ||
        !GStorage.setting.get(
          SettingBoxKey.orientationLockEnabled,
          defaultValue: false,
        )) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0x45000000),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: IconButton(
        tooltip: '方向锁定',
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        onPressed: () => _selectMode(context),
        icon: const Icon(
          Icons.screen_rotation_outlined,
          size: 20,
          color: Colors.white,
        ),
      ),
    );
  }
}
