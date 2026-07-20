import Cocoa
import FlutterMacOS
// N'oubliez pas d'importer le module de votre plugin si nécessaire
import multi_screen_presentation

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Enregistrement sur la vue principale
    RegisterGeneratedPlugins(registry: flutterViewController)

    // Étape 3 : Transmettre la référence de la fonction générée au plugin
    MultiScreenPresentationPlugin.registerPluginsHook = { registry in
      RegisterGeneratedPlugins(registry: registry)
    }

    super.awakeFromNib()
  }
}