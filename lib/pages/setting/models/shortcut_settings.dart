import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/plugin/pl_player/models/shortcut_action.dart';
import 'package:PiliPlus/services/shortcut_service.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyUpEvent, LogicalKeyboardKey;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

const List<ShortcutAction> _shortcutActionsInDisplayOrder = [
  // 播放控制
  ShortcutAction.playPause,
  ShortcutAction.mute,
  ShortcutAction.refreshStream,
  // 音量与进度
  ShortcutAction.volumeUp,
  ShortcutAction.volumeDown,
  ShortcutAction.seekBackward,
  ShortcutAction.seekForward,
  // 倍速与选集
  ShortcutAction.speedDown,
  ShortcutAction.speedUp,
  ShortcutAction.speedReset,
  ShortcutAction.prevEpisode,
  ShortcutAction.nextEpisode,
  // 画面显示与横屏模式
  ShortcutAction.fullscreen,
  ShortcutAction.inAppFullscreen,
  ShortcutAction.landscapeDisable,
  ShortcutAction.landscapeForward,
  ShortcutAction.landscapeReverse,
  ShortcutAction.desktopPip,
  ShortcutAction.screenshot,
  ShortcutAction.lockControls,
  // 弹幕
  ShortcutAction.toggleDanmaku,
  ShortcutAction.sendDanmaku,
  // 互动
  ShortcutAction.likeTriple,
  ShortcutAction.coin,
  ShortcutAction.fav,
  ShortcutAction.watchLater,
  ShortcutAction.relationMod,
  // 循环组合
  ShortcutAction.comboA,
  ShortcutAction.comboB,
  ShortcutAction.comboC,
];

final List<SettingsModel> shortcutSettings = [
  const SwitchModel(
    title: '启用键盘控制',
    subtitle: '在播放页启用键盘快捷键',
    leading: Icon(Icons.keyboard_alt_outlined),
    setKey: SettingBoxKey.keyboardControl,
    defaultVal: true,
  ),
  for (final action in _shortcutActionsInDisplayOrder)
    if (!action.desktopOnly || PlatformUtils.isDesktop)
      NormalModel(
        leading: const Icon(Icons.keyboard_outlined),
        title: action.title,
        getSubtitle: () => _bindingLabel(action),
        onTap: (context, setState) {
          _showCaptureDialog(context, action, setState);
        },
      ),
  for (final combo in const [
    ShortcutAction.comboA,
    ShortcutAction.comboB,
    ShortcutAction.comboC,
  ])
    NormalModel(
      leading: const Icon(Icons.playlist_play_outlined),
      title: '配置${combo.title}动作',
      getSubtitle: () {
        final actions = ShortcutService.comboActionsOf(combo);
        return actions.isEmpty
            ? '未配置动作，点击设置循环顺序'
            : actions.map((action) => action.title).join(' → ');
      },
      onTap: (context, setState) => _showComboDialog(context, combo, setState),
    ),
  const NormalModel(
    leading: Icon(Icons.restart_alt_outlined),
    title: '恢复全部默认',
    subtitle: '清除全部自定义按键绑定',
    onTap: _resetAll,
  ),
];

String _bindingLabel(ShortcutAction action) {
  final text = ShortcutService.formatBinding(
    ShortcutService.bindingOf(action),
  );
  return ShortcutService.isCustomized(action) ? text : '$text（默认）';
}

Future<void> _showCaptureDialog(
  BuildContext context,
  ShortcutAction action,
  VoidCallback setState,
) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (context) => _CaptureDialog(action: action),
  );
  if (changed == true) {
    setState();
  }
}

void _resetAll(BuildContext context, VoidCallback setState) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      constraints: Style.dialogFixedConstraints,
      title: const Text('恢复全部默认'),
      content: const Text('将清除全部自定义按键绑定，恢复默认键位，确定吗？'),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () {
            ShortcutService.resetAll();
            Get.back();
            setState();
            SmartDialog.showToast('已恢复全部默认');
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

Future<void> _showComboDialog(
  BuildContext context,
  ShortcutAction combo,
  VoidCallback setState,
) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (context) => _ComboActionDialog(combo: combo),
  );
  if (changed == true) setState();
}

class _ComboActionDialog extends StatefulWidget {
  const _ComboActionDialog({required this.combo});
  final ShortcutAction combo;

  @override
  State<_ComboActionDialog> createState() => _ComboActionDialogState();
}

class _ComboActionDialogState extends State<_ComboActionDialog> {
  late final List<ShortcutAction> _actions =
      ShortcutService.comboActionsOf(widget.combo).toList();

  @override
  Widget build(BuildContext context) {
    final available = ShortcutAction.values
        .where((action) =>
            action != ShortcutAction.comboA &&
            action != ShortcutAction.comboB &&
            action != ShortcutAction.comboC &&
            !action.isHold)
        .toList();
    return AlertDialog(
      constraints: Style.dialogFixedConstraints,
      title: Text(widget.combo.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('勾选动作后，可在下方调整执行顺序。'),
              ),
              for (final action in available)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(action.title),
                  value: _actions.contains(action),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _actions.add(action);
                    } else {
                      _actions.remove(action);
                    }
                  }),
                ),
              if (_actions.isNotEmpty) ...[
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('执行顺序'),
                ),
                for (var i = 0; i < _actions.length; i++)
                  ListTile(
                    dense: true,
                    title: Text('${i + 1}. ${_actions[i].title}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '上移',
                          onPressed: i == 0
                              ? null
                              : () => setState(() {
                            final item = _actions.removeAt(i);
                            _actions.insert(i - 1, item);
                          }),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: '下移',
                          onPressed: i == _actions.length - 1
                              ? null
                              : () => setState(() {
                            final item = _actions.removeAt(i);
                            _actions.insert(i + 1, item);
                          }),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('取消')),
        TextButton(
          onPressed: () {
            ShortcutService.setComboActions(widget.combo, _actions);
            Get.back(result: true);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _CaptureDialog extends StatelessWidget {
  const _CaptureDialog({required this.action});

  final ShortcutAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      constraints: Style.dialogFixedConstraints,
      title: Text(action.title),
      content: _CaptureContent(action: action),
      actions: [
        TextButton(
          onPressed: () {
            ShortcutService.resetBinding(action);
            Get.back(result: true);
          },
          child: Text(
            '恢复默认',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: () {
            ShortcutService.clearBinding(action);
            Get.back(result: true);
          },
          child: Text('清除绑定', style: TextStyle(color: theme.colorScheme.error)),
        ),
        TextButton(onPressed: Get.back, child: const Text('取消')),
      ],
    );
  }
}

class _CaptureContent extends StatefulWidget {
  const _CaptureContent({required this.action});

  final ShortcutAction action;

  @override
  State<_CaptureContent> createState() => _CaptureContentState();
}

class _CaptureContentState extends State<_CaptureContent> {
  String? _error;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (ShortcutService.isModifier(key)) {
      // 按住修饰键时实时刷新预览
      if (event is KeyDownEvent || event is KeyUpEvent) {
        setState(() {});
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Get.back();
      return KeyEventResult.handled;
    }
    final binding = ShortcutService.currentBinding(key);
    final conflict = ShortcutService.conflictOf(widget.action, binding);
    if (conflict != null) {
      setState(() => _error = '与「${conflict.title}」冲突，请换一个键');
      return KeyEventResult.handled;
    }
    ShortcutService.setBinding(widget.action, binding);
    SmartDialog.showToast('已保存');
    Get.back(result: true);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modifiers = ShortcutService.currentModifiersLabel();
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前：${ShortcutService.formatBinding(ShortcutService.bindingOf(widget.action))}',
          ),
          const SizedBox(height: 12),
          Text(
            modifiers.isEmpty ? '请按下新的按键组合…' : '$modifiers + …',
            style: theme.textTheme.titleMedium,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 8),
          Text(
            '按 Esc 取消；直播与普通视频的快捷键相互独立，可共用同一键位',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
