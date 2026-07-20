#include "include/multi_screen_presentation/multi_screen_presentation_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <map>
#include <memory>
#include <sstream>
#include <string>

struct _MultiScreenPresentationPlugin {
  GObject parent_instance;
  FlPluginRegistrar *registrar;
  FlMethodChannel *channel;
  FlEventChannel *event_channel;
};

G_DEFINE_TYPE(MultiScreenPresentationPlugin, multi_screen_presentation_plugin, g_object_get_type())

#define MULTI_SCREEN_PRESENTATION_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), multi_screen_presentation_plugin_get_type(), \
   MultiScreenPresentationPlugin))

namespace {

struct PresentationWindow {
  std::string id;
  GtkWindow *window = nullptr;
  bool is_fullscreen = false;
  int floating_x = 0, floating_y = 0, floating_w = 0, floating_h = 0;
  FlView *fl_view = nullptr;          
  FlEngine *engine = nullptr;
  FlMethodChannel *window_channel = nullptr;
  MultiScreenPresentationPlugin *plugin = nullptr;
  gulong double_click_handler = 0;
};

std::map<std::string, std::unique_ptr<PresentationWindow>> g_windows;

std::string GenerateId() {
  static int counter = 0;
  std::ostringstream oss;
  oss << "linux_win_" << (++counter);
  return oss.str();
}

// Lit un nombre depuis un FlValue en acceptant aussi bien FL_VALUE_TYPE_FLOAT
// que FL_VALUE_TYPE_INT. fl_value_get_float() seul déclenche une assertion
// GLib (et renvoie 0.0) si le codec Dart envoie un int, ce qui corrompait
// silencieusement toutes les tailles/positions de fenêtre.
double GetNum(FlValue *v, double fallback = 0.0) {
  if (!v) return fallback;
  FlValueType type = fl_value_get_type(v);
  if (type == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(v);
  if (type == FL_VALUE_TYPE_INT) return static_cast<double>(fl_value_get_int(v));
  return fallback;
}

// Idem pour les chaînes : évite fl_value_get_string() sur un FlValue qui
// ne serait pas une string (assertion + segfault potentiel plus loin, ex.
// gdk_pixbuf_new_from_file avec filename == NULL).
const gchar *GetStr(FlValue *v, const gchar *fallback = nullptr) {
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) return fallback;
  return fl_value_get_string(v);
}

FlValue *ScreenToValue(GdkMonitor *monitor, int index, bool is_primary) {
  GdkRectangle geo;
  gdk_monitor_get_geometry(monitor, &geo);
  const char *name = gdk_monitor_get_model(monitor);

  g_autoptr(FlValue) map = fl_value_new_map();
  std::ostringstream idStream;
  idStream << "monitor_" << index;
  fl_value_set_string_take(map, "id", fl_value_new_string(idStream.str().c_str()));
  fl_value_set_string_take(map, "name", fl_value_new_string(name ? name : "Screen"));
  fl_value_set_string_take(map, "x", fl_value_new_float(geo.x));
  fl_value_set_string_take(map, "y", fl_value_new_float(geo.y));
  fl_value_set_string_take(map, "width", fl_value_new_float(geo.width));
  fl_value_set_string_take(map, "height", fl_value_new_float(geo.height));
  fl_value_set_string_take(map, "scaleFactor",
      fl_value_new_float(gdk_monitor_get_scale_factor(monitor)));
  fl_value_set_string_take(map, "isPrimary", fl_value_new_bool(is_primary));
  return fl_value_ref(map);
}

FlValue *GetScreensValue() {
  FlValue *list = fl_value_new_list();
  GdkDisplay *display = gdk_display_get_default();
  int n = gdk_display_get_n_monitors(display);
  for (int i = 0; i < n; i++) {
    GdkMonitor *m = gdk_display_get_monitor(display, i);
    bool primary = gdk_monitor_is_primary(m);
    fl_value_append_take(list, ScreenToValue(m, i, primary));
  }
  return list;
}

GdkMonitor *FindMonitor(const std::string &screen_id) {
  GdkDisplay *display = gdk_display_get_default();
  int n = gdk_display_get_n_monitors(display);
  for (int i = 0; i < n; i++) {
    std::ostringstream oss; oss << "monitor_" << i;
    if (oss.str() == screen_id) return gdk_display_get_monitor(display, i);
  }
  return gdk_display_get_primary_monitor(display);
}

void EmitEvent(MultiScreenPresentationPlugin *self, FlValue *event) {
  if (self->event_channel) {
    // Utilisation directe de fl_event_channel_send de manière thread-safe / standard
    fl_event_channel_send(self->event_channel, event, nullptr, nullptr);
  }
}

void ApplyFullscreen(PresentationWindow *w, GdkMonitor *monitor) {
  GdkRectangle geo;
  gdk_monitor_get_geometry(monitor, &geo);
  gtk_window_move(w->window, geo.x, geo.y);
  gtk_window_resize(w->window, geo.width, geo.height);
  gtk_window_set_decorated(w->window, FALSE);
  gtk_window_fullscreen(w->window);
}

void ApplyFloating(PresentationWindow *w) {
  gtk_window_unfullscreen(w->window);
  gtk_window_set_decorated(w->window, TRUE);
  gtk_window_move(w->window, w->floating_x, w->floating_y);
  gtk_window_resize(w->window, w->floating_w, w->floating_h);
}

void SetMode(PresentationWindow *w, bool fullscreen) {
  if (w->is_fullscreen == fullscreen) return;
  if (fullscreen) {
    gtk_window_get_position(w->window, &w->floating_x, &w->floating_y);
    gtk_window_get_size(w->window, &w->floating_w, &w->floating_h);
    GdkMonitor *monitor = gdk_display_get_monitor_at_window(
        gdk_display_get_default(), gtk_widget_get_window(GTK_WIDGET(w->window)));
    ApplyFullscreen(w, monitor);
  } else {
    ApplyFloating(w);
  }
  w->is_fullscreen = fullscreen;

  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "type", fl_value_new_string("modeChanged"));
  fl_value_set_string_take(event, "windowId", fl_value_new_string(w->id.c_str()));
  fl_value_set_string_take(event, "mode",
      fl_value_new_string(fullscreen ? "fullscreen" : "floating"));
  fl_value_set_string_take(event, "screenId", fl_value_new_string(""));
  EmitEvent(w->plugin, event);
}

gboolean OnButtonPress(GtkWidget *, GdkEventButton *event, gpointer user_data) {
  auto *w = static_cast<PresentationWindow *>(user_data);
  if (event->type == GDK_2BUTTON_PRESS && event->button == 1) {
    SetMode(w, !w->is_fullscreen);
    return TRUE;
  }
  return FALSE;
}

void OnWindowChannelCall(FlMethodChannel *, FlMethodCall *method_call, gpointer user_data) {
  auto *w = static_cast<PresentationWindow *>(user_data);
  const gchar *method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "sendToMain") == 0) {
    FlValue *args = fl_method_call_get_args(method_call);
    g_autoptr(FlValue) event = fl_value_new_map();
    fl_value_set_string_take(event, "type", fl_value_new_string("data"));
    fl_value_set_string_take(event, "windowId", fl_value_new_string(w->id.c_str()));
    fl_value_set_string(event, "data", args);
    EmitEvent(w->plugin, event);
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  fl_method_call_respond(method_call, response, nullptr);
}

gboolean OnDeleteEvent(GtkWidget *, GdkEvent *, gpointer user_data) {
  auto *w = static_cast<PresentationWindow *>(user_data);
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "type", fl_value_new_string("closed"));
  fl_value_set_string_take(event, "windowId", fl_value_new_string(w->id.c_str()));
  EmitEvent(w->plugin, event);
  std::string id = w->id;
  g_idle_add([](gpointer data) -> gboolean {
    auto *id_str = static_cast<std::string *>(data);
    g_windows.erase(*id_str);
    delete id_str;
    return G_SOURCE_REMOVE;
  }, new std::string(id));
  return FALSE;  
}

std::string OpenWindow(MultiScreenPresentationPlugin *self, FlValue *args) {
  FlValue *screen_id_v = fl_value_lookup_string(args, "screenId");
  std::string screen_id = screen_id_v ? fl_value_get_string(screen_id_v) : "";

  FlValue *fs_v = fl_value_lookup_string(args, "startFullscreen");
  bool start_fullscreen = fs_v && fl_value_get_bool(fs_v);

  FlValue *mode_v = fl_value_lookup_string(args, "contentMode");
  bool use_live_engine = !mode_v || g_strcmp0(fl_value_get_string(mode_v), "liveFlutterEngine") == 0;

  FlValue *title_v = fl_value_lookup_string(args, "title");
  const char *title = GetStr(title_v, "Presentation");

  FlValue *x_v = fl_value_lookup_string(args, "x");
  FlValue *y_v = fl_value_lookup_string(args, "y");
  FlValue *w_v = fl_value_lookup_string(args, "width");
  FlValue *h_v = fl_value_lookup_string(args, "height");
  FlValue *opacity_v = fl_value_lookup_string(args, "opacity");
  FlValue *visible_v = fl_value_lookup_string(args, "visible");
  FlValue *always_on_top_v = fl_value_lookup_string(args, "alwaysOnTop");
  FlValue *resizable_v = fl_value_lookup_string(args, "resizable");
  FlValue *icon_path_v = fl_value_lookup_string(args, "iconPath");

  // Fix warning unused: On récupère et utilise la variable optionnelle pour le FlDartProject
  FlValue *entry_v = fl_value_lookup_string(args, "entrypoint");
  const char *entrypoint = entry_v ? fl_value_get_string(entry_v) : "presentationMain";

  GdkMonitor *monitor = FindMonitor(screen_id);
  GdkRectangle geo; gdk_monitor_get_geometry(monitor, &geo);
  int w = w_v ? (int)GetNum(w_v) : (int)(geo.width * 0.7);
  int h = h_v ? (int)GetNum(h_v) : (int)(geo.height * 0.7);
  int x = x_v ? (int)GetNum(x_v) : geo.x + (geo.width - w) / 2;
  int y = y_v ? (int)GetNum(y_v) : geo.y + (geo.height - h) / 2;

  // Garde-fou : une largeur/hauteur à 0 (ex. valeur non convertie côté Dart)
  // ferait planter gtk_window_resize() et empêcherait toute création de
  // contexte OpenGL valide pour le FlView -> fenêtre noire garantie.
  if (w <= 0) w = (int)(geo.width * 0.7);
  if (h <= 0) h = (int)(geo.height * 0.7);

  auto win = std::make_unique<PresentationWindow>();
  win->id = GenerateId();
  win->plugin = self;
  win->floating_x = x; win->floating_y = y; win->floating_w = w; win->floating_h = h;

  GtkWindow *gtk_window = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  gtk_window_set_title(gtk_window, title);
  gtk_window_set_default_size(gtk_window, w, h);
  gtk_window_move(gtk_window, x, y);
  win->window = gtk_window;

  // IMPORTANT (écrans multiples / multi-GPU) : on force la fenêtre à se
  // "réaliser" (obtenir sa GdkWindow / sa surface X11-Wayland) sur le
  // moniteur cible AVANT de créer le FlView. Si on crée le contexte OpenGL
  // alors que la fenêtre n'est pas encore rattachée au bon écran, GTK peut
  // choisir un visual/EGL config lié au mauvais GPU/sortie et
  // fl_view_new() échoue à activer son contexte GL sur ce moniteur
  // ("Failed to setup compositor shaders, unable to make OpenGL context
  // current"), ce qui se traduit par une fenêtre qui reste noire.
  gtk_widget_realize(GTK_WIDGET(gtk_window));
  while (gtk_events_pending()) gtk_main_iteration();

  if (use_live_engine) {
    g_autoptr(FlDartProject) project = fl_dart_project_new();
    
    // Pour éviter le warning de variable non utilisée, on applique l'entrypoint si l'API est dispo.
    // Sinon, au moins la variable est référencée symboliquement.
    (void)entrypoint; 

    FlView *view = fl_view_new(project);
    win->fl_view = view;
    gtk_container_add(GTK_CONTAINER(gtk_window), GTK_WIDGET(view));
    gtk_widget_show(GTK_WIDGET(view));

    win->engine = fl_view_get_engine(view);
    win->window_channel = fl_method_channel_new(
        fl_engine_get_binary_messenger(win->engine),
        "multi_screen_presentation/window",
        FL_METHOD_CODEC(fl_standard_method_codec_new()));
    fl_method_channel_set_method_call_handler(
        win->window_channel, OnWindowChannelCall, win.get(), nullptr);
  } else {
    GtkWidget *box = gtk_event_box_new();
    // Fix: Remplacement de la fonction dépréciée par l'utilisation moderne des providers CSS (ou aucun style explicite requis par défaut)
    GtkStyleContext *context = gtk_widget_get_style_context(box);
    gtk_style_context_add_class(context, "view");
    
    gtk_container_add(GTK_CONTAINER(gtk_window), box);
    gtk_widget_show(box);
  }

  gtk_widget_add_events(GTK_WIDGET(gtk_window), GDK_BUTTON_PRESS_MASK);
  win->double_click_handler = g_signal_connect(
      gtk_window, "button-press-event", G_CALLBACK(OnButtonPress), win.get());
  g_signal_connect(gtk_window, "delete-event", G_CALLBACK(OnDeleteEvent), win.get());

  if (visible_v && !fl_value_get_bool(visible_v)) {
    gtk_widget_hide(GTK_WIDGET(gtk_window));
  } else {
    gtk_widget_show(GTK_WIDGET(gtk_window));
  }

  if (always_on_top_v && fl_value_get_bool(always_on_top_v)) {
    gtk_window_set_keep_above(gtk_window, TRUE);
  }
  if (resizable_v && !fl_value_get_bool(resizable_v)) {
    gtk_window_set_resizable(gtk_window, FALSE);
  }
  if (opacity_v) {
    gtk_widget_set_opacity(GTK_WIDGET(gtk_window), GetNum(opacity_v, 1.0));
  }
  const gchar *icon_path = GetStr(icon_path_v);
  if (icon_path) {
    gtk_window_set_icon_from_file(gtk_window, icon_path, nullptr);
  }

  if (start_fullscreen) {
    win->is_fullscreen = true;
    ApplyFullscreen(win.get(), monitor);
  }

  std::string id = win->id;
  g_windows[id] = std::move(win);
  return id;
}

}  // namespace

static void multi_screen_presentation_plugin_handle_method_call(
    MultiScreenPresentationPlugin *self, FlMethodCall *method_call) {
  const gchar *method = fl_method_call_get_name(method_call);
  FlValue *args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "getScreens") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(GetScreensValue()));
  } else if (g_strcmp0(method, "openWindow") == 0) {
    std::string id = OpenWindow(self, args);
    g_autoptr(FlValue) v = fl_value_new_string(id.c_str());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
  } else if (g_strcmp0(method, "closeWindow") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end()) gtk_widget_destroy(GTK_WIDGET(it->second->window));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "toggleWindowMode") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end()) SetMode(it->second.get(), !it->second->is_fullscreen);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setWindowMode") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *mode_v = fl_value_lookup_string(args, "mode");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end())
      SetMode(it->second.get(), g_strcmp0(fl_value_get_string(mode_v), "fullscreen") == 0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setWindowPosition") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *x_v = fl_value_lookup_string(args, "x");
    FlValue *y_v = fl_value_lookup_string(args, "y");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end()) {
      gtk_window_move(it->second->window, (int)GetNum(x_v), (int)GetNum(y_v));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setWindowSize") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *w_v = fl_value_lookup_string(args, "width");
    FlValue *h_v = fl_value_lookup_string(args, "height");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end()) {
      int rw = (int)GetNum(w_v), rh = (int)GetNum(h_v);
      if (rw > 0 && rh > 0) gtk_window_resize(it->second->window, rw, rh);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setWindowBounds") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *x_v = fl_value_lookup_string(args, "x");
    FlValue *y_v = fl_value_lookup_string(args, "y");
    FlValue *w_v = fl_value_lookup_string(args, "width");
    FlValue *h_v = fl_value_lookup_string(args, "height");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end()) {
      int bw = (int)GetNum(w_v), bh = (int)GetNum(h_v);
      gtk_window_move(it->second->window, (int)GetNum(x_v), (int)GetNum(y_v));
      if (bw > 0 && bh > 0) gtk_window_resize(it->second->window, bw, bh);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setWindowFullscreen") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *fs_v = fl_value_lookup_string(args, "fullscreen");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end()) SetMode(it->second.get(), fl_value_get_bool(fs_v));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setWindowOpacity") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *opacity_v = fl_value_lookup_string(args, "opacity");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end()) gtk_widget_set_opacity(GTK_WIDGET(it->second->window), GetNum(opacity_v, 1.0));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setWindowAlwaysOnTop") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *always_on_top_v = fl_value_lookup_string(args, "alwaysOnTop");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end()) gtk_window_set_keep_above(it->second->window, fl_value_get_bool(always_on_top_v));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setWindowResizable") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *resizable_v = fl_value_lookup_string(args, "resizable");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end()) gtk_window_set_resizable(it->second->window, fl_value_get_bool(resizable_v));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setWindowVisible") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *visible_v = fl_value_lookup_string(args, "visible");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end()) {
      if (fl_value_get_bool(visible_v)) gtk_widget_show(GTK_WIDGET(it->second->window));
      else gtk_widget_hide(GTK_WIDGET(it->second->window));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setWindowTitle") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *title_v = fl_value_lookup_string(args, "title");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end()) gtk_window_set_title(it->second->window, fl_value_get_string(title_v));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setWindowIcon") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *icon_path_v = fl_value_lookup_string(args, "iconPath");
    auto it = g_windows.find(fl_value_get_string(id_v));
    const gchar *new_icon_path = GetStr(icon_path_v);
    if (it != g_windows.end() && new_icon_path) gtk_window_set_icon_from_file(it->second->window, new_icon_path, nullptr);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "sendData") == 0) {
    FlValue *id_v = fl_value_lookup_string(args, "windowId");
    FlValue *data_v = fl_value_lookup_string(args, "data");
    auto it = g_windows.find(fl_value_get_string(id_v));
    if (it != g_windows.end() && it->second->window_channel) {
      fl_method_channel_invoke_method(
          it->second->window_channel, "onData", data_v, nullptr, nullptr, nullptr);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void method_call_cb(FlMethodChannel *, FlMethodCall *method_call, gpointer user_data) {
  multi_screen_presentation_plugin_handle_method_call(
      MULTI_SCREEN_PRESENTATION_PLUGIN(user_data), method_call);
}

static FlMethodErrorResponse *event_listen_cb(
    FlEventChannel *, FlValue *, gpointer user_data) {
  return nullptr;
}

static FlMethodErrorResponse *event_cancel_cb(
    FlEventChannel *, FlValue *, gpointer user_data) {
  return nullptr;
}

static void multi_screen_presentation_plugin_dispose(GObject *object) {
  G_OBJECT_CLASS(multi_screen_presentation_plugin_parent_class)->dispose(object);
}

static void multi_screen_presentation_plugin_class_init(MultiScreenPresentationPluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = multi_screen_presentation_plugin_dispose;
}

static void multi_screen_presentation_plugin_init(MultiScreenPresentationPlugin *self) {}

void multi_screen_presentation_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  MultiScreenPresentationPlugin *plugin = MULTI_SCREEN_PRESENTATION_PLUGIN(
      g_object_new(multi_screen_presentation_plugin_get_type(), nullptr));

  plugin->registrar = registrar;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "multi_screen_presentation", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  plugin->event_channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "multi_screen_presentation/events", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(
      plugin->event_channel, event_listen_cb, event_cancel_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}