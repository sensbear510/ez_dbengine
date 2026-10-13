#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

FlutterWindow window(project);

  // 1. Initial creation with default origin (Flutter handles initial DPI sizing)
  Win32Window::Point origin(0, 0);
  Win32Window::Size size(1280, 720);

  if (!window.Create(L"ezDBUtility", origin, size)) {
    return EXIT_FAILURE;
  }

  // 2. Precision Centering via Win32 HWND Handle (Bypasses double DPI scaling)
  HWND hwnd = window.GetHandle();
  if (hwnd != nullptr) {
    // Locate the active monitor based on current mouse cursor position
    POINT cursor_pt;
    GetCursorPos(&cursor_pt);
    HMONITOR h_monitor = MonitorFromPoint(cursor_pt, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = { sizeof(MONITORINFO) };
    GetMonitorInfo(h_monitor, &mi);

    // Fetch actual DPI-scaled window dimensions rendered by Windows
    RECT window_rect;
    GetWindowRect(hwnd, &window_rect);
    int actual_width = window_rect.right - window_rect.left;
    int actual_height = window_rect.bottom - window_rect.top;

    // Calculate active monitor work area dimensions (excluding taskbar)
    int work_width = mi.rcWork.right - mi.rcWork.left;
    int work_height = mi.rcWork.bottom - mi.rcWork.top;

    // Compute exact physical centered coordinates for the active monitor
    int centered_x = mi.rcWork.left + (work_width - actual_width) / 2;
    int centered_y = mi.rcWork.top + (work_height - actual_height) / 2;

    // Reposition window directly using physical screen coordinates
    SetWindowPos(
      hwnd,
      NULL,
      centered_x,
      centered_y,
      0,
      0,
      SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
    );
  }

  window.SetQuitOnClose(true);

  

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
