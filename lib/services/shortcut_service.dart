import 'dart:io' show Platform;

import 'package:PiliPlus/plugin/pl_player/models/shortcut_action.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyUpEvent,
        LogicalKeyboardKey;

/// 播放器快捷键：自定义绑定的存取、按键匹配与跨平台显示。
///
/// 自定义数据存于 setting box（`Pref.customKeyBindings`）：
/// `{ actionName: bindingJson }`，值为 `'none'` 表示该动作已清除绑定。
abstract final class ShortcutService {
  static final bool _isMac = Platform.isMacOS;

  static final Set<LogicalKeyboardKey> _modifierKeys = {
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  static bool isModifier(LogicalKeyboardKey key) => _modifierKeys.contains(key);

  /// 当前生效的绑定：自定义优先，否则用默认值（已清除的动作为 null）
  static KeyBinding? bindingOf(ShortcutAction action) {
    final custom = Pref.customKeyBindings[action.name];
    if (custom == null) return action.defaultBinding;
    if (custom == 'none') return null;
    return KeyBinding.fromJson(custom) ?? action.defaultBinding;
  }

  static bool isCustomized(ShortcutAction action) =>
      Pref.customKeyBindings.containsKey(action.name);

  /// 按当前按下的键（含修饰键）匹配动作；未绑定或无匹配返回 null
  static ShortcutAction? matchAction(KeyEvent event, {required bool isLive}) {
    final binding = currentBinding(event.logicalKey);
    for (final action in ShortcutAction.values) {
      if (!action.context.applies(isLive)) continue;
      if (action.desktopOnly && !PlatformUtils.isDesktop) continue;
      if (bindingOf(action) == binding) return action;
    }
    return null;
  }


  static const List<String> comboIds = ['A', 'B', 'C'];
  static final Map<String, int> _comboIndexes = {};
  static final Map<String, List<String>> _comboSnapshots = {};
  static final Set<LogicalKeyboardKey> _activeComboKeys = {};

  static String _comboBindingKey(String id) => 'combo$id.binding';
  static String _comboActionsKey(String id) => 'combo$id.actions';

  /// 组合快捷键默认未绑定；动作序列与触发键分别持久化。
  static KeyBinding? comboBindingOf(String id) {
    if (!comboIds.contains(id)) return null;
    final raw = Pref.customKeyBindings[_comboBindingKey(id)];
    if (raw == null || raw == 'none') return null;
    return KeyBinding.fromJson(raw);
  }

  static List<ShortcutAction> comboActionsOf(String id) {
    if (!comboIds.contains(id)) return const [];
    final raw = Pref.customKeyBindings[_comboActionsKey(id)];
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((name) {
          for (final action in ShortcutAction.values) {
            if (action.name == name) return action;
          }
          return null;
        })
        .whereType<ShortcutAction>()
        .where((action) => !action.isHold)
        .toList(growable: false);
  }

  static void setComboBinding(String id, KeyBinding? binding) {
    if (!comboIds.contains(id)) return;
    final map = Pref.customKeyBindings;
    map[_comboBindingKey(id)] = binding?.toJson() ?? 'none';
    Pref.customKeyBindings = map;
  }

  static void setComboActions(String id, List<ShortcutAction> actions) {
    if (!comboIds.contains(id)) return;
    final map = Pref.customKeyBindings;
    map[_comboActionsKey(id)] = actions
        .where((action) => !action.isHold)
        .map((action) => action.name)
        .toList(growable: false);
    _comboIndexes.remove(id);
    _comboSnapshots.remove(id);
    Pref.customKeyBindings = map;
  }

  /// 吞掉组合快捷键的重复与释放事件，防止修饰键在按住主键期间松开后，
  /// 同一个按键的 KeyRepeat/KeyUp 被普通快捷键再次匹配。
  static bool consumeComboContinuation(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Flutter 用 KeyRepeatEvent 表示长按重复；若窗口失焦导致上次 KeyUp 丢失，
      // 新的 KeyDown 应视为下一次独立敲击，而不是沿用旧状态。
      _activeComboKeys.remove(event.logicalKey);
      return false;
    }
    if (!_activeComboKeys.contains(event.logicalKey)) return false;
    if (event is KeyUpEvent) _activeComboKeys.remove(event.logicalKey);
    return true;
  }

  /// 返回匹配的组合 ID；只由 KeyDown 事件调用，并记录该次按键的生命周期。
  static String? matchCombo(KeyEvent event) {
    if (event is! KeyDownEvent) return null;
    final binding = currentBinding(event.logicalKey);
    for (final id in comboIds) {
      if (comboBindingOf(id) == binding) {
        _activeComboKeys.add(event.logicalKey);
        return id;
      }
    }
    return null;
  }

  /// Meta+Q / Meta+R 被播放器保留，不能作为自定义快捷键。
  static String? reservedBindingConflict(KeyBinding binding) {
    if (!binding.meta) return null;
    if (binding.key == LogicalKeyboardKey.keyQ) {
      return Platform.isMacOS
          ? '系统保留快捷键（Cmd+Q 退出应用）'
          : '系统保留快捷键（Meta+Q）';
    }
    if (binding.key == LogicalKeyboardKey.keyR) {
      return '系统保留快捷键（Meta+R）';
    }
    return null;
  }

  /// 组合键按顺序循环执行。索引只保存在内存；动作列表变化时自动归零。
  static ShortcutAction? nextComboAction(String id, {required bool isLive}) {
    final actions = comboActionsOf(id);
    if (actions.isEmpty) {
      _comboIndexes[id] = 0;
      _comboSnapshots[id] = const [];
      return null;
    }
    final snapshot = actions.map((action) => action.name).toList(growable: false);
    if (!_sameNames(_comboSnapshots[id], snapshot)) {
      _comboSnapshots[id] = snapshot;
      _comboIndexes[id] = 0;
    }
    var index = _comboIndexes[id] ?? 0;
    for (var checked = 0; checked < actions.length; checked++) {
      final action = actions[index % actions.length];
      index = (index + 1) % actions.length;
      if (!action.context.applies(isLive)) continue;
      if (action.desktopOnly && !PlatformUtils.isDesktop) continue;
      _comboIndexes[id] = index;
      return action;
    }
    _comboIndexes[id] = index;
    return null;
  }

  static bool _sameNames(List<String>? a, List<String> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 组合绑定不能与普通快捷键或其他组合绑定重叠。
  static String? comboBindingConflictOf(String id, KeyBinding binding) {
    final reserved = reservedBindingConflict(binding);
    if (reserved != null) return reserved;
    for (final action in ShortcutAction.values) {
      if (action.desktopOnly && !PlatformUtils.isDesktop) continue;
      if (bindingOf(action) == binding) return action.title;
    }
    for (final otherId in comboIds) {
      if (otherId != id && comboBindingOf(otherId) == binding) {
        return '组合 $otherId';
      }
    }
    return null;
  }

  static String? bindingConflictWithCombo(
    ShortcutAction action,
    KeyBinding binding,
  ) {
    for (final id in comboIds) {
      if (comboBindingOf(id) == binding) return '组合 $id';
    }
    return null;
  }

  static KeyBinding currentBinding(LogicalKeyboardKey key) {
    final hw = HardwareKeyboard.instance;
    return KeyBinding(
      key,
      shift: hw.isShiftPressed,
      ctrl: hw.isControlPressed,
      alt: hw.isAltPressed,
      meta: hw.isMetaPressed,
    );
  }

  /// 检测绑定冲突：同上下文（且同平台可见）的其他动作已占用该键位时返回对方
  static ShortcutAction? conflictOf(ShortcutAction action, KeyBinding binding) {
    for (final other in ShortcutAction.values) {
      if (other == action) continue;
      if (!action.context.overlaps(other.context)) continue;
      if (other.desktopOnly && !PlatformUtils.isDesktop) continue;
      if (bindingOf(other) == binding) return other;
    }
    return null;
  }

  /// 保存自定义绑定；与默认一致时直接移除自定义记录
  static void setBinding(ShortcutAction action, KeyBinding binding) {
    final map = Pref.customKeyBindings;
    if (binding == action.defaultBinding) {
      map.remove(action.name);
    } else {
      map[action.name] = binding.toJson();
    }
    Pref.customKeyBindings = map;
  }

  /// 清除绑定（该动作将不再响应任何按键）
  static void clearBinding(ShortcutAction action) {
    final map = Pref.customKeyBindings;
    map[action.name] = 'none';
    Pref.customKeyBindings = map;
  }

  /// 恢复单个动作的默认绑定
  static void resetBinding(ShortcutAction action) {
    final map = Pref.customKeyBindings..remove(action.name);
    Pref.customKeyBindings = map;
  }

  /// 将全部快捷键触发键设为未绑定，保留组合动作序列。
  static void resetAll() {
    final map = Pref.customKeyBindings;
    for (final action in ShortcutAction.values) {
      map[action.name] = 'none';
    }
    for (final id in comboIds) {
      map[_comboBindingKey(id)] = 'none';
    }
    Pref.customKeyBindings = map;
    _comboIndexes.clear();
    _comboSnapshots.clear();
    _activeComboKeys.clear();
  }

  // ── 显示 ────────────────────────────────────────────────────────────────

  /// 当前按住的修饰键（用于按键捕获的实时预览），无修饰键时返回空串
  static String currentModifiersLabel() {
    final hw = HardwareKeyboard.instance;
    final parts = <String>[];
    if (_isMac) {
      if (hw.isControlPressed) parts.add('⌃');
      if (hw.isAltPressed) parts.add('⌥');
      if (hw.isShiftPressed) parts.add('⇧');
      if (hw.isMetaPressed) parts.add('⌘');
      return parts.join();
    }
    if (hw.isControlPressed) parts.add('Ctrl');
    if (hw.isAltPressed) parts.add('Alt');
    if (hw.isShiftPressed) parts.add('Shift');
    if (hw.isMetaPressed) parts.add(Platform.isLinux ? 'Super' : 'Win');
    return parts.join(' + ');
  }

  static String formatBinding(KeyBinding? binding) {
    if (binding == null) return '未绑定';
    final parts = <String>[];
    if (_isMac) {
      if (binding.ctrl) parts.add('⌃');
      if (binding.alt) parts.add('⌥');
      if (binding.shift) parts.add('⇧');
      if (binding.meta) parts.add('⌘');
      parts.add(keyLabel(binding.key));
      return parts.join();
    }
    if (binding.ctrl) parts.add('Ctrl');
    if (binding.alt) parts.add('Alt');
    if (binding.shift) parts.add('Shift');
    if (binding.meta) parts.add(Platform.isLinux ? 'Super' : 'Win');
    parts.add(keyLabel(binding.key));
    return parts.join(' + ');
  }

  static final Map<LogicalKeyboardKey, String> _keyLabels = {
    LogicalKeyboardKey.space: '空格',
    LogicalKeyboardKey.enter: '回车',
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
    LogicalKeyboardKey.bracketLeft: '[',
    LogicalKeyboardKey.bracketRight: ']',
    LogicalKeyboardKey.backspace: '退格',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.insert: 'Insert',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'PgUp',
    LogicalKeyboardKey.pageDown: 'PgDn',
    LogicalKeyboardKey.mediaPlayPause: '播放/暂停',
    LogicalKeyboardKey.mediaTrackNext: '下一曲',
    LogicalKeyboardKey.mediaTrackPrevious: '上一曲',
  };

  static String keyLabel(LogicalKeyboardKey key) {
    final label = _keyLabels[key];
    if (label != null) return label;
    final l = key.keyLabel;
    return l.length == 1 ? l.toUpperCase() : l;
  }
}
