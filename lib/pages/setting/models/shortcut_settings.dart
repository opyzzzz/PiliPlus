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

final List<SettingsModel> shortcutSettings = [
  const NormalModel(
    leading: Icon(Icons.restart_alt_outlined),
    title: '恢复全部默认',
    subtitle: '将所有快捷键设为未绑定，保留组合动作列表',
    onTap: _resetAll,
  ),
  const SwitchModel(
    title: '允许音量键及媒体控制键作为快捷键',
    subtitle: '开启后可绑定系统音量键、播放/暂停及上一曲/下一曲；关闭时旧绑定也不会触发自定义动作',
    leading: Icon(Icons.volume_up_outlined),
    setKey: SettingBoxKey.allowMediaKeyShortcuts,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '启用键盘控制',
    subtitle: '在播放页启用键盘快捷键',
    leading: Icon(Icons.keyboard_alt_outlined),
    setKey: SettingBoxKey.keyboardControl,
    defaultVal: true,
  ),
  for (final id in ShortcutService.comboIds)
    NormalModel(
      leading: const Icon(Icons.keyboard_outlined),
      title: '组合快捷键 $id',
      getSubtitle: () => _comboLabel(id),
      onTap: (context, setState) => _showComboDialog(context, id, setState),
    ),
  for (final action in ShortcutAction.values)
    if (!action.desktopOnly || PlatformUtils.isDesktop)
      NormalModel(
        leading: const Icon(Icons.keyboard_outlined),
        title: action.title,
        getSubtitle: () => _bindingLabel(action),
        onTap: (context, setState) {
          _showCaptureDialog(context, action, setState);
        },
      ),
];

String _comboLabel(String id) {
  final binding = ShortcutService.formatBinding(
    ShortcutService.comboBindingOf(id),
  );
  final actions = ShortcutService.comboActionsOf(id)
      .map((action) => action.title)
      .join(' → ');
  return '$binding · ${actions.isEmpty ? '未设置动作' : actions}';
}

Future<void> _showComboDialog(
  BuildContext context,
  String id,
  VoidCallback setState,
) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (context) => _ComboDialog(id: id),
  );
  if (changed == true) setState();
}

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
      content: const Text('将所有普通快捷键和组合快捷键的触发键设为未绑定；组合动作列表会保留。确定继续吗？'),
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
            SmartDialog.showToast('全部快捷键已设为未绑定');
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
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
    final binding = ShortcutService.currentBinding(key);
    if (!ShortcutService.isRestrictedBindingAllowed(binding)) {
      setState(() => _error = '音量键及媒体控制键默认禁用，请先开启设置页中的允许选项');
      return KeyEventResult.handled;
    }
    final reservedConflict = ShortcutService.reservedBindingConflict(binding);
    if (reservedConflict != null) {
      setState(() => _error = reservedConflict);
      return KeyEventResult.handled;
    }
    final conflict = ShortcutService.conflictOf(widget.action, binding);
    final comboConflict = ShortcutService.bindingConflictWithCombo(
      widget.action,
      binding,
    );
    if (conflict != null || comboConflict != null) {
      setState(() => _error =
          '与「${conflict?.title ?? comboConflict}」冲突，请换一个键');
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
            'Esc 也可作为绑定键；取消请点击“取消”。直播与普通视频的快捷键相互独立，可共用同一键位',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}


class _ComboDialog extends StatefulWidget {
  const _ComboDialog({required this.id});
  final String id;
  @override
  State<_ComboDialog> createState() => _ComboDialogState();
}

class _ComboDialogState extends State<_ComboDialog> {
  late List<ShortcutAction> _actions;
  late KeyBinding? _binding;
  ShortcutAction? _selected;
  String? _error;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _actions = ShortcutService.comboActionsOf(widget.id).toList();
    _binding = ShortcutService.comboBindingOf(widget.id);
    _selected = ShortcutAction.values.firstWhere(
      (action) => !action.isHold,
      orElse: () => ShortcutAction.playPause,
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (ShortcutService.isModifier(event.logicalKey)) {
      if (event is KeyDownEvent || event is KeyUpEvent) setState(() {});
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final binding = ShortcutService.currentBinding(event.logicalKey);
    if (!ShortcutService.isRestrictedBindingAllowed(binding)) {
      setState(() => _error = '音量键及媒体控制键默认禁用，请先开启设置页中的允许选项');
      return KeyEventResult.handled;
    }
    final conflict = ShortcutService.comboBindingConflictOf(widget.id, binding);
    if (conflict != null) {
      setState(() => _error = '与「$conflict」冲突，请换一个键');
      return KeyEventResult.handled;
    }
    setState(() {
      _binding = binding;
      _capturing = false;
      _error = null;
    });
    return KeyEventResult.handled;
  }

  void _save() {
    ShortcutService.setComboBinding(widget.id, _binding);
    ShortcutService.setComboActions(widget.id, _actions);
    Get.back(result: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final binding = ShortcutService.formatBinding(_binding);
    final candidates = ShortcutAction.values
        .where((action) => !action.isHold)
        .where((action) => !action.desktopOnly || PlatformUtils.isDesktop)
        .toList(growable: false);
    return AlertDialog(
      constraints: Style.dialogFixedConstraints,
      title: Text('组合快捷键 ${widget.id}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('触发键：$binding'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() {
                _capturing = !_capturing;
                _error = null;
              }),
              child: Text(_capturing ? '停止录入' : '设置触发键'),
            ),
            if (_capturing)
              Focus(
                autofocus: true,
                onKeyEvent: _onKeyEvent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '按下 Esc 或返回键也可作为触发键；当前修饰键：${ShortcutService.currentModifiersLabel()}',
                  ),
                ),
              ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const Divider(),
            const Text('按顺序循环执行（不支持长按型动作）'),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<ShortcutAction>(
                    isExpanded: true,
                    value: _selected,
                    items: candidates
                        .map((action) => DropdownMenuItem<ShortcutAction>(
                              value: action,
                              child: Text(action.title, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(growable: false),
                    onChanged: (action) => setState(() => _selected = action),
                  ),
                ),
                IconButton(
                  tooltip: '添加动作',
                  onPressed: _selected == null
                      ? null
                      : () => setState(() => _actions.add(_selected!)),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_actions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('尚未添加动作；此组合键不会执行任何操作。'),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _actions.length,
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${index + 1}. ${_actions[index].title}'),
                    leading: IconButton(
                      tooltip: '上移',
                      onPressed: index == 0 ? null : () => setState(() {
                        final item = _actions.removeAt(index);
                        _actions.insert(index - 1, item);
                      }),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '下移',
                          onPressed: index == _actions.length - 1 ? null : () => setState(() {
                            final item = _actions.removeAt(index);
                            _actions.insert(index + 1, item);
                          }),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        IconButton(
                          tooltip: '删除动作',
                          onPressed: () => setState(() => _actions.removeAt(index)),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _binding = null),
          child: const Text('清除触发键'),
        ),
        TextButton(onPressed: Get.back, child: const Text('取消')),
        TextButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
