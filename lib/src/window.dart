import 'dart:async';

import 'models.dart';
import '../multi_screen_presentation_platform_interface.dart';

/// Représente une fenêtre de présentation ouverte sur un écran.
///
/// Fournit :
///  - l'envoi de données vers la fenêtre (sendData)
///  - la réception de données/évènements venant de cette fenêtre précise
///  - le contrôle du mode (floating / fullscreen), y compris en réponse
///    au double-clic natif (onModeChanged)
class Window {
  final String id;
  final String screenId;

  final MultiScreenPresentationPlatform _platform;
  final StreamController<WindowModeEvent> _modeController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _dataController =
      StreamController.broadcast();
  final StreamController<void> _closedController = StreamController.broadcast();

  StreamSubscription<Map<String, dynamic>>? _rawSub;
  WindowMode _mode;
  bool _closed = false;

  Window._(
    this.id,
    this.screenId,
    this._platform,
    WindowMode initialMode,
  ) : _mode = initialMode {
    _rawSub = _platform.rawEvents.listen(_onRawEvent);
  }

  /// Usage interne : construit et branche l'écoute d'évènements pour cette
  /// fenêtre. Voir [MultiScreenPresentation.openWindow].
  static Window attach({
    required String id,
    required String screenId,
    required MultiScreenPresentationPlatform platform,
    required WindowMode initialMode,
  }) {
    return Window._(id, screenId, platform, initialMode);
  }

  WindowMode get mode => _mode;
  bool get isClosed => _closed;

  /// Émis à chaque fois que le mode bascule (typiquement double-clic natif :
  /// floating -> fullscreen -> floating ...).
  Stream<WindowModeEvent> get onModeChanged => _modeController.stream;

  /// Émis quand la fenêtre secondaire renvoie des données vers l'app
  /// principale (ex: la présentation notifie "slide suivante demandée").
  Stream<Map<String, dynamic>> get onData => _dataController.stream;

  /// Émis quand la fenêtre a été fermée (natif ou utilisateur).
  Stream<void> get onClosed => _closedController.stream;

  void _onRawEvent(Map<String, dynamic> event) {
    if (event['windowId'] != id) return;
    switch (event['type']) {
      case 'modeChanged':
        final e = WindowModeEvent.fromMap(event);
        _mode = e.mode;
        _modeController.add(e);
        break;
      case 'data':
        _dataController.add(
          Map<String, dynamic>.from(event['data'] as Map? ?? {}),
        );
        break;
      case 'closed':
        _closed = true;
        _closedController.add(null);
        dispose();
        break;
    }
  }

  /// Envoie des données (JSON-compatibles) affichables dans la fenêtre.
  Future<void> sendData(Map<String, dynamic> data) {
    return _platform.sendData(id, data);
  }

  /// Force le passage en plein écran (sur l'écran où se trouve
  /// actuellement la fenêtre, pas forcément [screenId] d'origine si
  /// l'utilisateur l'a déplacée entre-temps).
  Future<void> enterFullscreen() =>
      _platform.setWindowMode(id, WindowMode.fullscreen);

  /// Repasse en fenêtre flottante déplaçable.
  Future<void> enterFloating() =>
      _platform.setWindowMode(id, WindowMode.floating);

  /// Alias de [setFullscreen].
  Future<void> setFullScreen(bool enabled) => setFullscreen(enabled);

  /// Met à jour le mode plein écran.
  Future<void> setFullscreen(bool enabled) =>
      _platform.setWindowFullscreen(id, enabled);

  /// Déplace la fenêtre vers la position donnée.
  Future<void> setPosition(int x, int y) =>
      _platform.setWindowPosition(id, x, y);

  /// Alias court pour [setPosition].
  Future<void> setPos(int x, int y) => setPosition(x, y);

  /// Redimensionne la fenêtre.
  Future<void> setSize(int width, int height) =>
      _platform.setWindowSize(id, width, height);

  /// Définit une taille et une position en une seule opération.
  Future<void> setBounds({
    required int x,
    required int y,
    required int width,
    required int height,
  }) =>
      _platform.setWindowBounds(
        id,
        x: x,
        y: y,
        width: width,
        height: height,
      );

  /// Modifie l'opacité de la fenêtre.
  Future<void> setOpacity(double opacity) =>
      _platform.setWindowOpacity(id, opacity.clamp(0.0, 1.0));

  /// Garde la fenêtre au-dessus des autres.
  Future<void> setAlwaysOnTop(bool alwaysOnTop) =>
      _platform.setWindowAlwaysOnTop(id, alwaysOnTop);

  /// Active ou désactive la redimension de la fenêtre.
  Future<void> setResizable(bool resizable) =>
      _platform.setWindowResizable(id, resizable);

  /// Affiche la fenêtre.
  Future<void> show() => _platform.setWindowVisible(id, true);

  /// Masque la fenêtre.
  Future<void> hide() => _platform.setWindowVisible(id, false);

  /// Change le titre de la fenêtre.
  Future<void> setTitle(String title) => _platform.setWindowTitle(id, title);

  /// Fournit une icône optionnelle pour la fenêtre.
  Future<void> setIconPath(String? iconPath) =>
      _platform.setWindowIcon(id, iconPath);

  /// Applique un lot d'options initiales à la fenêtre.
  Future<void> applyOptions(WindowOptions options) async {
    if (options.position != null) {
      await setPosition(options.position!.x, options.position!.y);
    }
    if (options.size != null) {
      await setSize(options.size!.width, options.size!.height);
    }
    if (options.opacity != null) {
      await setOpacity(options.opacity!);
    }
    if (options.alwaysOnTop != null) {
      await setAlwaysOnTop(options.alwaysOnTop!);
    }
    if (options.resizable != null) {
      await setResizable(options.resizable!);
    }
    if (!options.visible) {
      await hide();
    }
    if (options.title.isNotEmpty) {
      await setTitle(options.title);
    }
    if (options.iconPath != null) {
      await setIconPath(options.iconPath);
    }
  }

  /// Simule/force le même comportement que le double-clic utilisateur.
  Future<void> toggleMode() => _platform.toggleWindowMode(id);

  Future<void> close() async {
    await _platform.closeWindow(id);
    _closed = true;
  }

  void dispose() {
    _rawSub?.cancel();
    _modeController.close();
    _dataController.close();
    _closedController.close();
  }
}
