import Flutter
import UIKit

/// Mode d'affichage courant d'une fenêtre de présentation.
private enum LocalWindowMode: String {
  case floating
  case fullscreen
}

/// Représente une fenêtre de présentation ouverte (sur l'écran externe, ou
/// en overlay flottant sur l'écran principal de l'app).
private final class PresentationWindow {
  let id: String
  var screenId: String
  let window: UIWindow

  /// true si on peut librement repositionner/redimensionner cette fenêtre
  /// (cas d'un overlay flottant DANS la scène de l'app). false pour une
  /// fenêtre attachée à un vrai écran externe (UIScreen) : sur iOS on ne
  /// peut pas positionner une fenêtre à l'intérieur d'un écran externe,
  /// elle occupe forcément tout l'écran.
  let canReposition: Bool

  var mode: LocalWindowMode
  var floatingFrame: CGRect

  /// Moteur Flutter dédié, uniquement en mode liveFlutterEngine.
  var engine: FlutterEngine?
  /// Canal utilisé pour transmettre sendData()/onData vers ce moteur,
  /// et recevoir "sendToMain" depuis lui (symétrique du natif Linux).
  var windowChannel: FlutterMethodChannel?

  /// Label utilisé en mode "manual" (pas de moteur Flutter, rendu 100%
  /// natif minimal qui affiche juste les dernières données reçues).
  var manualLabel: UILabel?

  init(id: String, screenId: String, window: UIWindow, canReposition: Bool,
       mode: LocalWindowMode, floatingFrame: CGRect) {
    self.id = id
    self.screenId = screenId
    self.window = window
    self.canReposition = canReposition
    self.mode = mode
    self.floatingFrame = floatingFrame
  }
}

public class MultiScreenPresentationPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  // MARK: - Hook pour l'app hôte (AppDelegate)
  //
  // Chaque fenêtre "liveFlutterEngine" crée un TOUT NOUVEAU FlutterEngine.
  // Comme sur Linux/macOS/Windows, ce moteur n'a par défaut aucun plugin
  // natif enregistré (GeneratedPluginRegistrant.swift est généré au niveau
  // de l'app, le plugin ne peut pas l'importer lui-même). L'app hôte DOIT
  // donc définir ce callback dans son AppDelegate :
  //
  //   MultiScreenPresentationPlugin.pluginRegistrantCallback = { engine in
  //     GeneratedPluginRegistrant.register(with: engine)
  //   }
  //
  // Sans ça, tout MethodChannel/EventChannel appelé depuis la fenêtre
  // secondaire échoue avec MissingPluginException, comme sur Linux.
  public static var pluginRegistrantCallback: ((FlutterEngine) -> Void)?

  private var methodChannel: FlutterMethodChannel!
  private var eventSink: FlutterEventSink?
  private var windows: [String: PresentationWindow] = [:]
  private var screenIds: [ObjectIdentifier: String] = [:]
  private var nextScreenIndex = 0
  private var nextWindowIndex = 0

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MultiScreenPresentationPlugin()

    let channel = FlutterMethodChannel(
      name: "multi_screen_presentation",
      binaryMessenger: registrar.messenger())
    instance.methodChannel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)

    let eventChannel = FlutterEventChannel(
      name: "multi_screen_presentation/events",
      binaryMessenger: registrar.messenger())
    eventChannel.setStreamHandler(instance)
  }

  // MARK: - FlutterStreamHandler (canal "multi_screen_presentation/events")

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: UIScreen.didConnectNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: UIScreen.didDisconnectNotification, object: nil)
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(self)
    eventSink = nil
    return nil
  }

  @objc private func screensChanged() {
    eventSink?(["type": "screensChanged"])
  }

  private func emit(_ event: [String: Any]) {
    eventSink?(event)
  }

  // MARK: - Résolution des écrans

  private func idFor(screen: UIScreen) -> String {
    let key = ObjectIdentifier(screen)
    if let existing = screenIds[key] { return existing }
    let id = "ios_screen_\(nextScreenIndex)"
    nextScreenIndex += 1
    screenIds[key] = id
    return id
  }

  private func screenInfoMap(_ screen: UIScreen) -> [String: Any] {
    let isPrimary = screen == UIScreen.main
    return [
      "id": idFor(screen: screen),
      // iOS n'expose aucune API publique pour le nom lisible d'un écran
      // externe (contrairement à macOS NSScreen.localizedName).
      "name": isPrimary ? "Écran principal (iPhone/iPad)" : "Écran externe",
      "x": 0.0,
      "y": 0.0,
      "width": Double(screen.bounds.width),
      "height": Double(screen.bounds.height),
      "scaleFactor": Double(screen.scale),
      "isPrimary": isPrimary,
    ]
  }

  private func resolveScreen(id: String) -> UIScreen? {
    UIScreen.screens.first { idFor(screen: $0) == id }
  }

  private func currentWindowScene() -> UIWindowScene? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
      ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
  }

  // MARK: - FlutterPlugin

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)

    case "getScreens":
      result(UIScreen.screens.map { screenInfoMap($0) })

    case "openWindow":
      openWindow(call, result: result)

    case "closeWindow":
      closeWindow(call, result: result)

    case "toggleWindowMode":
      guard let w = window(from: call) else { return missing(result) }
      setMode(w, mode: w.mode == .floating ? .fullscreen : .floating)
      result(nil)

    case "setWindowMode":
      guard let w = window(from: call), let args = call.arguments as? [String: Any],
            let modeStr = args["mode"] as? String else { return missing(result) }
      setMode(w, mode: modeStr == "fullscreen" ? .fullscreen : .floating)
      result(nil)

    case "setWindowFullscreen":
      guard let w = window(from: call), let args = call.arguments as? [String: Any],
            let fullscreen = args["fullscreen"] as? Bool else { return missing(result) }
      setMode(w, mode: fullscreen ? .fullscreen : .floating)
      result(nil)

    case "setWindowPosition":
      guard let w = window(from: call), let args = call.arguments as? [String: Any] else { return missing(result) }
      if w.canReposition {
        let x = numArg(args["x"]) ?? Double(w.window.frame.origin.x)
        let y = numArg(args["y"]) ?? Double(w.window.frame.origin.y)
        w.window.frame.origin = CGPoint(x: x, y: y)
        w.floatingFrame = w.window.frame
      }
      // Sur un vrai écran externe, la position n'a pas de sens (la fenêtre
      // occupe tout l'écran) : on ignore silencieusement plutôt que d'échouer.
      result(nil)

    case "setWindowSize":
      guard let w = window(from: call), let args = call.arguments as? [String: Any] else { return missing(result) }
      if w.canReposition {
        let width = numArg(args["width"]) ?? Double(w.window.frame.width)
        let height = numArg(args["height"]) ?? Double(w.window.frame.height)
        if width > 0 && height > 0 {
          w.window.frame.size = CGSize(width: width, height: height)
          w.floatingFrame = w.window.frame
        }
      }
      result(nil)

    case "setWindowBounds":
      guard let w = window(from: call), let args = call.arguments as? [String: Any] else { return missing(result) }
      if w.canReposition {
        let x = numArg(args["x"]) ?? Double(w.window.frame.origin.x)
        let y = numArg(args["y"]) ?? Double(w.window.frame.origin.y)
        let width = numArg(args["width"]) ?? Double(w.window.frame.width)
        let height = numArg(args["height"]) ?? Double(w.window.frame.height)
        if width > 0 && height > 0 {
          w.window.frame = CGRect(x: x, y: y, width: width, height: height)
          w.floatingFrame = w.window.frame
        }
      }
      result(nil)

    case "setWindowOpacity":
      guard let w = window(from: call), let args = call.arguments as? [String: Any],
            let opacity = numArg(args["opacity"]) else { return missing(result) }
      w.window.alpha = CGFloat(opacity)
      result(nil)

    case "setWindowAlwaysOnTop":
      guard let w = window(from: call), let args = call.arguments as? [String: Any],
            let alwaysOnTop = args["alwaysOnTop"] as? Bool else { return missing(result) }
      w.window.windowLevel = alwaysOnTop ? .alert + 1 : .normal + 1
      result(nil)

    case "setWindowResizable":
      // Pas de redimensionnement utilisateur (drag) applicable sur iOS.
      result(nil)

    case "setWindowVisible":
      guard let w = window(from: call), let args = call.arguments as? [String: Any],
            let visible = args["visible"] as? Bool else { return missing(result) }
      if visible {
        w.window.isHidden = false
        w.window.makeKeyAndVisible()
      } else {
        w.window.isHidden = true
      }
      result(nil)

    case "setWindowTitle":
      // Pas de barre de titre sur iOS : no-op, on ne fait pas échouer l'appel.
      result(nil)

    case "setWindowIcon":
      // Pas d'icône de fenêtre sur iOS : no-op.
      result(nil)

    case "sendData":
      guard let w = window(from: call), let args = call.arguments as? [String: Any],
            let data = args["data"] as? [String: Any] else { return missing(result) }
      if let channel = w.windowChannel {
        channel.invokeMethod("onData", arguments: data)
      } else if let label = w.manualLabel {
        label.text = "\(data)"
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func missing(_ result: FlutterResult) {
    result(FlutterError(code: "ARGUMENT_ERROR", message: "Arguments invalides ou fenêtre introuvable", details: nil))
  }

  private func numArg(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
  }

  private func window(from call: FlutterMethodCall) -> PresentationWindow? {
    guard let args = call.arguments as? [String: Any],
          let id = args["windowId"] as? String else { return nil }
    return windows[id]
  }

  // MARK: - openWindow / closeWindow

  private func openWindow(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let screenId = args["screenId"] as? String else {
      result(FlutterError(code: "ARGUMENT_ERROR", message: "screenId manquant", details: nil))
      return
    }
    guard let targetScreen = resolveScreen(id: screenId) else {
      result(FlutterError(code: "SCREEN_NOT_FOUND", message: "Écran introuvable: \(screenId)", details: nil))
      return
    }

    let contentMode = (args["contentMode"] as? String) ?? "liveFlutterEngine"
    let startFullscreen = (args["startFullscreen"] as? Bool) ?? false
    let visible = (args["visible"] as? Bool) ?? true
    let opacity = numArg(args["opacity"]) ?? 1.0
    let entrypoint = (args["entrypoint"] as? String) ?? "presentationMain"

    let isExternalScreen = targetScreen != UIScreen.main
    let id = "ios_win_\(nextWindowIndex)"
    nextWindowIndex += 1

    let uiWindow: UIWindow
    let canReposition: Bool
    var floatingFrame: CGRect

    if isExternalScreen {
      // Sur un vrai écran externe, la fenêtre occupe TOUJOURS tout l'écran
      // (aucune notion de fenêtre flottante positionnable sur iOS/iPadOS
      // pour un UIScreen externe) : x/y/width/height fournis sont ignorés.
      uiWindow = UIWindow(frame: targetScreen.bounds)
      uiWindow.screen = targetScreen
      canReposition = false
      floatingFrame = targetScreen.bounds
    } else {
      // "Fenêtre de retour" flottante superposée sur l'écran principal :
      // implémentée comme un UIWindow additionnel dans la scène active,
      // avec un niveau au-dessus de la fenêtre normale de l'app.
      guard let scene = currentWindowScene() else {
        result(FlutterError(code: "NO_SCENE", message: "Aucune UIWindowScene active", details: nil))
        return
      }
      let x = numArg(args["x"]) ?? 40
      let y = numArg(args["y"]) ?? 80
      let width = numArg(args["width"]) ?? 360
      let height = numArg(args["height"]) ?? 240
      let frame = CGRect(x: x, y: y, width: max(width, 1), height: max(height, 1))
      uiWindow = UIWindow(windowScene: scene)
      uiWindow.frame = frame
      let alwaysOnTop = (args["alwaysOnTop"] as? Bool) ?? true
      uiWindow.windowLevel = alwaysOnTop ? .alert + 1 : .normal + 1
      canReposition = true
      floatingFrame = frame
    }

    uiWindow.alpha = CGFloat(opacity)
    uiWindow.backgroundColor = .black

    let presentationWindow = PresentationWindow(
      id: id, screenId: screenId, window: uiWindow, canReposition: canReposition,
      mode: startFullscreen ? .fullscreen : .floating, floatingFrame: floatingFrame)

    if contentMode == "manual" {
      let vc = UIViewController()
      vc.view.backgroundColor = .black
      let label = UILabel()
      label.textColor = .white
      label.numberOfLines = 0
      label.textAlignment = .center
      label.text = "En attente de données…"
      label.translatesAutoresizingMaskIntoConstraints = false
      vc.view.addSubview(label)
      NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
        label.leadingAnchor.constraint(greaterThanOrEqualTo: vc.view.leadingAnchor, constant: 16),
        label.trailingAnchor.constraint(lessThanOrEqualTo: vc.view.trailingAnchor, constant: -16),
      ])
      presentationWindow.manualLabel = label
      uiWindow.rootViewController = vc
    } else {
      // liveFlutterEngine : un moteur Flutter dédié, démarré directement
      // sur l'entrypoint demandé (iOS supporte nativement les entrypoints
      // nommés via run(withEntrypoint:), pas de contournement nécessaire
      // ici contrairement à Linux).
      let engine = FlutterEngine(name: "presentation_\(id)")
      engine.run(withEntrypoint: entrypoint)

      // Sans ceci, ce moteur n'a AUCUN plugin natif enregistré et tout
      // MethodChannel/EventChannel y échoue avec MissingPluginException.
      MultiScreenPresentationPlugin.pluginRegistrantCallback?(engine)

      let flutterVC = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
      uiWindow.rootViewController = flutterVC

      let windowChannel = FlutterMethodChannel(
        name: "multi_screen_presentation/window",
        binaryMessenger: engine.binaryMessenger)
      windowChannel.setMethodCallHandler { [weak self] call, innerResult in
        // Symétrique du natif Linux : la fenêtre secondaire peut renvoyer
        // des données vers l'app principale via "sendToMain".
        if call.method == "sendToMain" {
          self?.emit(["type": "data", "windowId": id, "data": call.arguments ?? [:]])
        }
        innerResult(nil)
      }

      presentationWindow.engine = engine
      presentationWindow.windowChannel = windowChannel
    }

    windows[id] = presentationWindow

    if canReposition, presentationWindow.mode == .fullscreen, let scene = currentWindowScene() {
      uiWindow.frame = scene.screen.bounds
    }

    if visible {
      uiWindow.isHidden = false
      if canReposition {
        uiWindow.makeKeyAndVisible()
      }
    } else {
      uiWindow.isHidden = true
    }

    // Double-tap pour basculer floating <-> fullscreen, uniquement
    // pertinent pour la fenêtre de retour flottante (un vrai écran externe
    // n'a pas de notion de "floating").
    if canReposition {
      let tap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
      tap.numberOfTapsRequired = 2
      uiWindow.addGestureRecognizer(tap)
      tapTargets[ObjectIdentifier(tap)] = id
    }

    result(id)
  }

  private var tapTargets: [ObjectIdentifier: String] = [:]

  @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
    guard let id = tapTargets[ObjectIdentifier(recognizer)], let w = windows[id] else { return }
    setMode(w, mode: w.mode == .floating ? .fullscreen : .floating)
  }

  private func setMode(_ w: PresentationWindow, mode: LocalWindowMode) {
    guard w.canReposition else { return } // pas de "floating" sur un écran externe
    if mode == .fullscreen {
      if w.mode == .floating { w.floatingFrame = w.window.frame }
      if let scene = currentWindowScene() {
        w.window.frame = scene.screen.bounds
      }
    } else {
      w.window.frame = w.floatingFrame
    }
    w.mode = mode
    emit(["type": "modeChanged", "windowId": w.id, "mode": mode.rawValue, "screenId": w.screenId])
  }

  private func closeWindow(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let id = args["windowId"] as? String,
          let w = windows[id] else {
      result(nil) // déjà fermée / inconnue : idempotent, pas d'erreur
      return
    }
    w.window.isHidden = true
    w.window.rootViewController = nil
    w.windowChannel?.setMethodCallHandler(nil)
    windows.removeValue(forKey: id)
    emit(["type": "closed", "windowId": id])
    result(nil)
  }
}