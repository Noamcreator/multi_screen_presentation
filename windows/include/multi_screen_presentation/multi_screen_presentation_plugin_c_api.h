#ifndef FLUTTER_PLUGIN_MULTI_SCREEN_PRESENTATION_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_MULTI_SCREEN_PRESENTATION_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void MultiScreenPresentationPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

// Permet à l'app (main.cpp) de fournir au plugin un pointeur vers la
// fonction RegisterPlugins() générée par Flutter (generated_plugin_registrant.h),
// afin que le plugin puisse enregistrer tous les plugins Dart tiers sur les
// fenêtres secondaires qu'il crée. Sans cette déclaration dans le header,
// main.cpp ne voit pas la fonction (définie dans le .cpp) -> C3861.
FLUTTER_PLUGIN_EXPORT void MultiScreenPresentationPluginSetRegisterPluginsCallback(
    void* callback);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif