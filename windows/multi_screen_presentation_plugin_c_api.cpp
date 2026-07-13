#include "include/multi_screen_presentation/multi_screen_presentation_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "multi_screen_presentation_plugin.h"

void MultiScreenPresentationPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  multi_screen_presentation::MultiScreenPresentationPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
