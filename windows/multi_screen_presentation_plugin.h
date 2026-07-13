#ifndef FLUTTER_PLUGIN_MULTI_SCREEN_PRESENTATION_PLUGIN_H_
#define FLUTTER_PLUGIN_MULTI_SCREEN_PRESENTATION_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <map>
#include <memory>
#include <string>

namespace multi_screen_presentation {

struct PresentationWindow {
  std::string id;
  HWND hwnd = nullptr;
  bool isFullscreen = false;
  RECT floatingRect{};
  bool useLiveEngine = true;
  // Handle brut de l'API C (flutter::FlutterViewController n'est PAS
  // linkable depuis un plugin, voir la note dans multi_screen_presentation_plugin.cpp).
  FlutterDesktopViewControllerRef viewController = nullptr;
  // Permet de maintenir en vie le messager binaire pour le MethodChannel :
  std::unique_ptr<flutter::BinaryMessenger> binaryMessenger;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> windowChannel;
};

class MultiScreenPresentationPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  MultiScreenPresentationPlugin(flutter::PluginRegistrarWindows *registrar);
  virtual ~MultiScreenPresentationPlugin();

  // Emet un évènement générique vers Dart (main engine) via l'EventChannel.
  void EmitEvent(const flutter::EncodableMap &event);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::EncodableList GetScreens();
  std::string OpenWindow(const flutter::EncodableMap &args);
  void CloseWindow(const std::string &id);
  void ToggleWindowMode(const std::string &id);
  void SetWindowMode(const std::string &id, bool fullscreen);
  void SetWindowPosition(const std::string &id, int x, int y);
  void SetWindowSize(const std::string &id, int width, int height);
  void SetWindowBounds(const std::string &id, int x, int y, int width, int height);
  void SetWindowFullscreen(const std::string &id, bool fullscreen);
  void SetWindowOpacity(const std::string &id, double opacity);
  void SetWindowAlwaysOnTop(const std::string &id, bool alwaysOnTop);
  void SetWindowResizable(const std::string &id, bool resizable);
  void SetWindowVisible(const std::string &id, bool visible);
  void SetWindowTitle(const std::string &id, const std::string &title);
  void SetWindowIcon(const std::string &id, const std::string &iconPath);
  void SendData(const std::string &id, const flutter::EncodableMap &data);

  void ApplyFullscreen(PresentationWindow &w);
  void ApplyFloating(PresentationWindow &w);

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

  flutter::PluginRegistrarWindows *registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  std::map<std::string, std::unique_ptr<PresentationWindow>> windows_;
  static std::map<HWND, MultiScreenPresentationPlugin *> hwnd_registry_;
  static std::map<HWND, std::string> hwnd_to_id_;
};

}  // namespace multi_screen_presentation

#endif
