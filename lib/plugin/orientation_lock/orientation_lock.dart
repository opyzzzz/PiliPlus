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

class OrientationLockButton extends StatefulWidget {
  const OrientationLockButton({required this.showControls, super.key});

  final bool showControls;

  @override
  State<OrientationLockButton> createState() => _OrientationLockButtonState();
}

class _OrientationLockButtonState extends State<OrientationLockButton> {
  static const _modes = <({String value, String label, IconData icon})>[
    (value: 'default', label: '默认', icon: Icons.screen_rotation_outlined),
    (value: 'portrait', label: '竖屏', icon: Icons.stay_current_portrait),
    (value: 'landscape', label: '横屏', icon: Icons.stay_current_landscape),
    (value: 'reverseLandscape', label: '反向横屏', icon: Icons.screen_rotation),
  ];

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _menuEntry;

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

  void _closeMenu() {
    final entry = _menuEntry;
    if (entry == null) return;
    _menuEntry = null;
    entry.remove();
    entry.dispose();
  }

  void _toggleMenu() {
    if (_menuEntry != null) {
      _closeMenu();
      return;
    }

    final layout = GStorage.setting.get(
      SettingBoxKey.orientationLockMenuLayout,
      defaultValue: 0,
    );
    final selectedMode = GStorage.setting.get(
      SettingBoxKey.orientationLockMode,
      defaultValue: 'default',
    );
    final colorScheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context, rootOverlay: true);

    _menuEntry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8),
            child: Material(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: layout == 0
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final mode in _modes)
                              _buildHorizontalItem(
                                mode,
                                selectedMode,
                                colorScheme,
                              ),
                          ],
                        ),
                      ),
                    )
                  : SizedBox(
                      width: 156,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final mode in _modes)
                            _buildVerticalItem(
                              mode,
                              selectedMode,
                              colorScheme,
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_menuEntry!);
  }

  Widget _buildHorizontalItem(
    ({String value, String label, IconData icon}) mode,
    String selectedMode,
    ColorScheme colorScheme,
  ) {
    final selected = mode.value == selectedMode;
    return InkWell(
      onTap: () {
        _closeMenu();
        _applyMode(mode.value);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode.icon,
              size: 18,
              color: selected ? colorScheme.secondary : Colors.white,
            ),
            const SizedBox(height: 4),
            Text(
              mode.label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? colorScheme.secondary : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalItem(
    ({String value, String label, IconData icon}) mode,
    String selectedMode,
    ColorScheme colorScheme,
  ) {
    final selected = mode.value == selectedMode;
    return InkWell(
      onTap: () {
        _closeMenu();
        _applyMode(mode.value);
      },
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                mode.icon,
                size: 18,
                color: selected ? colorScheme.secondary : Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? colorScheme.secondary : Colors.white,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check, size: 16, color: colorScheme.secondary),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid ||
        !widget.showControls ||
        !GStorage.setting.get(
          SettingBoxKey.orientationLockEnabled,
          defaultValue: false,
        )) {
      return const SizedBox.shrink();
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0x45000000),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        child: IconButton(
          tooltip: '方向锁定',
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          onPressed: _toggleMenu,
          icon: const Icon(
            Icons.screen_rotation_outlined,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
