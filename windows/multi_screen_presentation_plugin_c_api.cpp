#include "include/multi_screen_presentation/multi_screen_presentation_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>
#include <flutter/plugin_registry.h>

#include "multi_screen_presentation_plugin.h"

// Définition du type de fonction pour le callback.
// IMPORTANT: doit être IDENTIQUE au typedef RegisterPluginsFunc déclaré
// (extern) dans multi_screen_presentation_plugin.cpp. Un typedef différent
// dans les deux fichiers produit deux noms "manglés" différents pour la
// même variable globale -> LNK2001 (symbole non résolu), car le linker
// cherche une variable qu'aucune unité de compilation ne définit avec ce
// type exact.
typedef void (*RegisterPluginsFunc)(flutter::PluginRegistry *);

// Instanciation de la variable globale (sans le mot-clé extern) pour corriger l'erreur LNK2001
RegisterPluginsFunc g_register_plugins_cb = nullptr;

void MultiScreenPresentationPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  multi_screen_presentation::MultiScreenPresentationPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

void MultiScreenPresentationPluginSetRegisterPluginsCallback(void* callback) {
  g_register_plugins_cb = reinterpret_cast<RegisterPluginsFunc>(callback);
}