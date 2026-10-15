import 'package:flutter/material.dart';

enum OrientationLockMode {
  system('default', '默认', Icons.screen_rotation_outlined),
  portrait('portrait', '竖屏', Icons.stay_current_portrait),
  landscape('landscape', '横屏', Icons.stay_current_landscape),
  reverseLandscape('reverseLandscape', '反向横屏', Icons.screen_rotation);

  const OrientationLockMode(this.wireValue, this.label, this.icon);

  final String wireValue;
  final String label;
  final IconData icon;

  static const valuesForMenu = <OrientationLockMode>[
    system, portrait, landscape, reverseLandscape,
  ];
}
