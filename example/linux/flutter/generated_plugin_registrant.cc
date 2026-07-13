//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <multi_screen_presentation/multi_screen_presentation_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) multi_screen_presentation_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MultiScreenPresentationPlugin");
  multi_screen_presentation_plugin_register_with_registrar(multi_screen_presentation_registrar);
}
