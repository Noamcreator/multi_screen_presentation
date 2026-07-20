import Flutter
import UIKit
import multi_screen_presentation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // IMPORTANT (multi_screen_presentation) : chaque fenêtre de présentation
    // "liveFlutterEngine" démarre son propre FlutterEngine séparé. Ce moteur
    // n'a par défaut aucun plugin natif enregistré (GeneratedPluginRegistrant
    // ne peut pas être importé depuis le package du plugin lui-même). Ce
    // callback permet au plugin de demander à l'app hôte de les enregistrer
    // à chaque nouvelle fenêtre. Sans ça : MissingPluginException dès que la
    // fenêtre secondaire appelle un canal natif.
    MultiScreenPresentationPlugin.pluginRegistrantCallback = { engine in
      GeneratedPluginRegistrant.register(with: engine)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}