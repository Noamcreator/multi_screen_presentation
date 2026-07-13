import 'dart:io';

import 'package:flutter/material.dart';
import 'package:multi_screen_presentation/multi_screen_presentation.dart';

// =========================================================================
// 1. DEFINITION DES PAGES / SLIDES
// =========================================================================

enum AppRoute {
  accueil,
  presentation,
  statistiques,
}

class SharedPageContent extends StatelessWidget {
  final AppRoute route;

  const SharedPageContent({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    switch (route) {
      case AppRoute.accueil:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.home, size: 80, color: Colors.blue),
              SizedBox(height: 16),
              Text("ÉCRAN D'ACCUEIL", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              Text("Bienvenue dans l'application", style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      case AppRoute.presentation:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.slideshow, size: 80, color: Colors.cyan),
              SizedBox(height: 16),
              Text("PAGE DE PRÉSENTATION", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              Text("Contenu synchronisé instantanément !", style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      case AppRoute.statistiques:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bar_chart, size: 80, color: Colors.green),
              SizedBox(height: 16),
              Text("TABLEAU DE BORD", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              Text("Données et statistiques en direct", style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
    }
  }
}

// =========================================================================
// 2. ENTRYPOINT DE LA FENÊTRE SECONDAIRE / RETOUR
// =========================================================================

@pragma('vm:entry-point')
void presentationMain() {
  runApp(const PresentationApp());
}

class PresentationApp extends StatelessWidget {
  const PresentationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PresentationPage(),
    );
  }
}

class PresentationPage extends StatefulWidget {
  const PresentationPage({super.key});

  @override
  State<PresentationPage> createState() => _PresentationPageState();
}

class _PresentationPageState extends State<PresentationPage> {
  AppRoute _currentRoute = AppRoute.accueil;

  @override
  void initState() {
    super.initState();
    
    // Écoute des données transmises via le Stream natif du package
    WindowManager.onDataReceived.listen((Map<String, dynamic> data) {
      if (data.containsKey('route')) {
        setState(() {
          _currentRoute = AppRoute.values.firstWhere(
            (r) => r.name == data['route'],
            orElse: () => AppRoute.accueil,
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SharedPageContent(route: _currentRoute),
    );
  }
}

// =========================================================================
// 3. APPLICATION PRINCIPALE (LA TÉLÉCOMMANDE)
// =========================================================================

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<ScreenInfo> _screens = [];

  // Une seule fenêtre active par écran pour éviter les doublons
  final Map<String, Window> _activeWindows = {};
  final Map<String, bool> _screenFullscreenChoices = {};

  final TextEditingController _titleController =
      TextEditingController(text: 'Écran de Présentation');
  final TextEditingController _iconPathController = TextEditingController();
  final TextEditingController _xController = TextEditingController(text: '100');
  final TextEditingController _yController = TextEditingController(text: '100');
  final TextEditingController _widthController =
      TextEditingController(text: '1280');
  final TextEditingController _heightController =
      TextEditingController(text: '720');

  Window? _previewWindow;
  AppRoute _activeRoute = AppRoute.accueil;
  double _windowOpacity = 1.0;
  bool _windowAlwaysOnTop = false;
  bool _windowResizable = true;
  bool _windowVisible = true;
  bool _windowFullscreen = false;

  @override
  void initState() {
    super.initState();
    _refreshScreens();
    WindowManager.onScreensChanged.listen((s) => setState(() => _screens = s));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _iconPathController.dispose();
    _xController.dispose();
    _yController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _refreshScreens() async {
    final screens = await WindowManager.getScreens();
    setState(() {
      _screens = screens;
      for (var s in screens) {
        _screenFullscreenChoices.putIfAbsent(s.id, () => false);
      }
    });
  }

  /// Ouvre ou ferme une fenêtre unique de manière exclusive pour cet écran
  /// Ouvre ou ferme une fenêtre unique de manière exclusive pour cet écran
  Future<void> _toggleScreen(ScreenInfo screen) async {
    if (_activeWindows.containsKey(screen.id)) {
      await _activeWindows[screen.id]!.close();
      setState(() {
        _activeWindows.remove(screen.id);
      });
      return;
    }

    final forceFullscreen = _screenFullscreenChoices[screen.id] ?? false;
    final title = _titleController.text.trim().isEmpty
        ? 'Écran de Présentation'
        : _titleController.text.trim();
    final iconPath = _iconPathController.text.trim().isEmpty
        ? null
        : _iconPathController.text.trim();

    Window? window;
    if(forceFullscreen) {
      window = await WindowManager.openWindow(
        WindowOptions(
          screenId: screen.id,
          fullscreen: forceFullscreen,
          contentMode: PresentationContentMode.liveFlutterEngine,
          title: title,
          visible: true,
        ),
      );
    }
    else {
      window = await WindowManager.openWindow(
        WindowOptions(
          screenId: screen.id,
          fullscreen: false,
          contentMode: PresentationContentMode.liveFlutterEngine,
          title: title,
          position: WindowPosition(
            x: int.tryParse(_xController.text) ?? 100,
            y: int.tryParse(_yController.text) ?? 100,
          ),
          size: WindowSize(
            width: int.tryParse(_widthController.text) ?? 1280,
            height: int.tryParse(_heightController.text) ?? 720,
          ),
          opacity: _windowOpacity,
          alwaysOnTop: _windowAlwaysOnTop,
          resizable: _windowResizable,
          visible: _windowVisible,
          iconPath: iconPath,
        ),
      );
    }
      

    window.onClosed.listen((_) {
      setState(() {
        _activeWindows.remove(screen.id);
      });
    });

    setState(() {
      _activeWindows[screen.id] = window!;
    });

    // Augmente le délai à 800ms ou 1 seconde pour tester si c'est un problème de timing natif
    await Future.delayed(const Duration(milliseconds: 800));
    window.sendData({'route': _activeRoute.name});
  }

  /// Active/Désactive la fenêtre de retour physique (Floating sur l'écran principal)
  Future<void> _togglePhysicalPreview() async {
    if(Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (_previewWindow != null) {
        await _previewWindow!.close();
        setState(() {
          _previewWindow = null;
        });
        return;
      }

      final primaryScreen = _screens.firstWhere((s) => s.isPrimary, orElse: () => _screens.first);

      final title = _titleController.text.trim().isEmpty
          ? 'Retour Monitoring'
          : _titleController.text.trim();
      final iconPath = _iconPathController.text.trim().isEmpty
          ? null
          : _iconPathController.text.trim();

      final window = await WindowManager.openWindow(
        WindowOptions(
          screenId: primaryScreen.id,
          fullscreen: false,
          contentMode: PresentationContentMode.liveFlutterEngine,
          title: title,
          position: WindowPosition(
            x: int.tryParse(_xController.text) ?? 100,
            y: int.tryParse(_yController.text) ?? 100,
          ),
          size: WindowSize(
            width: int.tryParse(_widthController.text) ?? 1280,
            height: int.tryParse(_heightController.text) ?? 720,
          ),
          opacity: _windowOpacity,
          alwaysOnTop: _windowAlwaysOnTop,
          resizable: _windowResizable,
          visible: _windowVisible,
          iconPath: iconPath,
        ),
      );

      window.onClosed.listen((_) {
        setState(() {
          _previewWindow = null;
        });
      });

      setState(() {
        _previewWindow = window;
      });

      await Future.delayed(const Duration(milliseconds: 300));
      window.sendData({'route': _activeRoute.name});
    }
  }

  Future<void> _applyCurrentWindowSettingsToAll() async {
    final title = _titleController.text.trim().isEmpty
        ? 'Écran de Présentation'
        : _titleController.text.trim();
    final iconPath = _iconPathController.text.trim().isEmpty
        ? null
        : _iconPathController.text.trim();

    for (final window in <Window?>[
      ..._activeWindows.values,
      _previewWindow,
    ].whereType<Window>()) {
      await window.setTitle(title);
      await window.setPosition(
        int.tryParse(_xController.text) ?? 100,
        int.tryParse(_yController.text) ?? 100,
      );
      await window.setSize(
        int.tryParse(_widthController.text) ?? 1280,
        int.tryParse(_heightController.text) ?? 720,
      );
      await window.setOpacity(_windowOpacity);
      await window.setAlwaysOnTop(_windowAlwaysOnTop);
      await window.setResizable(_windowResizable);
      if (_windowVisible) {
        await window.show();
      } else {
        await window.hide();
      }
      await window.setFullScreen(_windowFullscreen);
      await window.setIconPath(iconPath);
    }
  }

  void _changeRoute(AppRoute newRoute) {
    setState(() {
      _activeRoute = newRoute;
    });
    _forceSyncAll();
  }

  void _nextRoute() {
    final nextIndex = (_activeRoute.index + 1) % AppRoute.values.length;
    _changeRoute(AppRoute.values[nextIndex]);
  }

  void _forceSyncAll() {
    for (var window in _activeWindows.values) {
      window.sendData({'route': _activeRoute.name});
    }
    if (_previewWindow != null) {
      _previewWindow!.sendData({'route': _activeRoute.name});
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool anyActive = _activeWindows.isNotEmpty || _previewWindow != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Télécommande Multi-Écrans (Stream Intégré)'),
        backgroundColor: Colors.blue.shade100,
      ),
      body: Row(
        children: [
        Material(
          color: Colors.grey.shade100,
          // On utilise un SingleChildScrollView pour permettre le scroll vertical global de la barre
          child: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("1. FENÊTRE DE RETOUR PHYSIQUE", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _previewWindow != null ? Colors.purple : Colors.white,
                      foregroundColor: _previewWindow != null ? Colors.white : Colors.purple,
                    ),
                    onPressed: _togglePhysicalPreview,
                    icon: Icon(_previewWindow != null ? Icons.visibility_off : Icons.visibility),
                    label: Text(_previewWindow != null ? "Fermer le retour" : "Activer la fenêtre de retour"),
                  ),
                  const Divider(height: 30),
                  const Text("2. ÉCRANS EXTERNES", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _refreshScreens,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Actualiser la liste"),
                  ),
                  const SizedBox(height: 8),
            
                  // --- MODIFICATION ICI : On enlève le Expanded et on affiche les éléments directement ---
                  ..._screens.map((s) {
                    if (s.isPrimary) return const SizedBox.shrink();
            
                    final isOpened = _activeWindows.containsKey(s.id);
                    final isFullscreen = _screenFullscreenChoices[s.id] ?? false;
            
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: isOpened ? Colors.blue.shade50 : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text("${s.width.toInt()}x${s.height.toInt()}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Text(isFullscreen ? "Plein Écran Initial" : "Mode Fenêtré (Floating)"),
                                Switch(
                                  value: isFullscreen,
                                  onChanged: isOpened ? null : (val) {
                                    setState(() {
                                      _screenFullscreenChoices[s.id] = val;
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isOpened ? Colors.red : Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _toggleScreen(s),
                                child: Text(isOpened ? "Fermer la fenêtre" : "Lancer sur cet écran"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  // -------------------------------------------------------------------------------------
            
                  const Divider(height: 30),
                  const Text("3. OPTIONS DE FENÊTRE", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titre de la fenêtre',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _iconPathController,
                    decoration: const InputDecoration(
                      labelText: 'Chemin icône optionnel (.ico)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _xController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'X', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _yController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Y', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _widthController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Largeur', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _heightController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Hauteur', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Opacité'),
                      Expanded(
                        child: Slider(
                          value: _windowOpacity,
                          min: 0.1,
                          max: 1.0,
                          divisions: 9,
                          label: _windowOpacity.toStringAsFixed(1),
                          onChanged: (value) => setState(() => _windowOpacity = value),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Toujours au premier plan'),
                    value: _windowAlwaysOnTop,
                    onChanged: (value) => setState(() => _windowAlwaysOnTop = value),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Redimensionnable'),
                    value: _windowResizable,
                    onChanged: (value) => setState(() => _windowResizable = value),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Visible'),
                    value: _windowVisible,
                    onChanged: (value) => setState(() => _windowVisible = value),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Plein écran au démarrage'),
                    value: _windowFullscreen,
                    onChanged: (value) => setState(() => _windowFullscreen = value),
                  ),
                  ElevatedButton.icon(
                    onPressed: _applyCurrentWindowSettingsToAll,
                    icon: const Icon(Icons.window),
                    label: const Text('Appliquer aux fenêtres ouvertes'),
                  ),
                  const Divider(height: 30),
                  const Text("4. PILOTAGE DU CONTENU", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: anyActive ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: anyActive ? _nextRoute : null,
                    icon: const Icon(Icons.skip_next),
                    label: const Text("SLIDE SUIVANTE", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: AppRoute.values.map((route) {
                      final isSelected = _activeRoute == route;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSelected ? Colors.blue : Colors.white,
                              foregroundColor: isSelected ? Colors.white : Colors.black87,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                            ),
                            onPressed: () => _changeRoute(route),
                            child: Text(route.name.substring(0, 3).toUpperCase(), style: const TextStyle(fontSize: 11)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}