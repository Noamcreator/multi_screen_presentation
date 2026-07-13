#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

// Inclusion du registre de plugins généré par ton projet Flutter
#include "flutter/generated_plugin_registrant.h"

// Inclusion du header du plugin multi-screen
#include <multi_screen_presentation/multi_screen_presentation_plugin_c_api.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // === C'est cette fonction qui permet d'activer les plugins sur ta 2e fenêtre ===
  MultiScreenPresentationPluginSetRegisterPluginsCallback(
      reinterpret_cast<void*>(RegisterPlugins)
  );

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Size size(1300, 900);

  RECT desktop_rect;
  SystemParametersInfo(SPI_GETWORKAREA, 0, &desktop_rect, 0);
  int screen_width = desktop_rect.right - desktop_rect.left;
  int screen_height = desktop_rect.bottom - desktop_rect.top;

  int x = desktop_rect.left + (screen_width - size.width) / 2;
  int y = desktop_rect.top + (screen_height - size.height) / 2;
  Win32Window::Point origin(x, y);

  if (!window.Create(L"Multi Screen Presentation Example", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  HWND hwnd = window.GetHandle();
  if (hwnd != nullptr) {
    ::SetForegroundWindow(hwnd);
    ::SetFocus(hwnd);
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}