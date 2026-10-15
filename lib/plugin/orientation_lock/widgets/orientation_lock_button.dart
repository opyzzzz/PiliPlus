import 'dart:io';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../orientation_lock_mode.dart';
import '../orientation_lock_platform.dart';

class OrientationLockButton extends StatefulWidget {
  const OrientationLockButton({required this.showControls, super.key});

  final bool showControls;

  @override
  State<OrientationLockButton> createState() => _OrientationLockButtonState();
}

class _OrientationLockButtonState extends State<OrientationLockButton> {
  static const _modes = OrientationLockMode.valuesForMenu;

  OverlayEntry? _menuEntry;

  Future<void> _applyMode(OrientationLockMode mode) async {
    try {
      if (mode == OrientationLockMode.system) {
        await OrientationLockPlatform.release();
      } else {
        await OrientationLockPlatform.apply(mode);
      }

      // This value represents the user's explicit selection only. Never infer
      // it from the device's current orientation or the player's rotation.
      await GStorage.setting.put(SettingBoxKey.orientationLockMode, mode.wireValue);
      if (mounted && mode != OrientationLockMode.system) {
        SmartDialog.showToast(
          '已请求${mode.label}方向',
        );
      }
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

    final renderObject = context.findRenderObject();
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayObject = overlay.context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        overlayObject is! RenderBox ||
        !overlayObject.hasSize) {
      return;
    }

    final anchorTopLeft = overlayObject.globalToLocal(
      renderObject.localToGlobal(Offset.zero),
    );
    final anchorRect = anchorTopLeft & renderObject.size;
    final screenSize = overlayObject.size;
    final layout = GStorage.setting.get(
      SettingBoxKey.orientationLockMenuLayout,
      defaultValue: 0,
    );
    final selectedMode = GStorage.setting.get(
      SettingBoxKey.orientationLockMode,
      defaultValue: 'default',
    );
    final theme = Theme.of(context);
    final horizontal = layout == 0;
    const edgePadding = 8.0;
    const menuGap = 8.0;
    final menuWidth = horizontal
        ? (screenSize.width - edgePadding * 2)
            .clamp(120.0, 296.0)
            .toDouble()
        : 156.0;
    final menuHeight = horizontal ? 64.0 : 160.0;

    // Both layouts share the button as their anchor and expand to its left.
    // Keep the menu on-screen on narrow devices, even if that requires
    // reducing the available horizontal scrolling viewport.
    final preferredLeft = anchorRect.left - menuWidth - menuGap;
    final left = preferredLeft >= edgePadding
        ? preferredLeft
        : edgePadding;
    final top = horizontal
        ? (anchorRect.center.dy - menuHeight / 2)
            .clamp(edgePadding, screenSize.height - menuHeight - edgePadding)
            .toDouble()
        : anchorRect.top
            .clamp(edgePadding, screenSize.height - menuHeight - edgePadding)
            .toDouble();

    _menuEntry = OverlayEntry(
      builder: (_) => Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeMenu,
              child: const SizedBox.expand(),
            ),
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: Theme(
                data: theme,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: horizontal
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final mode in _modes)
                                _buildHorizontalItem(
                                  mode,
                                  selectedMode,
                                  theme.colorScheme,
                                  menuWidth / _modes.length,
                                ),
                            ],
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final mode in _modes)
                              _buildVerticalItem(mode, selectedMode, theme.colorScheme),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    overlay.insert(_menuEntry!);
  }

  Widget _buildHorizontalItem(
    OrientationLockMode mode,
    String selectedMode,
    ColorScheme colorScheme,
    double itemWidth,
  ) {
    final selected = mode.wireValue == selectedMode;
    return InkWell(
      onTap: () {
        _closeMenu();
        _applyMode(mode);
      },
      child: SizedBox(
        width: itemWidth,
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(mode.icon, size: 18,
                color: selected ? colorScheme.secondary : Colors.white),
              const SizedBox(height: 4),
              Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11,
                  color: selected ? colorScheme.secondary : Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalItem(
    OrientationLockMode mode,
    String selectedMode,
    ColorScheme colorScheme,
  ) {
    final selected = mode.wireValue == selectedMode;
    return InkWell(
      onTap: () {
        _closeMenu();
        _applyMode(mode);
      },
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(mode.icon, size: 18,
                color: selected ? colorScheme.secondary : Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(mode.label, style: TextStyle(fontSize: 13,
                  color: selected ? colorScheme.secondary : Colors.white)),
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
  void didUpdateWidget(covariant OrientationLockButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showControls ||
        !GStorage.setting.get(
          SettingBoxKey.orientationLockEnabled,
          defaultValue: false,
        )) {
      _closeMenu();
    }
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

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0x45000000),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Tooltip(
        message: '方向锁定',
        child: SizedBox(
          width: 34,
          height: 34,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _toggleMenu,
              child: const Center(
                child: Icon(
                  Icons.screen_rotation_outlined,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
