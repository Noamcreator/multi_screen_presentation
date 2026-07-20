import Cocoa
import FlutterMacOS

public class MultiScreenPresentationPlugin: NSObject, FlutterPlugin {

  public static var registerPluginsHook: ((FlutterPluginRegistry) -> Void)?
  
  static var eventSink: FlutterEventSink?
  var windows: [String: PresentationWindowController] = [:]
  var mainChannel: FlutterMethodChannel!

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "multi_screen_presentation",
      binaryMessenger: registrar.messenger)
    let eventChannel = FlutterEventChannel(
      name: "multi_screen_presentation/events",
      binaryMessenger: registrar.messenger)

    let instance = MultiScreenPresentationPlugin()
    instance.mainChannel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)

    // Écoute les branchements/débranchements d'écrans.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil, queue: .main
    ) { _ in
      MultiScreenPresentationPlugin.eventSink?(["type": "screensChanged"])
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getScreens":
      result(NSScreen.screens.map { screenToMap($0) })

    case "openWindow":
      guard let args = call.arguments as? [String: Any],
            let screenId = args["screenId"] as? String else {
        result(FlutterError(code: "bad_args", message: "screenId manquant", details: nil))
        return
      }
      guard let screen = findScreen(id: screenId) else {
        result(FlutterError(code: "no_screen", message: "Écran introuvable: \(screenId)", details: nil))
        return
      }
      let startFullscreen = args["startFullscreen"] as? Bool ?? false
      let contentMode = args["contentMode"] as? String ?? "liveFlutterEngine"
      let entrypoint = args["entrypoint"] as? String ?? "presentationMain"
      let title = args["title"] as? String ?? "Presentation"
      let x = args["x"] as? Int
      let y = args["y"] as? Int
      let width = args["width"] as? Int
      let height = args["height"] as? Int
      let opacity = args["opacity"] as? Double ?? 1.0
      let alwaysOnTop = args["alwaysOnTop"] as? Bool ?? false
      let resizable = args["resizable"] as? Bool ?? true
      let visible = args["visible"] as? Bool ?? true
      let iconPath = args["iconPath"] as? String

      let id = UUID().uuidString
      let controller = PresentationWindowController(
        id: id,
        screen: screen,
        title: title,
        startFullscreen: startFullscreen,
        useLiveEngine: contentMode == "liveFlutterEngine",
        entrypoint: entrypoint,
        position: x.flatMap { NSPoint(x: CGFloat($0), y: CGFloat(y ?? 0)) },
        size: width.flatMap { NSSize(width: CGFloat($0), height: CGFloat(height ?? 0)) },
        opacity: opacity,
        alwaysOnTop: alwaysOnTop,
        resizable: resizable,
        visible: visible,
        iconPath: iconPath,
        onModeChanged: { mode in
          MultiScreenPresentationPlugin.eventSink?([
            "type": "modeChanged",
            "windowId": id,
            "mode": mode,
            "screenId": screenId,
          ])
        },
        onClosed: { [weak self] in
          self?.windows.removeValue(forKey: id)
          MultiScreenPresentationPlugin.eventSink?(["type": "closed", "windowId": id])
        },
        onDataFromWindow: { data in
          MultiScreenPresentationPlugin.eventSink?([
            "type": "data", "windowId": id, "data": data,
          ])
        }
      )
      windows[id] = controller
      controller.show()
      result(id)

    case "closeWindow":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let w = windows[id] else {
        result(nil); return
      }
      w.close()
      windows.removeValue(forKey: id)
      result(nil)

    case "toggleWindowMode":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let w = windows[id] else {
        result(nil); return
      }
      w.toggleMode()
      result(nil)

    case "setWindowMode":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let modeStr = args["mode"] as? String,
            let w = windows[id] else {
        result(nil); return
      }
      w.setMode(fullscreen: modeStr == "fullscreen")
      result(nil)

    case "setWindowPosition":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let x = args["x"] as? Int,
            let y = args["y"] as? Int,
            let w = windows[id] else {
        result(nil); return
      }
      w.setPosition(x: x, y: y)
      result(nil)

    case "setWindowSize":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let width = args["width"] as? Int,
            let height = args["height"] as? Int,
            let w = windows[id] else {
        result(nil); return
      }
      w.setSize(width: width, height: height)
      result(nil)

    case "setWindowBounds":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let x = args["x"] as? Int,
            let y = args["y"] as? Int,
            let width = args["width"] as? Int,
            let height = args["height"] as? Int,
            let w = windows[id] else {
        result(nil); return
      }
      w.setBounds(x: x, y: y, width: width, height: height)
      result(nil)

    case "setWindowFullscreen":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let fullscreen = args["fullscreen"] as? Bool,
            let w = windows[id] else {
        result(nil); return
      }
      w.setFullscreen(fullscreen)
      result(nil)

    case "setWindowOpacity":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let opacity = args["opacity"] as? Double,
            let w = windows[id] else {
        result(nil); return
      }
      w.setOpacity(opacity)
      result(nil)

    case "setWindowAlwaysOnTop":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let alwaysOnTop = args["alwaysOnTop"] as? Bool,
            let w = windows[id] else {
        result(nil); return
      }
      w.setAlwaysOnTop(alwaysOnTop)
      result(nil)

    case "setWindowResizable":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let resizable = args["resizable"] as? Bool,
            let w = windows[id] else {
        result(nil); return
      }
      w.setResizable(resizable)
      result(nil)

    case "setWindowVisible":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let visible = args["visible"] as? Bool,
            let w = windows[id] else {
        result(nil); return
      }
      w.setVisible(visible)
      result(nil)

    case "setWindowTitle":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let title = args["title"] as? String,
            let w = windows[id] else {
        result(nil); return
      }
      w.setTitle(title)
      result(nil)

    case "setWindowIcon":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let w = windows[id] else {
        result(nil); return
      }
      let iconPath = args["iconPath"] as? String
      w.setIconPath(iconPath)
      result(nil)

    case "sendData":
      guard let args = call.arguments as? [String: Any],
            let id = args["windowId"] as? String,
            let data = args["data"] as? [String: Any],
            let w = windows[id] else {
        result(nil); return
      }
      w.sendData(data)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func findScreen(id: String) -> NSScreen? {
    return NSScreen.screens.first { screenId(for: $0) == id }
  }

  private func screenId(for screen: NSScreen) -> String {
    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    return "screen_\(number?.intValue ?? 0)"
  }

  private func screenToMap(_ screen: NSScreen) -> [String: Any] {
    let frame = screen.frame
    return [
      "id": screenId(for: screen),
      "name": screen.localizedName,
      "x": frame.origin.x,
      "y": frame.origin.y,
      "width": frame.size.width,
      "height": frame.size.height,
      "scaleFactor": screen.backingScaleFactor,
      "isPrimary": screen == NSScreen.screens.first,
    ]
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
