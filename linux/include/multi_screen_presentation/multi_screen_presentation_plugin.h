#ifndef FLUTTER_PLUGIN_MULTI_SCREEN_PRESENTATION_PLUGIN_H_
#define FLUTTER_PLUGIN_MULTI_SCREEN_PRESENTATION_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _MultiScreenPresentationPlugin MultiScreenPresentationPlugin;
typedef struct {
  GObjectClass parent_class;
} MultiScreenPresentationPluginClass;

FLUTTER_PLUGIN_EXPORT GType multi_screen_presentation_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void multi_screen_presentation_plugin_register_with_registrar(
    FlPluginRegistrar *registrar);

G_END_DECLS

#endif
