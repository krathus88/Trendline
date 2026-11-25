#include "url_scheme.h"

#include <windows.h>

#include <string>

namespace {

bool SetStringValue(HKEY root, const std::wstring& subkey,
                    const wchar_t* name, const std::wstring& value) {
  HKEY key = nullptr;
  if (::RegCreateKeyExW(root, subkey.c_str(), 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key,
                        nullptr) != ERROR_SUCCESS) {
    return false;
  }
  const auto bytes =
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  const LSTATUS status =
      ::RegSetValueExW(key, name, 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(value.c_str()), bytes);
  ::RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

}  // namespace

bool RegisterUrlScheme() {
  // Long paths are possible, so grow the buffer until the path fits.
  std::wstring exe(MAX_PATH, L'\0');
  for (;;) {
    const DWORD length = ::GetModuleFileNameW(
        nullptr, exe.data(), static_cast<DWORD>(exe.size()));
    if (length == 0) return false;
    if (length < exe.size()) {
      exe.resize(length);
      break;
    }
    exe.resize(exe.size() * 2);
  }

  const std::wstring base = std::wstring(L"Software\\Classes\\") + kUrlScheme;
  // The link must arrive as the only argument: the app_links plugin ignores
  // the command line unless it has exactly one.
  const std::wstring command = L"\"" + exe + L"\" \"%1\"";

  return SetStringValue(HKEY_CURRENT_USER, base, nullptr,
                        L"URL:Trendline sign-in") &&
         SetStringValue(HKEY_CURRENT_USER, base, L"URL Protocol", L"") &&
         SetStringValue(HKEY_CURRENT_USER, base + L"\\DefaultIcon", nullptr,
                        L"\"" + exe + L"\",0") &&
         SetStringValue(HKEY_CURRENT_USER, base + L"\\shell\\open\\command",
                        nullptr, command);
}
