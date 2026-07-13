import Flutter
import UIKit

/// Sur iPhone, iOS ne permet pas plusieurs fenêtres/écrans (getScreens()
/// renverra toujours 1 seul écran, celui de l'appareil : openWindow() sur
/// un autre id échouera avec no_screen).
///
/// Sur iPad, un écran externe (AirPlay/USB-C/HDMI) apparaît dans
/// `UIScreen.screens`. Pour y afficher une VRAIE fenêtre indépendante
/// il faut activer le support multi-scène dans le projet hôte :
///   1. Info.plist : UIApplicationSceneManifest / UIApplicationSupportsMultipleScenes = true
///   2. AppDelegate : implémenter
///      application(_:configurationForConnecting:options:) pour fournir
///      une UISceneConfiguration dédiée à l'écran externe
///      (voir UIWindowScene.didConnectNotification).
/// Ce plugin fournit la brique de connexion (création de l'UIWindow sur la
/// scène de l'écran externe) mais la configuration Info.plist/AppDelegate
/// reste à la charge de l'app hôte (limite structurelle d'un plugin).
public class MultiScreenPresentationPlugin: NSObject, FlutterPlugin {
  static var eventSink: FlutterEventSink?
  var windows: [String: UIWindow] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "multi_screen_presentation", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "multi_screen_presentation/events", binaryMessenger: registrar.messenger())
    let instance = MultiScreenPresentationPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)

    NotificationCenter.default.addObserver(
      forName: UIScreen.didConnectNotification, object: nil, queue: .main
    ) { _ in MultiScreenPresentationPlugin.eventSink?(["type": "screensChanged"]) }
    NotificationCenter.default.addObserver(
      forName: UIScreen.didDisconnectNotification, object: nil, queue: .main
    ) { _ in MultiScreenPresentationPlugin.eventSink?(["type": "screensChanged"]) }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getScreens":
      result(UIScreen.screens.enumerated().map { (i, screen) -> [String: Any] in
        [
          "id": "ui_screen_\(i)",
          "name": i == 0 ? "Built-in" : "External \(i)",
          "x": 0.0, "y": 0.0,
          "width": screen.bounds.width,
          "height": screen.bounds.height,
          "scaleFactor": screen.scale,
          "isPrimary": i == 0,
        ]
      })

    case "openWindow":
      guard let args = call.arguments as? [String: Any],
            let screenId = args["screenId"] as? String,
            let idx = Int(screenId.replacingOccurrences(of: "ui_screen_", with: "")),
            idx < UIScreen.screens.count else {
        result(FlutterError(code: "no_screen", message: "Écran indisponible (iPhone = 1 seul écran).", details: nil))
        return
      }
      if idx == 0 {
        result(FlutterError(code: "unsupported", message: "L'écran principal ne peut pas être ouvert comme fenêtre secondaire sur iOS.", details: nil))
        return
      }
      let targetScreen = UIScreen.screens[idx]
      let id = UUID().uuidString
      let window = UIWindow(frame: targetScreen.bounds)
      window.screen = targetScreen
      // Le contenu (FlutterViewController avec moteur dédié) est à brancher
      // ici de la même façon que sur macOS, si l'app hôte fournit un
      // FlutterEngine secondaire. iOS ne connaît pas de mode "flottant"
      // entre écrans : la fenêtre occupe tout l'écran externe par nature.
      window.isHidden = false
      windows[id] = window
      result(id)

    case "closeWindow":
      if let args = call.arguments as? [String: Any], let id = args["windowId"] as? String {
        windows[id]?.isHidden = true
        windows.removeValue(forKey: id)
      }
      result(nil)

    case "toggleWindowMode", "setWindowMode", "sendData":
      // Non applicable / à router vers le FlutterViewController de la fenêtre
      // si un moteur dédié y est attaché (mêmes principes que macOS).
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

extension MultiScreenPresentationPlugin: FlutterStreamHandler {
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    MultiScreenPresentationPlugin.eventSink = events
    return nil
  }
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    MultiScreenPresentationPlugin.eventSink = nil
    return nil
  }
}
