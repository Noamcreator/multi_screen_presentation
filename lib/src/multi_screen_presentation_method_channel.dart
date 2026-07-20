import 'package:flutter/services.dart';

import 'models.dart';
import 'multi_screen_presentation_platform_interface.dart';
import 'screen_info.dart';

/// Implémentation basée sur MethodChannel + EventChannel.
///
/// Convention des canaux (doit correspondre au code natif de chaque
/// plateforme) :
///   - Channel de commandes : "multi_screen_presentation"
///   - Channel d'évènements : "multi_screen_presentation/events"
///
/// Le natif fait le pont entre le moteur Flutter principal et le(s)
/// moteur(s) Flutter secondaire(s) ouverts dans les fenêtres de
/// présentation, sur les canaux "multi_screen_presentation/window/id".
class MethodChannelMultiScreenPresentation
    extends MultiScreenPresentationPlatform {
  final MethodChannel methodChannel =
      const MethodChannel('multi_screen_presentation');

  final EventChannel eventChannel =
      const EventChannel('multi_screen_presentation/events');

  Stream<Map<String, dynamic>>? _rawEventsBroadcast;

  @override
  Future<List<ScreenInfo>> getScreens() async {
    final result =
        await methodChannel.invokeMethod<List<dynamic>>('getScreens') ?? [];
    return result
        .map((e) => ScreenInfo.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<String> openWindow(WindowOptions options) async {
    final id = await methodChannel.invokeMethod<String>(
      'openWindow',
      options.toMap(),
    );
    if (id == null) {
      throw StateError('openWindow a renvoyé un id nul');
    }
    return id;
  }

  @override
  Future<void> closeWindow(String windowId) {
    return methodChannel.invokeMethod('closeWindow', {'windowId': windowId});
  }

  @override
  Future<void> toggleWindowMode(String windowId) {
    return methodChannel
        .invokeMethod('toggleWindowMode', {'windowId': windowId});
  }

  @override
  Future<void> setWindowMode(String windowId, WindowMode mode) {
    return methodChannel.invokeMethod('setWindowMode', {
      'windowId': windowId,
      'mode': mode.name,
    });
  }

  @override
  Future<void> setWindowPosition(String windowId, int x, int y) {
    // NB: le natif Linux fait fl_value_get_float() sur ces valeurs, donc on
    // doit envoyer des double (sinon assertion FL_VALUE_TYPE_FLOAT côté GTK
    // et la position retombe à 0).
    return methodChannel.invokeMethod('setWindowPosition', {
      'windowId': windowId,
      'x': x.toDouble(),
      'y': y.toDouble(),
    });
  }

  @override
  Future<void> setWindowSize(String windowId, int width, int height) {
    // Idem : sans .toDouble(), width/height arrivent à 0 côté natif ->
    // "gtk_window_resize: assertion 'width > 0' failed".
    return methodChannel.invokeMethod('setWindowSize', {
      'windowId': windowId,
      'width': width.toDouble(),
      'height': height.toDouble(),
    });
  }

  @override
  Future<void> setWindowBounds(
    String windowId, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    return methodChannel.invokeMethod('setWindowBounds', {
      'windowId': windowId,
      'x': x.toDouble(),
      'y': y.toDouble(),
      'width': width.toDouble(),
      'height': height.toDouble(),
    });
  }

  @override
  Future<void> setWindowFullscreen(String windowId, bool fullscreen) {
    return methodChannel.invokeMethod('setWindowFullscreen', {
      'windowId': windowId,
      'fullscreen': fullscreen,
    });
  }

  @override
  Future<void> setWindowOpacity(String windowId, double opacity) {
    return methodChannel.invokeMethod('setWindowOpacity', {
      'windowId': windowId,
      'opacity': opacity,
    });
  }

  @override
  Future<void> setWindowAlwaysOnTop(String windowId, bool alwaysOnTop) {
    return methodChannel.invokeMethod('setWindowAlwaysOnTop', {
      'windowId': windowId,
      'alwaysOnTop': alwaysOnTop,
    });
  }

  @override
  Future<void> setWindowResizable(String windowId, bool resizable) {
    return methodChannel.invokeMethod('setWindowResizable', {
      'windowId': windowId,
      'resizable': resizable,
    });
  }

  @override
  Future<void> setWindowVisible(String windowId, bool visible) {
    return methodChannel.invokeMethod('setWindowVisible', {
      'windowId': windowId,
      'visible': visible,
    });
  }

  @override
  Future<void> setWindowTitle(String windowId, String title) {
    return methodChannel.invokeMethod('setWindowTitle', {
      'windowId': windowId,
      'title': title,
    });
  }

  @override
  Future<void> setWindowIcon(String windowId, String? iconPath) {
    return methodChannel.invokeMethod('setWindowIcon', {
      'windowId': windowId,
      'iconPath': iconPath,
    });
  }

  @override
  Future<void> sendData(String windowId, Map<String, dynamic> data) {
    return methodChannel.invokeMethod('sendData', {
      'windowId': windowId,
      'data': data,
    });
  }

  @override
  Stream<Map<String, dynamic>> get rawEvents {
    _rawEventsBroadcast ??= eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _rawEventsBroadcast!;
  }
}