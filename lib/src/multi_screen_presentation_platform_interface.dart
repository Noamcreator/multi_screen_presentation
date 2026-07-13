import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models.dart';
import 'multi_screen_presentation_method_channel.dart';
import 'screen_info.dart';

abstract class MultiScreenPresentationPlatform extends PlatformInterface {
  MultiScreenPresentationPlatform() : super(token: _token);

  static final Object _token = Object();

  static MultiScreenPresentationPlatform _instance =
      MethodChannelMultiScreenPresentation();

  static MultiScreenPresentationPlatform get instance => _instance;

  static set instance(MultiScreenPresentationPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<List<ScreenInfo>> getScreens() {
    throw UnimplementedError('getScreens() has not been implemented.');
  }

  Future<String> openWindow(WindowOptions options) {
    throw UnimplementedError('openWindow() has not been implemented.');
  }

  Future<void> closeWindow(String windowId) {
    throw UnimplementedError('closeWindow() has not been implemented.');
  }

  Future<void> toggleWindowMode(String windowId) {
    throw UnimplementedError('toggleWindowMode() has not been implemented.');
  }

  Future<void> setWindowMode(String windowId, WindowMode mode) {
    throw UnimplementedError('setWindowMode() has not been implemented.');
  }

  Future<void> setWindowPosition(String windowId, int x, int y) {
    throw UnimplementedError('setWindowPosition() has not been implemented.');
  }

  Future<void> setWindowSize(String windowId, int width, int height) {
    throw UnimplementedError('setWindowSize() has not been implemented.');
  }

  Future<void> setWindowBounds(
    String windowId, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    throw UnimplementedError('setWindowBounds() has not been implemented.');
  }

  Future<void> setWindowFullscreen(String windowId, bool fullscreen) {
    throw UnimplementedError('setWindowFullscreen() has not been implemented.');
  }

  Future<void> setWindowOpacity(String windowId, double opacity) {
    throw UnimplementedError('setWindowOpacity() has not been implemented.');
  }

  Future<void> setWindowAlwaysOnTop(String windowId, bool alwaysOnTop) {
    throw UnimplementedError(
        'setWindowAlwaysOnTop() has not been implemented.');
  }

  Future<void> setWindowResizable(String windowId, bool resizable) {
    throw UnimplementedError('setWindowResizable() has not been implemented.');
  }

  Future<void> setWindowVisible(String windowId, bool visible) {
    throw UnimplementedError('setWindowVisible() has not been implemented.');
  }

  Future<void> setWindowTitle(String windowId, String title) {
    throw UnimplementedError('setWindowTitle() has not been implemented.');
  }

  Future<void> setWindowIcon(String windowId, String? iconPath) {
    throw UnimplementedError('setWindowIcon() has not been implemented.');
  }

  /// Envoie des données JSON-compatibles depuis l'app principale vers la
  /// fenêtre secondaire (peu importe si celle-ci est en liveFlutterEngine
  /// ou manual).
  Future<void> sendData(String windowId, Map<String, dynamic> data) {
    throw UnimplementedError('sendData() has not been implemented.');
  }

  /// Flux d'évènements génériques venant du natif : changements de mode,
  /// fermeture de fenêtre, changement de liste d'écrans (branchement/
  /// débranchement à chaud), données remontées depuis la fenêtre secondaire.
  Stream<Map<String, dynamic>> get rawEvents {
    throw UnimplementedError('rawEvents has not been implemented.');
  }
}
