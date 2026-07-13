# multi_screen_presentation

A comprehensive Flutter plugin to manage a **presentation window on a secondary screen**, featuring a **double-click toggle between floating window ↔ fullscreen**, fine-grained window state customization, and a robust **bidirectional data channel** between the main application and the secondary windows.

## Features

- **Multi-Screen Discovery**: Fetch all connected physical monitors with accurate coordinates, dimensions, scale factors, and primary statuses.
- **Dynamic Window Control**: Manage multiple windows with full mastery over size, position, opacity, visibility, window titles, custom icons, and "always on top" behaviors.
- **Native Interactivity**: Double-clicking on desktop frames automatically toggles between floating and fullscreen presentation layouts relative to their current screen position.
- **Dual Content Modes**: Launch a live secondary Flutter engine context with isolated Dart entrypoints, or drop back to raw manual native containers for lightweight 100% custom processing.
- **Bi-directional Streaming**: Pass serialized JSON payloads back and forth transparently across isolated boundaries within the same physical process structure.

---

## Platform Coverage

| Platform | Multi-window | getScreens() | Implementation Mechanics |
|---|---|---|---|
| **macOS** | ✅ | ✅ | Native `NSWindow` + secondary isolated `FlutterEngine` mapping |
| **iPad** | ✅ (limited) | ✅ | `UIWindow` mapped on an external `UIScreen` context (requires explicit multi-scene setup) |
| **iPhone** | ❌ | ✅ (1 screen) | Secondary windowing is rejected due to strict Operating System constraints |
| **Windows** | ✅ | ✅ | Win32 framework operations (`EnumDisplayMonitors`) + `FlutterViewController` allocations |
| **Linux** | ✅ | ✅ | GTK standard engine utilities (`GdkMonitor`) + dedicated target `FlView` instances |
| **Android** | ✅ (external only)| ✅ | Standard subsystem `Presentation` object routines backed by `DisplayManager` |

---

## Architecture Flow

```
Main Application Context (Flutter Engine #1)
        │  
        ├── MethodChannel ("multi_screen_presentation")
        └── EventChannel  ("multi_screen_presentation/events")
        ▼
   Platform-Specific Native Layer
        │  
        ├── Creates standard OS containers (NSWindow / HWND / GtkWindow / Presentation)
        └── Configures and hooks into target UI layers:
             ├── PresentationContentMode.liveFlutterEngine -> Starts isolated secondary Engine instance
             └── PresentationContentMode.manual             -> Reserves an unpopulated raw native frame
        ▼
Secondary Presentation Window (Flutter Engine #2, Optional context)
        │  
        └── MethodChannel ("multi_screen_presentation/window")
        ▼
   The Native Implementation serves as an instant bridge connecting both Flutter Engines
```

---

## Complete API Overview

### 1. Main Management Layer (`WindowManager`)
The primary system handle providing entry points into monitor inspection, window spawning, and event listeners.

- `Future<List<ScreenInfo>> getScreens()`: Discovers the current platform screen array topology.
- `Stream<List<ScreenInfo>> get onScreensChanged`: Realtime notification stream signaling when physical monitors are plugged, unplugged, or resolution characteristics shifting.
- `Future<Window> openWindow(WindowOptions options)`: Attaches a concrete window handle on the targeted monitor with specified styling and layout rules.
- `Stream<Map<String, dynamic>> get onDataReceived`: Stream for listening to global communication updates emitted down to secondary windows.

### 2. Physical Display Entities (`ScreenInfo`)
Immutable model mapping hardware parameters provided by underlying platform subsystems:
- `id`: Unique stable identifier token (e.g., monitor handle reference, screen index tracker).
- `name`: User-facing localized hardware display label string (e.g., "DELL U2720Q").
- `x` / `y`: Coordinate pairs mapping the display's top-left origin position in logical virtual pixels.
- `width` / `height`: Overall window dimensions calculated via logical pixel densities.
- `scaleFactor`: Device pixel density ratios (e.g., high-DPI Retina multipliers).
- `isPrimary`: Truth value flag indicating whether the entity serves as the root system monitor.

### 3. Window Control Instance (`Window`)
The actionable instance control returned from a successful `openWindow` routine invocation:
- `sendData(Map<String, dynamic> data)`: Streams structured data directly to the listening target viewport.
- `enterFullscreen()` / `enterFloating()`: Enforces full desktop immersive sizing or converts to a draggable window context.
- `setBounds({int x, int y, int width, int height})`: Updates both dimensions and screen placements in a unified transaction call.
- `setOpacity(double opacity)`: Alters surface translucency thresholds (`0.0` entirely hidden to `1.0` opaque).
- `setAlwaysOnTop(bool alwaysOnTop)`: Pins the window floating above traditional application frames.
- `setResizable(bool resizable)`: Enables or restricts user-driven cursor window resize manipulation.
- `setTitle(String title)` / `setIconPath(String? path)`: Updates window framing meta parameters (Desktop environments only).
- `close()`: Terminate visual frame lifetimes and cleanly dispose underlying engine resources.

---

## Detailed Usage Guides

### Standard Presentation Launch Example
Below is an explicit breakdown targeting secondary external display discovery, window instantiation, option configuration, and real-time state listeners:

```dart
import 'package:multi_screen_presentation/multi_screen_presentation.dart';

void initializePresentation() async {
  // 1. Fetch available desktop monitors
  final screens = await WindowManager.getScreens();
  
  // 2. Identify an external secondary screen target, falling back to primary frame if none found
  final secondaryDisplay = screens.firstWhere(
    (screen) => !screen.isPrimary, 
    orElse: () => screens.first,
  );
  
  print('Targeting screen: ${secondaryDisplay.name} [ID: ${secondaryDisplay.id}]');

  // 3. Spawning presentation window with rich initialization settings
  final window = await WindowManager.openWindow(
    WindowOptions(
      screenId: secondaryDisplay.id,
      fullscreen: true, // Start in immersive layout directly
      contentMode: PresentationContentMode.liveFlutterEngine,
      title: 'Projector View Output',
      alwaysOnTop: true,
      resizable: false,
      opacity: 1.0,
      visible: true,
    ),
  );

  // 4. Attach reactive lifecycle listeners
  window.onModeChanged.listen((WindowModeEvent event) {
    print('Window display layout changed state to: ${event.mode}');
  });

  window.onData.listen((Map<String, dynamic> responseMessage) {
    print('Payload message received back from presentation engine: $responseMessage');
  });

  window.onClosed.listen((_) {
    print('Presentation window instance was requested to close.');
  });

  // 5. Broadcast live parameters over the bidirectional pipeline
  await window.sendData({
    'currentSlideIndex': 14,
    'presentationTheme': 'dark_ambient',
    'cacheAssets': ['asset/vector_bg.svg', 'asset/intro_reel.mp4'],
  });
}
```

### Listening inside the Secondary Entrypoint
When using `PresentationContentMode.liveFlutterEngine`, make sure to declare a decoupled entrypoint within your target files (typically configured in your entry point trees, matching the option configurations). This block isolates data decoding tasks cleanly:

```dart
import 'package:flutter/material.dart';
import 'package:multi_screen_presentation/multi_screen_presentation.dart';

@pragma('vm:entry-point')
void presentationMain() {
  runApp(const PresentationApp());
}

class PresentationApp extends StatefulWidget {
  const PresentationApp({super.key});

  @override
  State<PresentationApp> createState() => _PresentationAppState();
}

class _PresentationAppState extends State<PresentationApp> {
  Map<String, dynamic> _receivedData = {};

  @override
  void initState() {
    super.initState();
    // Intercept data pushes arriving from the parent app instance thread
    WindowManager.onDataReceived.listen((Map<String, dynamic> update) {
      setState(() {
        _receivedData = update;
      });
    });
  }

  @override
  Widget build(BuildContext MaterialContext) {
    final title = _receivedData['title'] ?? 'Awaiting Payload';
    final slide = _receivedData['slide'] ?? 0;

    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Slide #$slide',
                style: const TextStyle(color: Colors.grey, fontSize: 24),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```
---

## Setup for windows

Go to the `example/windows` folder and open the `main.cpp` file.

In the `main.cpp` file, add the following line at the top of the file:
```cpp
#include "flutter/generated_plugin_registrant.h"
#include <multi_screen_presentation/multi_screen_presentation_plugin_c_api.h>

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Essential: without this call, third-party plugins will not work
  // in secondary windows (contentMode: liveFlutterEngine).
  MultiScreenPresentationPluginSetRegisterPluginsCallback(
      reinterpret_cast<void*>(RegisterPlugins));

  // ... rest of wWinMain remains unchanged ...
}

---

## Known Production Caveats & Checklist

- **Apple iOS (iPhone Devices)**: Hard ecosystem limitation enforced by Apple. Multiple window workspaces are entirely rejected; calls targeting window creation will drop, though `getScreens()` correctly maps single device information.
- **Apple iPadOS Layouts**: System scenes integration must be explicitly configured. Host client applications must include the `UIApplicationSupportsMultipleScenes = true` flag configuration inside their root `Info.plist` layout files and map out matching `application(_:configurationForConnecting:options:)` lifecycle bindings inside the host `AppDelegate` structures.
- **Google Android Platforms**: The `Presentation` framework API implements absolute full-bleed structures across external view outputs. Window floating structures, relative offset shifts, and `toggleWindowMode`/`setWindowMode` actions are silent no-ops on this platform.
- **Desktop Environments Plugin Registries (Windows / Linux)**: If your secondary isolated engine components must run dependency plugins (such as camera layers, network paths, secure file storage), remember to register them within your target window controllers (`PresentationWindowController` on macOS / `OpenWindow` routines across Win32/GTK configurations) inside native code trees.
- **Windows High-DPI Scale Factors**: The fallback engine scales default to a flat `1.0` base. Pinpoint relative physical multi-monitor scaling computations requires wiring into specific Win32 `GetDpiForMonitor` routines.