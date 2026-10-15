import 'package:PiliPlus/features/landscape/landscape_feature.dart';
import 'package:PiliPlus/models/common/landscape_mode.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/material.dart' show BoxDecoration, BorderRadius, Color, Colors, DecoratedBox, GestureDetector, Icon, Icons, Radius, SizedBox, Tooltip, Widget, Center, HitTestBehavior;

/// Flutter UI adapters for the landscape feature.
///
/// Keep player controls and settings models here so the feature's policy and
/// preference operations do not depend on presentation-layer types.
abstract final class LandscapeUi {
  static bool get showToggleButton => Pref.showFsLandscapeBtn;

  static Widget buildToggleButton({
    required void Function() onToggle,
    required void Function() onLongPress,
  }) => Tooltip(
    message: '切换横屏方向（长按关闭）',
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0x45000000),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        onLongPress: onLongPress,
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(
              Icons.screen_rotation_outlined,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ),
  );

  static PopupModel<LandscapeMode> buildModeSetting({
    required void Function() applyMode,
  }) => PopupModel(
    title: '横屏模式',
    leading: const Icon(Icons.screen_rotation_outlined),
    value: () => Pref.landscapeMode,
    items: LandscapeMode.values,
    onSelected: (value, setState) async {
      await LandscapeFeature.setMode(value);
      applyMode();
      setState();
    },
  );

  static SwitchModel buildShowToggleSetting() => const SwitchModel(
    title: '全屏显示横屏切换按钮',
    leading: Icon(Icons.screen_rotation_outlined),
    setKey: SettingBoxKey.showFsLandscapeBtn,
    defaultVal: true,
  );
}
