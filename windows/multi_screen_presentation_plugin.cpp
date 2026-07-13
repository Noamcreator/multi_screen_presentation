#include "multi_screen_presentation_plugin.h"

#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registry.h>

#include <algorithm>
#include <sstream>
#include <variant>

// IMPORTANT: cette signature doit correspondre EXACTEMENT à celle de
// `RegisterPlugins` générée par Flutter dans generated_plugin_registrant.h,
// c'est-à-dire `void RegisterPlugins(flutter::PluginRegistry* registry)`.
// L'ancienne version prenait un FlutterDesktopEngineRef (handle C brut), ce
// qui provoquait un mismatch d'ABI : RegisterPlugins() interprétait ce
// handle comme un objet C++ flutter::PluginRegistry*, donc les plugins
// tiers ne s'enregistraient jamais correctement sur le messenger de la 2e
// fenêtre -> d'où le "MissingPluginException / not implemented".
//
// NOTE: on ne peut PAS utiliser flutter::FlutterEngine / FlutterViewController
// / DartProject ici : leur implémentation (.cc) n'est compilée que dans
// flutter_wrapper_app (lié au runner .exe), pas dans flutter_wrapper_plugin
// (lié aux plugins). Les utiliser depuis un plugin donne des LNK2019. On
// reste donc sur l'API C pure (FlutterDesktopEngineRef, etc.), exportée par
// flutter_windows.dll et donc accessible depuis le plugin. Voir plus bas la
// classe RawEnginePluginRegistry qui fournit un vrai flutter::PluginRegistry*
// sans dépendre de FlutterEngine.
typedef void (*RegisterPluginsFunc)(flutter::PluginRegistry *);
extern RegisterPluginsFunc g_register_plugins_cb;

namespace multi_screen_presentation {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::EncodableList;

std::map<HWND, MultiScreenPresentationPlugin *> MultiScreenPresentationPlugin::hwnd_registry_;
std::map<HWND, std::string> MultiScreenPresentationPlugin::hwnd_to_id_;
// Pour stocker l'ancienne procédure de la fenêtre Flutter afin de la restaurer
static std::map<HWND, WNDPROC> old_child_procs;

namespace {
const wchar_t kWindowClassName[] = L"MultiScreenPresentationWindow";

struct MonitorEnumCtx {
  EncodableList *screens;
  int index;
};

std::string WideToUtf8(const std::wstring &wide) {
  if (wide.empty()) return std::string();
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(), (int)wide.size(),
                                  nullptr, 0, nullptr, nullptr);
  std::string result(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), (int)wide.size(),
                       result.data(), size, nullptr, nullptr);
  return result;
}

BOOL CALLBACK MonitorEnumProc(HMONITOR hMonitor, HDC, LPRECT, LPARAM lParam) {
  auto *ctx = reinterpret_cast<MonitorEnumCtx *>(lParam);
  MONITORINFOEXW info;
  info.cbSize = sizeof(info);
  GetMonitorInfoW(hMonitor, &info);

  std::string name = WideToUtf8(std::wstring(info.szDevice));

  EncodableMap m;
  std::ostringstream idStream;
  idStream << "monitor_" << ctx->index;
  m[EncodableValue("id")] = EncodableValue(idStream.str());
  m[EncodableValue("name")] = EncodableValue(name);
  m[EncodableValue("x")] = EncodableValue((double)info.rcMonitor.left);
  m[EncodableValue("y")] = EncodableValue((double)info.rcMonitor.top);
  m[EncodableValue("width")] = EncodableValue((double)(info.rcMonitor.right - info.rcMonitor.left));
  m[EncodableValue("height")] = EncodableValue((double)(info.rcMonitor.bottom - info.rcMonitor.top));
  m[EncodableValue("scaleFactor")] = EncodableValue(1.0);
  m[EncodableValue("isPrimary")] = EncodableValue((bool)(info.dwFlags & MONITORINFOF_PRIMARY));

  ctx->screens->push_back(EncodableValue(m));
  ctx->index++;
  return TRUE;
}

std::string GenerateId() {
  static int counter = 0;
  std::ostringstream oss;
  oss << "win_" << (++counter) << "_" << GetTickCount64();
  return oss.str();
}

std::wstring GetExecutableDir() {
  wchar_t path[MAX_PATH];
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring full(path);
  size_t pos = full.find_last_of(L"\\/");
  return (pos == std::wstring::npos) ? L"." : full.substr(0, pos);
}

bool FileExistsW(const std::wstring &path) {
  DWORD attrs = GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

class RawBinaryMessenger : public flutter::BinaryMessenger {
 public:
  explicit RawBinaryMessenger(FlutterDesktopMessengerRef messenger)
      : messenger_(FlutterDesktopMessengerAddRef(messenger)) {}

  ~RawBinaryMessenger() override { FlutterDesktopMessengerRelease(messenger_); }

  void Send(const std::string &channel, const uint8_t *message,
            size_t message_size, flutter::BinaryReply reply) const override {
    if (!reply) {
      FlutterDesktopMessengerSend(messenger_, channel.c_str(), message, message_size);
      return;
    }
    auto *reply_ptr = new flutter::BinaryReply(std::move(reply));
    FlutterDesktopMessengerSendWithReply(
        messenger_, channel.c_str(), message, message_size,
        [](const uint8_t *data, size_t size, void *user_data) {
          auto *r = reinterpret_cast<flutter::BinaryReply *>(user_data);
          (*r)(data, size);
          delete r;
        },
        reply_ptr);
  }

  void SetMessageHandler(const std::string &channel,
                          flutter::BinaryMessageHandler handler) override {
    if (!handler) {
      FlutterDesktopMessengerSetCallback(messenger_, channel.c_str(), nullptr, nullptr);
      return;
    }
    auto *handler_ptr = new flutter::BinaryMessageHandler(std::move(handler));
    handlers_.emplace_back(handler_ptr);
    FlutterDesktopMessengerSetCallback(
        messenger_, channel.c_str(),
        [](FlutterDesktopMessengerRef messenger,
           const FlutterDesktopMessage *message, void *user_data) {
          auto *h = reinterpret_cast<flutter::BinaryMessageHandler *>(user_data);
          auto response_handle = message->response_handle;
          (*h)(message->message, message->message_size,
               [messenger, response_handle](const uint8_t *reply, size_t reply_size) {
                 FlutterDesktopMessengerSendResponse(messenger, response_handle, reply, reply_size);
               });
        },
        handler_ptr);
  }

 private:
  FlutterDesktopMessengerRef messenger_;
  std::vector<std::unique_ptr<flutter::BinaryMessageHandler>> handlers_;
};

// Petite implémentation locale de flutter::PluginRegistry, adossée à un
// FlutterDesktopEngineRef brut. flutter::PluginRegistry est une interface
// purement virtuelle définie dans plugin_registry.h (header-only, aucun
// .cc à linker), donc on peut la sous-classer directement ici sans
// dépendre de flutter::FlutterEngine (qui, lui, n'est pas linkable depuis
// un plugin — voir la note plus haut). GetRegistrarForPlugin() délègue
// simplement à la fonction C FlutterDesktopEngineGetPluginRegistrar,
// exportée par flutter_windows.dll.
class RawEnginePluginRegistry : public flutter::PluginRegistry {
 public:
  explicit RawEnginePluginRegistry(FlutterDesktopEngineRef engine)
      : engine_(engine) {}

  FlutterDesktopPluginRegistrarRef GetRegistrarForPlugin(
      const std::string &plugin_name) override {
    return FlutterDesktopEngineGetPluginRegistrar(engine_, plugin_name.c_str());
  }

 private:
  FlutterDesktopEngineRef engine_;
};

FlutterDesktopViewControllerRef CreateSecondaryFlutterView(
    int width, int height, const std::string &entrypoint) {
  std::wstring dir = GetExecutableDir();
  std::wstring assets = dir + L"\\data\\flutter_assets";
  std::wstring icu = dir + L"\\data\\icudtl.dat";
  std::wstring aot = dir + L"\\data\\app.so";

  FlutterDesktopEngineProperties props = {};
  props.assets_path = assets.c_str();
  props.icu_data_path = icu.c_str();
  props.aot_library_path = FileExistsW(aot) ? aot.c_str() : L"";
  props.dart_entrypoint_argc = 0;
  props.dart_entrypoint_argv = nullptr;

  FlutterDesktopEngineRef engine = FlutterDesktopEngineCreate(&props);
  if (!engine) return nullptr;

  if (!FlutterDesktopEngineRun(engine, entrypoint.c_str())) {
    FlutterDesktopEngineDestroy(engine);
    return nullptr;
  }

  // Enregistre tous les plugins Dart du projet (y compris les tiers) sur
  // ce moteur secondaire, via un vrai flutter::PluginRegistry* (voir
  // RawEnginePluginRegistry ci-dessus) — c'est ce qui corrige le
  // MissingPluginException sur la 2e fenêtre.
  if (g_register_plugins_cb != nullptr) {
    RawEnginePluginRegistry registry(engine);
    g_register_plugins_cb(&registry);
  }

  return FlutterDesktopViewControllerCreate(width, height, engine);
}

// Intercepte les messages de la vue Flutter enfant
LRESULT CALLBACK FlutterChildWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  if (msg == WM_LBUTTONDBLCLK) {
    HWND parentHwnd = ::GetParent(hwnd);
    if (parentHwnd) {
      // Transmet le double-clic à la fenêtre parente
      ::PostMessage(parentHwnd, WM_LBUTTONDBLCLK, wParam, lParam);
    }
  }
  return ::CallWindowProc(old_child_procs[hwnd], hwnd, msg, wParam, lParam);
}
}  // namespace

void MultiScreenPresentationPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<MultiScreenPresentationPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

MultiScreenPresentationPlugin::MultiScreenPresentationPlugin(
    flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "multi_screen_presentation",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const auto &call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  event_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "multi_screen_presentation/events",
      &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<EncodableValue>>(
      [this](const EncodableValue *args,
            std::unique_ptr<flutter::EventSink<EncodableValue>> &&events)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        event_sink_ = std::move(events);
        return nullptr;
      },
      [this](const EncodableValue *args)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        event_sink_ = nullptr;
        return nullptr;
      });
  event_channel_->SetStreamHandler(std::move(handler));

  // --- RÉCUPÉRATION DU LOGO DEPUIS LES RESSOURCES DE L'EXÉCUTABLE ---
  HMODULE hCurrentInstance = ::GetModuleHandleW(nullptr);
  HICON hAppIcon = nullptr;

  // 1. Extraction directe de la première icône embarquée dans le fichier .exe
  wchar_t szExePath[MAX_PATH];
  ::GetModuleFileNameW(nullptr, szExePath, MAX_PATH);
  hAppIcon = ::ExtractIconW(hCurrentInstance, szExePath, 0);

  // 2. Si l'extraction échoue, méthode de secours (on interroge la fenêtre principale)
  if (hAppIcon == nullptr || hAppIcon == (HICON)1) {
    HWND mainHwnd = registrar_->GetView()->GetNativeWindow();
    if (mainHwnd) {
      hAppIcon = (HICON)::SendMessageW(mainHwnd, WM_GETICON, ICON_BIG, 0);
      if (!hAppIcon) {
        hAppIcon = (HICON)::GetClassLongPtrW(mainHwnd, GCLP_HICON);
      }
    }
  }

  // 3. Si vraiment rien ne marche, sécurité Windows (icône par défaut de l'OS)
  if (!hAppIcon || hAppIcon == (HICON)1) {
    hAppIcon = ::LoadIconW(nullptr, IDI_APPLICATION);
  }

  WNDCLASSW wc = {};
  wc.lpfnWndProc = MultiScreenPresentationPlugin::WndProc;
  wc.hInstance = hCurrentInstance;
  wc.lpszClassName = kWindowClassName;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.style = CS_DBLCLKS; 

  // FOND NOIR : évite le flash / rectangle blanc
  wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);

  // Application de l'icône extraite
  wc.hIcon = hAppIcon;

  RegisterClassW(&wc);
}

MultiScreenPresentationPlugin::~MultiScreenPresentationPlugin() {}

void MultiScreenPresentationPlugin::EmitEvent(const EncodableMap &event) {
  if (event_sink_) {
    event_sink_->Success(EncodableValue(event));
  }
}

void MultiScreenPresentationPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string &method = call.method_name();

  if (method == "getScreens") {
    result->Success(EncodableValue(GetScreens()));
  } else if (method == "openWindow") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    if (!args) { result->Error("bad_args"); return; }
    result->Success(EncodableValue(OpenWindow(*args)));
  } else if (method == "closeWindow") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto it = args->find(EncodableValue("windowId"));
    CloseWindow(std::get<std::string>(it->second));
    result->Success();
  } else if (method == "toggleWindowMode") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto it = args->find(EncodableValue("windowId"));
    ToggleWindowMode(std::get<std::string>(it->second));
    result->Success();
  } else if (method == "setWindowMode") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto modeIt = args->find(EncodableValue("mode"));
    SetWindowMode(std::get<std::string>(idIt->second),
                  std::get<std::string>(modeIt->second) == "fullscreen");
    result->Success();
  } else if (method == "setWindowPosition") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto xIt = args->find(EncodableValue("x"));
    auto yIt = args->find(EncodableValue("y"));
    SetWindowPosition(std::get<std::string>(idIt->second),
                      std::get<int>(xIt->second),
                      std::get<int>(yIt->second));
    result->Success();
  } else if (method == "setWindowSize") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto wIt = args->find(EncodableValue("width"));
    auto hIt = args->find(EncodableValue("height"));
    SetWindowSize(std::get<std::string>(idIt->second),
                  std::get<int>(wIt->second),
                  std::get<int>(hIt->second));
    result->Success();
  } else if (method == "setWindowBounds") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto xIt = args->find(EncodableValue("x"));
    auto yIt = args->find(EncodableValue("y"));
    auto wIt = args->find(EncodableValue("width"));
    auto hIt = args->find(EncodableValue("height"));
    SetWindowBounds(std::get<std::string>(idIt->second),
                    std::get<int>(xIt->second),
                    std::get<int>(yIt->second),
                    std::get<int>(wIt->second),
                    std::get<int>(hIt->second));
    result->Success();
  } else if (method == "setWindowFullscreen") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto fsIt = args->find(EncodableValue("fullscreen"));
    SetWindowFullscreen(std::get<std::string>(idIt->second),
                       std::get<bool>(fsIt->second));
    result->Success();
  } else if (method == "setWindowOpacity") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto opacityIt = args->find(EncodableValue("opacity"));
    SetWindowOpacity(std::get<std::string>(idIt->second),
                     std::get<double>(opacityIt->second));
    result->Success();
  } else if (method == "setWindowAlwaysOnTop") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto topIt = args->find(EncodableValue("alwaysOnTop"));
    SetWindowAlwaysOnTop(std::get<std::string>(idIt->second),
                         std::get<bool>(topIt->second));
    result->Success();
  } else if (method == "setWindowResizable") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto resizableIt = args->find(EncodableValue("resizable"));
    SetWindowResizable(std::get<std::string>(idIt->second),
                       std::get<bool>(resizableIt->second));
    result->Success();
  } else if (method == "setWindowVisible") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto visibleIt = args->find(EncodableValue("visible"));
    SetWindowVisible(std::get<std::string>(idIt->second),
                     std::get<bool>(visibleIt->second));
    result->Success();
  } else if (method == "setWindowTitle") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto titleIt = args->find(EncodableValue("title"));
    SetWindowTitle(std::get<std::string>(idIt->second),
                   std::get<std::string>(titleIt->second));
    result->Success();
  } else if (method == "setWindowIcon") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto iconIt = args->find(EncodableValue("iconPath"));
    SetWindowIcon(std::get<std::string>(idIt->second),
                  iconIt != args->end() && std::holds_alternative<std::string>(iconIt->second)
                      ? std::get<std::string>(iconIt->second)
                      : std::string());
    result->Success();
  } else if (method == "sendData") {
    const auto *args = std::get_if<EncodableMap>(call.arguments());
    auto idIt = args->find(EncodableValue("windowId"));
    auto dataIt = args->find(EncodableValue("data"));
    SendData(std::get<std::string>(idIt->second),
             std::get<EncodableMap>(dataIt->second));
    result->Success();
  } else {
    result->NotImplemented();
  }
}

EncodableList MultiScreenPresentationPlugin::GetScreens() {
  EncodableList screens;
  MonitorEnumCtx ctx{&screens, 0};
  EnumDisplayMonitors(nullptr, nullptr, MonitorEnumProc, reinterpret_cast<LPARAM>(&ctx));
  return screens;
}

std::string MultiScreenPresentationPlugin::OpenWindow(const EncodableMap &args) {
  std::string screenId = std::get<std::string>(args.at(EncodableValue("screenId")));
  bool startFullscreen = false;
  if (auto it = args.find(EncodableValue("startFullscreen")); it != args.end())
    startFullscreen = std::get<bool>(it->second);
  bool useLiveEngine = true;
  if (auto it = args.find(EncodableValue("contentMode")); it != args.end())
    useLiveEngine = std::get<std::string>(it->second) == "liveFlutterEngine";
  std::string title = "Presentation";
  if (auto it = args.find(EncodableValue("title")); it != args.end())
    title = std::get<std::string>(it->second);

  int x = 0;
  if (auto it = args.find(EncodableValue("x")); it != args.end())
    x = std::get<int>(it->second);
  int y = 0;
  if (auto it = args.find(EncodableValue("y")); it != args.end())
    y = std::get<int>(it->second);
  int width = 0;
  if (auto it = args.find(EncodableValue("width")); it != args.end())
    width = std::get<int>(it->second);
  int height = 0;
  if (auto it = args.find(EncodableValue("height")); it != args.end())
    height = std::get<int>(it->second);
  bool visible = true;
  if (auto it = args.find(EncodableValue("visible")); it != args.end())
    visible = std::get<bool>(it->second);
  bool alwaysOnTop = false;
  if (auto it = args.find(EncodableValue("alwaysOnTop")); it != args.end())
    alwaysOnTop = std::get<bool>(it->second);
  bool resizable = true;
  if (auto it = args.find(EncodableValue("resizable")); it != args.end())
    resizable = std::get<bool>(it->second);
  double opacity = 1.0;
  if (auto it = args.find(EncodableValue("opacity")); it != args.end())
    opacity = std::get<double>(it->second);
  std::string iconPath;
  if (auto it = args.find(EncodableValue("iconPath")); it != args.end() && std::holds_alternative<std::string>(it->second))
    iconPath = std::get<std::string>(it->second);

  struct FindCtx { std::string target; int index; RECT rect; bool found; };
  FindCtx findCtx{screenId, 0, {}, false};
  EnumDisplayMonitors(nullptr, nullptr,
    [](HMONITOR hMonitor, HDC, LPRECT, LPARAM lParam) -> BOOL {
      auto *c = reinterpret_cast<FindCtx *>(lParam);
      std::ostringstream oss; oss << "monitor_" << c->index;
      if (oss.str() == c->target) {
        MONITORINFO info; info.cbSize = sizeof(info);
        GetMonitorInfo(hMonitor, &info);
        c->rect = info.rcMonitor;
        c->found = true;
      }
      c->index++;
      return TRUE;
    }, reinterpret_cast<LPARAM>(&findCtx));

  RECT target = findCtx.found ? findCtx.rect : RECT{100, 100, 900, 700};
  int w = width > 0 ? width : (int)((target.right - target.left) * 0.7);
  int h = height > 0 ? height : (int)((target.bottom - target.top) * 0.7);
  int xPos = x != 0 ? x : target.left + ((target.right - target.left) - w) / 2;
  int yPos = y != 0 ? y : target.top + ((target.bottom - target.top) - h) / 2;

  // --- CORRECTION CONVERSION UTF-8 POUR LES ACCENTS ---
  std::wstring wtitle;
  if (!title.empty()) {
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &title[0], (int)title.size(), NULL, 0);
    wtitle.resize(size_needed);
    MultiByteToWideChar(CP_UTF8, 0, &title[0], (int)title.size(), &wtitle[0], size_needed);
  } else {
    wtitle = L"Presentation";
  }

  HWND hwnd = CreateWindowExW(
      0, kWindowClassName, wtitle.c_str(),
      WS_OVERLAPPEDWINDOW,
      xPos, yPos, w, h,
      nullptr, nullptr, GetModuleHandle(nullptr), nullptr);

  auto window = std::make_unique<PresentationWindow>();
  window->id = GenerateId();
  window->hwnd = hwnd;
  window->useLiveEngine = useLiveEngine;
  window->floatingRect = {xPos, yPos, xPos + w, yPos + h};

  hwnd_registry_[hwnd] = this;
  hwnd_to_id_[hwnd] = window->id;

  if (useLiveEngine) {
    std::string entrypoint = "presentationMain";
    if (auto it = args.find(EncodableValue("entrypoint")); it != args.end())
      entrypoint = std::get<std::string>(it->second);

    window->viewController = CreateSecondaryFlutterView(w, h, entrypoint);

    if (window->viewController) {
      FlutterDesktopViewRef flutterView = FlutterDesktopViewControllerGetView(window->viewController);
      HWND flutterHwnd = FlutterDesktopViewGetHWND(flutterView);

      ::SetParent(flutterHwnd, hwnd);
      ::MoveWindow(flutterHwnd, 0, 0, w, h, TRUE);

      // CORRECTION DOUBLE-CLIC : On détourne la procédure de la vue Flutter enfant
      old_child_procs[flutterHwnd] = (WNDPROC)::SetWindowLongPtr(flutterHwnd, GWLP_WNDPROC, (LONG_PTR)FlutterChildWndProc);

      FlutterDesktopEngineRef engineRef = FlutterDesktopViewControllerGetEngine(window->viewController);
      FlutterDesktopMessengerRef messengerRef = FlutterDesktopEngineGetMessenger(engineRef);

      window->binaryMessenger = std::make_unique<RawBinaryMessenger>(messengerRef);

      window->windowChannel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
          window->binaryMessenger.get(),
          "multi_screen_presentation/window",
          &flutter::StandardMethodCodec::GetInstance());

      std::string id = window->id;
      window->windowChannel->SetMethodCallHandler(
          [this, id](const auto &call, auto result) {
            if (call.method_name() == "sendToMain") {
              const auto *data = std::get_if<EncodableMap>(call.arguments());
              if (data) {
                EncodableMap event;
                event[EncodableValue("type")] = EncodableValue("data");
                event[EncodableValue("windowId")] = EncodableValue(id);
                event[EncodableValue("data")] = EncodableValue(*data);
                EmitEvent(event);
              }
            }
            result->Success();
          });
    }
  }

  if (visible) {
    ShowWindow(hwnd, SW_SHOW);
  } else {
    ShowWindow(hwnd, SW_HIDE);
  }
  if (alwaysOnTop) {
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
  }
  if (!resizable) {
    SetWindowLongPtr(hwnd, GWL_STYLE,
      (GetWindowLongPtr(hwnd, GWL_STYLE) & ~WS_SIZEBOX) | WS_CAPTION | WS_SYSMENU);
  }
  if (opacity >= 0.0 && opacity <= 1.0) {
    SetWindowLongPtr(hwnd, GWL_EXSTYLE,
                     GetWindowLongPtr(hwnd, GWL_EXSTYLE) | WS_EX_LAYERED);
    SetLayeredWindowAttributes(hwnd, 0, (BYTE)(opacity * 255), LWA_ALPHA);
  }
  if (!iconPath.empty()) {
    HICON hIcon = (HICON)LoadImageW(nullptr, std::wstring(iconPath.begin(), iconPath.end()).c_str(), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE);
    if (hIcon) {
      SendMessage(hwnd, WM_SETICON, ICON_BIG, (LPARAM)hIcon);
      SendMessage(hwnd, WM_SETICON, ICON_SMALL, (LPARAM)hIcon);
    }
  }

  if (startFullscreen) {
    window->isFullscreen = true;
    ApplyFullscreen(*window);
  }

  std::string id = window->id;
  windows_[id] = std::move(window);
  return id;
}

void MultiScreenPresentationPlugin::CloseWindow(const std::string &id) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;
  if (it->second->viewController) {
    FlutterDesktopViewRef flutterView = FlutterDesktopViewControllerGetView(it->second->viewController);
    HWND flutterHwnd = FlutterDesktopViewGetHWND(flutterView);
    old_child_procs.erase(flutterHwnd);
    FlutterDesktopViewControllerDestroy(it->second->viewController);
  }
  DestroyWindow(it->second->hwnd);
  windows_.erase(it);
}

void MultiScreenPresentationPlugin::ToggleWindowMode(const std::string &id) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;
  SetWindowMode(id, !it->second->isFullscreen);
}

void MultiScreenPresentationPlugin::SetWindowMode(const std::string &id, bool fullscreen) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;
  auto &w = *it->second;
  if (w.isFullscreen == fullscreen) return;
  w.isFullscreen = fullscreen;
  if (fullscreen) {
    RECT r; GetWindowRect(w.hwnd, &r);
    w.floatingRect = r;
    ApplyFullscreen(w);
  } else {
    ApplyFloating(w);
  }
  EncodableMap event;
  event[EncodableValue("type")] = EncodableValue("modeChanged");
  event[EncodableValue("windowId")] = EncodableValue(id);
  event[EncodableValue("mode")] = EncodableValue(fullscreen ? "fullscreen" : "floating");
  event[EncodableValue("screenId")] = EncodableValue(std::string(""));
  EmitEvent(event);
}

void MultiScreenPresentationPlugin::ApplyFullscreen(PresentationWindow &w) {
  HMONITOR mon = MonitorFromWindow(w.hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info; info.cbSize = sizeof(info);
  GetMonitorInfo(mon, &info);

  SetWindowLongPtr(w.hwnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
  SetWindowPos(w.hwnd, HWND_TOPMOST,
      info.rcMonitor.left, info.rcMonitor.top,
      info.rcMonitor.right - info.rcMonitor.left,
      info.rcMonitor.bottom - info.rcMonitor.top,
      SWP_FRAMECHANGED | SWP_SHOWWINDOW);

  if (w.viewController) {
    HWND flutterHwnd = FlutterDesktopViewGetHWND(FlutterDesktopViewControllerGetView(w.viewController));
    RECT r = info.rcMonitor;
    MoveWindow(flutterHwnd, 0, 0,
        r.right - r.left, r.bottom - r.top, TRUE);
  }
}

void MultiScreenPresentationPlugin::ApplyFloating(PresentationWindow &w) {
  SetWindowLongPtr(w.hwnd, GWL_STYLE, WS_OVERLAPPEDWINDOW | WS_VISIBLE);
  SetWindowPos(w.hwnd, HWND_NOTOPMOST,
      w.floatingRect.left, w.floatingRect.top,
      w.floatingRect.right - w.floatingRect.left,
      w.floatingRect.bottom - w.floatingRect.top,
      SWP_FRAMECHANGED | SWP_SHOWWINDOW);

  if (w.viewController) {
    HWND flutterHwnd = FlutterDesktopViewGetHWND(FlutterDesktopViewControllerGetView(w.viewController));
    MoveWindow(flutterHwnd, 0, 0,
        w.floatingRect.right - w.floatingRect.left,
        w.floatingRect.bottom - w.floatingRect.top, TRUE);
  }
}

void MultiScreenPresentationPlugin::SetWindowPosition(const std::string &id, int x, int y) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;
  SetWindowPos(it->second->hwnd, nullptr, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER);
}

void MultiScreenPresentationPlugin::SetWindowSize(const std::string &id, int width, int height) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;
  SetWindowPos(it->second->hwnd, nullptr, 0, 0, width, height, SWP_NOMOVE | SWP_NOZORDER);
}

void MultiScreenPresentationPlugin::SetWindowBounds(const std::string &id, int x, int y, int width, int height) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;
  SetWindowPos(it->second->hwnd, nullptr, x, y, width, height, SWP_NOZORDER);
}

void MultiScreenPresentationPlugin::SetWindowFullscreen(const std::string &id, bool fullscreen) {
  SetWindowMode(id, fullscreen);
}

void MultiScreenPresentationPlugin::SetWindowOpacity(const std::string &id, double opacity) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;
  auto alpha = static_cast<BYTE>(std::clamp(opacity, 0.0, 1.0) * 255.0);
  SetLayeredWindowAttributes(it->second->hwnd, 0, alpha, LWA_ALPHA);
}

void MultiScreenPresentationPlugin::SetWindowAlwaysOnTop(const std::string &id, bool alwaysOnTop) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;
  SetWindowPos(it->second->hwnd, alwaysOnTop ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
}

void MultiScreenPresentationPlugin::SetWindowResizable(const std::string &id, bool resizable) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;
  auto style = GetWindowLongPtr(it->second->hwnd, GWL_STYLE);
  style = resizable ? (style | WS_SIZEBOX) : (style & ~WS_SIZEBOX);
  SetWindowLongPtr(it->second->hwnd, GWL_STYLE, style);
  SetWindowPos(it->second->hwnd, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED);
}

void MultiScreenPresentationPlugin::SetWindowVisible(const std::string &id, bool visible) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;
  ShowWindow(it->second->hwnd, visible ? SW_SHOW : SW_HIDE);
}

void MultiScreenPresentationPlugin::SetWindowTitle(const std::string &id, const std::string &title) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;

  std::wstring wtitle;
  if (!title.empty()) {
    // 1. Calculer la taille requise pour la chaîne de caractères larges (UTF-16)
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &title[0], (int)title.size(), NULL, 0);
    wtitle.resize(size_needed);
    // 2. Effectuer la conversion réelle
    MultiByteToWideChar(CP_UTF8, 0, &title[0], (int)title.size(), &wtitle[0], size_needed);
  } else {
    wtitle = L"";
  }

  SetWindowTextW(it->second->hwnd, wtitle.c_str());
}

void MultiScreenPresentationPlugin::SetWindowIcon(const std::string &id, const std::string &iconPath) {
  auto it = windows_.find(id);
  if (it == windows_.end()) return;
  if (iconPath.empty()) return;
  std::wstring path(iconPath.begin(), iconPath.end());
  HICON hIcon = (HICON)LoadImageW(nullptr, path.c_str(), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE);
  if (hIcon) {
    SendMessage(it->second->hwnd, WM_SETICON, ICON_BIG, (LPARAM)hIcon);
    SendMessage(it->second->hwnd, WM_SETICON, ICON_SMALL, (LPARAM)hIcon);
  }
}

void MultiScreenPresentationPlugin::SendData(const std::string &id, const EncodableMap &data) {
  auto it = windows_.find(id);
  if (it == windows_.end() || !it->second->windowChannel) return;
  it->second->windowChannel->InvokeMethod(
      "onData", std::make_unique<EncodableValue>(data));
}

LRESULT CALLBACK MultiScreenPresentationPlugin::WndProc(
    HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  switch (msg) {
    case WM_LBUTTONDBLCLK: {
      auto pluginIt = hwnd_registry_.find(hwnd);
      auto idIt = hwnd_to_id_.find(hwnd);
      if (pluginIt != hwnd_registry_.end() && idIt != hwnd_to_id_.end()) {
        pluginIt->second->ToggleWindowMode(idIt->second);
      }
      return 0;
    }
    case WM_SIZE: {
      auto pluginIt = hwnd_registry_.find(hwnd);
      auto idIt = hwnd_to_id_.find(hwnd);
      if (pluginIt != hwnd_registry_.end() && idIt != hwnd_to_id_.end()) {
        auto& w = pluginIt->second->windows_[idIt->second];
        if (w && w->viewController) {
          HWND flutterHwnd = FlutterDesktopViewGetHWND(FlutterDesktopViewControllerGetView(w->viewController));
          int width = LOWORD(lParam);
          int height = HIWORD(lParam);
          ::MoveWindow(flutterHwnd, 0, 0, width, height, TRUE);
        }
      }
      return DefWindowProc(hwnd, msg, wParam, lParam);
    }
    case WM_CLOSE: {
      auto pluginIt = hwnd_registry_.find(hwnd);
      auto idIt = hwnd_to_id_.find(hwnd);
      if (pluginIt != hwnd_registry_.end() && idIt != hwnd_to_id_.end()) {
        EncodableMap event;
        event[EncodableValue("type")] = EncodableValue("closed");
        event[EncodableValue("windowId")] = EncodableValue(idIt->second);
        pluginIt->second->EmitEvent(event);
        
        auto& w = pluginIt->second->windows_[idIt->second];
        if (w && w->viewController) {
          HWND flutterHwnd = FlutterDesktopViewGetHWND(FlutterDesktopViewControllerGetView(w->viewController));
          old_child_procs.erase(flutterHwnd);
          FlutterDesktopViewControllerDestroy(w->viewController);
        }
        pluginIt->second->windows_.erase(idIt->second);
      }
      hwnd_registry_.erase(hwnd);
      hwnd_to_id_.erase(hwnd);
      DestroyWindow(hwnd);
      return 0;
    }
    case WM_DESTROY:
      return 0;
    default:
      return DefWindowProc(hwnd, msg, wParam, lParam);
  }
}

}  // namespace multi_screen_presentation