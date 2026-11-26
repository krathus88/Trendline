#include "window_placement.h"

namespace {

// Bumped if the stored layout changes; older values are then ignored.
constexpr DWORD kVersion = 1;

// Below this, a saved size is a mistake rather than a choice.
constexpr LONG kMinSide = 200;

struct Stored {
  DWORD version;
  RECT normal;  // Restored (not maximised) bounds, workspace coordinates.
  DWORD maximized;
};

}  // namespace

void SaveWindowPlacement(HWND window) {
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!window || !::GetWindowPlacement(window, &placement)) {
    return;
  }
  Stored stored{kVersion, placement.rcNormalPosition,
                placement.showCmd == SW_SHOWMAXIMIZED ? 1u : 0u};
  // Closing while minimised keeps whether it was maximised before.
  if (placement.showCmd == SW_SHOWMINIMIZED) {
    stored.maximized = (placement.flags & WPF_RESTORETOMAXIMIZED) ? 1u : 0u;
  }
  HKEY key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kPlacementKey, 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key,
                        nullptr) != ERROR_SUCCESS) {
    return;
  }
  ::RegSetValueExW(key, kPlacementValue, 0, REG_BINARY,
                   reinterpret_cast<const BYTE*>(&stored), sizeof(stored));
  ::RegCloseKey(key);
}

int RestoreWindowPlacement(HWND window) {
  Stored stored{};
  DWORD size = sizeof(stored);
  DWORD type = 0;
  if (::RegGetValueW(HKEY_CURRENT_USER, kPlacementKey, kPlacementValue,
                     RRF_RT_REG_BINARY, &type, &stored,
                     &size) != ERROR_SUCCESS ||
      size != sizeof(stored) || stored.version != kVersion) {
    return SW_SHOWNORMAL;
  }
  const RECT& r = stored.normal;
  if (r.right - r.left < kMinSide || r.bottom - r.top < kMinSide ||
      ::MonitorFromRect(&r, MONITOR_DEFAULTTONULL) == nullptr) {
    return SW_SHOWNORMAL;
  }
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!::GetWindowPlacement(window, &placement)) {
    return SW_SHOWNORMAL;
  }
  placement.rcNormalPosition = r;
  // Keep it hidden: it's shown once Flutter has drawn its first frame.
  placement.showCmd = SW_HIDE;
  placement.flags = 0;
  ::SetWindowPlacement(window, &placement);
  return stored.maximized ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;
}
