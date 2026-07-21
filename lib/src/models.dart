/// Mode d'affichage courant de la fenêtre de présentation.
enum WindowMode {
  /// Fenêtre normale, déplaçable/redimensionnable par l'utilisateur.
  floating,

  /// Fenêtre en plein écran sur l'écran où elle se trouve actuellement.
  fullscreen,
}

/// Position initiale d'une fenêtre.
class WindowPosition {
  final int x;
  final int y;

  const WindowPosition({required this.x, required this.y});
}

/// Taille initiale d'une fenêtre.
class WindowSize {
  final int width;
  final int height;

  const WindowSize({required this.width, required this.height});
}

/// Mode de contenu envoyé sur la fenêtre secondaire.
enum PresentationContentMode {
  /// La fenêtre native lance directement un moteur Flutter avec un
  /// entrypoint dédié (ex: `presentationMain`) : "mise en présentation directe".
  liveFlutterEngine,

  /// La fenêtre native est créée "vide" (juste un conteneur natif) et
  /// attend explicitement que l'app envoie des données à afficher via
  /// [PresentationWindow.sendData]. Utile si on veut choisir plus tard,
  /// ou piloter un rendu 100% natif au lieu de Flutter.
  manual,
}

/// Évènement émis quand le mode de la fenêtre change (double-clic).
class WindowModeEvent {
  final String windowId;
  final WindowMode mode;
  final String screenId;

  const WindowModeEvent({
    required this.windowId,
    required this.mode,
    required this.screenId,
  });

  factory WindowModeEvent.fromMap(Map<dynamic, dynamic> map) {
    return WindowModeEvent(
      windowId: map['windowId'].toString(),
      mode: (map['mode'] == 'fullscreen')
          ? WindowMode.fullscreen
          : WindowMode.floating,
      screenId: map['screenId'].toString(),
    );
  }
}

/// Options de création d'une fenêtre de présentation.
class WindowOptions {
  /// Id de l'écran cible (voir [ScreenInfo.id]).
  final String screenId;

  /// Si true, la fenêtre s'ouvre directement en plein écran sur [screenId].
  /// Si false, elle s'ouvre en fenêtre flottante (déplaçable).
  final bool fullscreen;

  /// Contrôle si on lance directement un rendu Flutter ("présentation
  /// directe") ou si on attend un envoi manuel de données.
  final PresentationContentMode contentMode;

  /// Titre de la fenêtre (desktop uniquement).
  final String title;

  /// Position initiale de la fenêtre.
  final WindowPosition? position;

  /// Taille initiale de la fenêtre.
  final WindowSize? size;

  /// Opacité initiale de la fenêtre, entre 0.0 et 1.0.
  final double? opacity;

  /// Si true, la fenêtre reste au-dessus des autres.
  final bool? alwaysOnTop;

  /// Si false, la fenêtre devient non redimensionnable.
  final bool? resizable;

  /// Si false, la fenêtre démarre cachée.
  final bool visible;

  /// Chemin d'une icône optionnelle (.ico, .png, .svg, ...).
  final String? iconPath;

  const WindowOptions({
    required this.screenId,
    this.fullscreen = false,
    this.contentMode = PresentationContentMode.liveFlutterEngine,
    this.title = 'Presentation',
    this.position,
    this.size,
    this.opacity,
    this.alwaysOnTop,
    this.resizable,
    this.visible = true,
    this.iconPath,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'screenId': screenId,
      'startFullscreen': fullscreen,
      'contentMode': contentMode.name,
      'title': title,
      'visible': visible,
    };

    if (position != null) {
      // IMPORTANT: le natif Linux lit ces valeurs avec fl_value_get_float(),
      // qui exige un FL_VALUE_TYPE_FLOAT. Envoyer un int brut ici provoque
      // "assertion 'self->type == FL_VALUE_TYPE_FLOAT' failed" côté GTK et
      // fait retomber x/y à 0.
      map['x'] = position!.x.toDouble();
      map['y'] = position!.y.toDouble();
    }
    if (size != null) {
      // Même remarque que ci-dessus : sans .toDouble(), width/height
      // arrivent à 0 côté natif -> "gtk_window_resize: assertion
      // 'width > 0' failed" et échec de création du contexte OpenGL.
      map['width'] = size!.width.toDouble();
      map['height'] = size!.height.toDouble();
    }
    if (opacity != null) {
      map['opacity'] = opacity;
    }
    if (alwaysOnTop != null) {
      map['alwaysOnTop'] = alwaysOnTop;
    }
    if (resizable != null) {
      map['resizable'] = resizable;
    }
    if (iconPath != null) {
      map['iconPath'] = iconPath;
    }
    return map;
  }
}
