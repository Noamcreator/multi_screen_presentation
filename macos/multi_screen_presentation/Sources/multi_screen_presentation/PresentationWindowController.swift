import Cocoa
import FlutterMacOS

/// Vue qui intercepte le double-clic pour basculer floating <-> fullscreen.
/// Le simple-clic / drag continue de fonctionner normalement pour déplacer
/// la fenêtre (comportement standard NSWindow, on ne bloque que le double-clic).
class DoubleClickCatcherView: NSView {
  var onDoubleClick: (() -> Void)?

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      onDoubleClick?()
      return
    }
    super.mouseDown(with: event)
    // Laisse la fenêtre parente gérer le drag normalement.
    window?.performDrag(with: event)
  }
}

class PresentationWindowController: NSObject, NSWindowDelegate {
  let id: String
  private(set) var isFullscreen: Bool
  private var floatingFrame: NSRect
  private var isAlwaysOnTop: Bool
  private var isResizable: Bool

  private var window: NSWindow!
  private var flutterViewController: FlutterViewController?
  private var engine: FlutterEngine?
  private var windowChannel: FlutterMethodChannel?

  private let onModeChanged: (String) -> Void
  private let onClosed: () -> Void
  private let onDataFromWindow: ([String: Any]) -> Void
  private let useLiveEngine: Bool
  private let entrypoint: String

  init(id: String,
       screen: NSScreen,
       title: String,
       startFullscreen: Bool,
       useLiveEngine: Bool,
       entrypoint: String,
       position: NSPoint? = nil,
       size: NSSize? = nil,
       opacity: Double = 1.0,
       alwaysOnTop: Bool = false,
       resizable: Bool = true,
       visible: Bool = true,
       iconPath: String? = nil,
       onModeChanged: @escaping (String) -> Void,
       onClosed: @escaping () -> Void,
       onDataFromWindow: @escaping ([String: Any]) -> Void) {
    self.id = id
    self.isFullscreen = startFullscreen
    self.useLiveEngine = useLiveEngine
    self.entrypoint = entrypoint
    self.isAlwaysOnTop = alwaysOnTop
    self.isResizable = resizable
    self.onModeChanged = onModeChanged
    self.onClosed = onClosed
    self.onDataFromWindow = onDataFromWindow

    // Fenêtre flottante par défaut : 70% de l'écran cible, centrée dessus.
    let sf = screen.frame
    let w = size?.width ?? (sf.width * 0.7)
    let h = size?.height ?? (sf.height * 0.7)
    let x = position?.x ?? (sf.origin.x + (sf.width - w) / 2)
    let y = position?.y ?? (sf.origin.y + (sf.height - h) / 2)
    self.floatingFrame = NSRect(x: x, y: y, width: w, height: h)

    super.init()

    let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    window = NSWindow(
      contentRect: floatingFrame,
      styleMask: styleMask,
      backing: .buffered,
      defer: false,
      screen: screen)
    window.title = title
    window.delegate = self
    window.isReleasedWhenClosed = false
    window.alphaValue = CGFloat(max(0.0, min(1.0, opacity)))
    window.level = alwaysOnTop ? .floating : .normal

    setResizable(resizable)
    if !visible { window.orderOut(nil) }
    if let iconPath { setIconPath(iconPath) }

    setupContent()

    if startFullscreen {
      applyFullscreen(on: screen)
    }
  }

  private func setupContent() {
    if useLiveEngine {
      let engine = FlutterEngine(name: "presentation_\(id)", project: FlutterDartProject())
      engine.run(withEntrypoint: entrypoint)
      // Enregistre les plugins générés (adapter selon le projet hôte,
      // voir GeneratedPluginRegistrant dans l'app macOS).
      // GeneratedPluginRegistrant.register(with: engine)

      let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
      self.engine = engine
      self.flutterViewController = vc

      windowChannel = FlutterMethodChannel(
        name: "multi_screen_presentation/window",
        binaryMessenger: engine.binaryMessenger)
      windowChannel?.setMethodCallHandler { [weak self] call, result in
        if call.method == "sendToMain", let data = call.arguments as? [String: Any] {
          self?.onDataFromWindow(data)
        }
        result(nil)
      }

      window.contentViewController = vc
    } else {
      // Mode "manual" : conteneur natif vide, pas de moteur Flutter tant
      // que sendData() n'a pas été appelé. Ici un simple NSView de fond,
      // à personnaliser (rendu natif custom, image, texte, etc.).
      let plain = NSView(frame: window.contentView?.bounds ?? .zero)
      plain.wantsLayer = true
      plain.layer?.backgroundColor = NSColor.black.cgColor
      window.contentView = plain
    }

    // Superpose la vue de capture de double-clic sur toute la fenêtre.
    installDoubleClickCatcher()
  }

  private func installDoubleClickCatcher() {
    guard let contentView = window.contentView else { return }
    let catcher = DoubleClickCatcherView(frame: contentView.bounds)
    catcher.autoresizingMask = [.width, .height]
    catcher.onDoubleClick = { [weak self] in self?.toggleMode() }
    // On l'ajoute en transparent au-dessus : elle laisse passer les clics
    // simples vers Flutter (via performDrag) et n'intercepte que le double.
    contentView.addSubview(catcher, positioned: .above, relativeTo: nil)
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
  }

  func setPosition(x: Int, y: Int) {
    let point = NSPoint(x: CGFloat(x), y: CGFloat(y))
    if isFullscreen {
      floatingFrame.origin = point
    } else {
      window.setFrameOrigin(point)
      floatingFrame.origin = point
    }
  }

  func setSize(width: Int, height: Int) {
    let size = NSSize(width: CGFloat(width), height: CGFloat(height))
    if isFullscreen {
      floatingFrame.size = size
    } else {
      window.setContentSize(size)
      floatingFrame.size = size
    }
  }

  func setBounds(x: Int, y: Int, width: Int, height: Int) {
    let rect = NSRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    if isFullscreen {
      floatingFrame = rect
    } else {
      window.setFrame(rect, display: true)
      floatingFrame = rect
    }
  }

  func setFullscreen(_ fullscreen: Bool) {
    setMode(fullscreen: fullscreen)
  }

  func setOpacity(_ opacity: Double) {
    let clamped = max(0.0, min(1.0, opacity))
    window.alphaValue = CGFloat(clamped)
  }

  func setAlwaysOnTop(_ alwaysOnTop: Bool) {
    isAlwaysOnTop = alwaysOnTop
    window.level = alwaysOnTop ? .floating : .normal
  }

  func setResizable(_ resizable: Bool) {
    isResizable = resizable
    var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
    if resizable {
      mask.insert(.resizable)
    }
    window.styleMask = mask
  }

  func setVisible(_ visible: Bool) {
    if visible { show() } else { window.orderOut(nil) }
  }

  func setTitle(_ title: String) {
    window.title = title
  }

  func setIconPath(_ iconPath: String?) {
    guard let iconPath, let image = NSImage(contentsOfFile: iconPath) else { return }
    image.size = NSSize(width: 32, height: 32)
    NSApplication.shared.applicationIconImage = image
    window.standardWindowButton(.closeButton)?.image = image
    window.standardWindowButton(.miniaturizeButton)?.image = image
    window.standardWindowButton(.zoomButton)?.image = image
  }

  func toggleMode() {
    if isFullscreen {
      setMode(fullscreen: false)
    } else {
      setMode(fullscreen: true)
    }
  }

  func setMode(fullscreen: Bool) {
    guard fullscreen != isFullscreen else { return }
    if fullscreen {
      // Mémorise la position/taille actuelle avant de passer en plein écran.
      floatingFrame = window.frame
      let targetScreen = window.screen ?? NSScreen.main!
      applyFullscreen(on: targetScreen)
    } else {
      // Restaure le comportement normal de la barre des menus et du dock
      NSApp.presentationOptions = []
      
      var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
      if isResizable { mask.insert(.resizable) }
      window.styleMask = mask
      window.setFrame(floatingFrame, display: true, animate: true)
    }
    isFullscreen = fullscreen
    onModeChanged(fullscreen ? "fullscreen" : "floating")
  }

  private func applyFullscreen(on screen: NSScreen) {
    // Masquer le Dock et la barre des menus
    // .autoHideMenuBar permet de la faire réapparaître si l'utilisateur glisse la souris tout en haut.
    // Si tu veux la bloquer COMPLÈTEMENT sans option de retour, utilise .hideMenuBar à la place.
    NSApp.presentationOptions = [.hideDock, .autoHideMenuBar]

    var mask: NSWindow.StyleMask = [.borderless]
    if isResizable { mask.insert(.resizable) }
    window.styleMask = mask
    window.setFrame(screen.frame, display: true, animate: true)
    
    // Assure que la fenêtre passe bien au-dessus du niveau de la barre de menu
    window.level = .mainMenu + 1
  }

  func sendData(_ data: [String: Any]) {
    windowChannel?.invokeMethod("onData", arguments: data)
  }

  func close() {
    window.close()
  }

  func windowWillClose(_ notification: Notification) {
    if isFullscreen {
      NSApp.presentationOptions = []
    }
    engine?.shutDownEngine()
    onClosed()
  }
}
