library multi_screen_presentation;

export 'src/models.dart';
export 'src/screen_info.dart';
export 'src/window.dart';

import 'dart:async'; // Ajouté pour le StreamController
import 'package:flutter/services.dart'; // Ajouté pour le MethodChannel
import 'src/models.dart';
import 'src/multi_screen_presentation_platform_interface.dart';
import 'src/window.dart';
import 'src/screen_info.dart';

/// Point d'entrée principal du plugin.
///
/// ```dart
/// final screens = await MultiScreenPresentation.getScreens();
/// final external = screens.firstWhere((s) => !s.isPrimary);
///
/// final window = await MultiScreenPresentation.openWindow(
///   OpenWindowOptions(
///     screenId: external.id,
///     startFullscreen: true,
///     contentMode: PresentationContentMode.liveFlutterEngine,
///     entrypoint: 'presentationMain',
///   ),
/// );
///
/// window.onModeChanged.listen((e) => print('mode -> ${e.mode}'));
/// await window.sendData({'slide': 3, 'title': 'Bonjour'});
/// ```
class WindowManager {
  WindowManager._();

  // Canal utilisé par la deuxième fenêtre et contrôleur de flux pour onDataReceived
  static const MethodChannel _windowChannel =
      MethodChannel('multi_screen_presentation/window');
  static final StreamController<Map<String, dynamic>> _dataStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  static MultiScreenPresentationPlatform get _platform =>
      MultiScreenPresentationPlatform.instance;

  /// Liste des écrans actuellement connectés.
  static Future<List<ScreenInfo>> getScreens() => _platform.getScreens();

  /// Écoute les changements de configuration des écrans (branchement /
  /// débranchement d'un moniteur, résolution AirPlay changée, etc.)
  /// en filtrant le flux d'évènements brut.
  static Stream<List<ScreenInfo>> get onScreensChanged {
    return _platform.rawEvents
        .where((e) => e['type'] == 'screensChanged')
        .asyncMap((_) => getScreens());
  }

  /// Écoute les données envoyées vers la fenêtre secondaire.
  static Stream<Map<String, dynamic>> get onDataReceived {
    _windowChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onData') {
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(call.arguments as Map);
        _dataStreamController.add(data);
      }
      return null;
    });
    return _dataStreamController.stream;
  }

  /// Ouvre une fenêtre de présentation sur l'écran demandé et retourne un
  /// contrôleur [Window] permettant d'envoyer des données et
  /// d'écouter les changements de mode (floating/fullscreen).
  static Future<Window> openWindow(
    WindowOptions options,
  ) async {
    final id = await _platform.openWindow(options);
    final window = Window.attach(
      id: id,
      screenId: options.screenId,
      platform: _platform,
      initialMode:
          options.fullscreen ? WindowMode.fullscreen : WindowMode.floating,
    );
    await window.applyOptions(options);
    return window;
  }
}
