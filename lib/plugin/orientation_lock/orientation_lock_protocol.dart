/// Names shared by the Dart and Android sides of the orientation-lock
/// MethodChannel. Keep the matching constants in MainActivity in sync.
abstract final class OrientationLockProtocol {
  static const channelName = 'com.example.piliplus/orientation_lock';
  static const requestOverlayPermission = 'requestOverlayPermission';
  static const setOrientation = 'setOrientation';
  static const modeArgument = 'mode';
}
