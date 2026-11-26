#ifndef RUNNER_WINDOW_PLACEMENT_H_
#define RUNNER_WINDOW_PLACEMENT_H_

#include <windows.h>

// Where the window's size and position are kept between runs, for the
// current user: HKCU\<kPlacementKey>, value kPlacementValue. Only the
// window's position, size and whether it was maximised; nothing about the
// user. The installer's uninstaller deletes the key.
inline constexpr wchar_t kPlacementKey[] = L"Software\\com.krathus\\Trendline";
inline constexpr wchar_t kPlacementValue[] = L"WindowPlacement";

// Saves [window]'s normal position and size, and whether it's maximised.
// Call while the window still exists (on WM_DESTROY at the latest).
void SaveWindowPlacement(HWND window);

// Moves the (still hidden) [window] to where it was last closed, without
// showing it. Returns the command to show it with: SW_SHOWMAXIMIZED if it
// was maximised, otherwise SW_SHOWNORMAL. A saved position that's no longer
// on any monitor (one was unplugged), or unreadable, is ignored and the
// window keeps its default place.
int RestoreWindowPlacement(HWND window);

#endif  // RUNNER_WINDOW_PLACEMENT_H_
