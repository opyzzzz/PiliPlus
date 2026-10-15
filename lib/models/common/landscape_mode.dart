import 'package:PiliPlus/models/common/enum_with_label.dart';

enum LandscapeMode with EnumWithLabel {
  disabled('关闭'),
  landscape('正向横屏'),
  reverseLandscape('反向横屏');

  @override
  final String label;

  const LandscapeMode(this.label);
}
