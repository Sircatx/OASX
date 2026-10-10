#ifndef RUNNER_STARTUP_SETTINGS_H_
#define RUNNER_STARTUP_SETTINGS_H_

#include <windows.h>
#include <string>
#include <shlobj.h>
#include <shobjidl.h>

namespace startup_settings {
constexpr wchar_t kSettingsKey[] = L"Software\\OASX";
constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";

inline bool StartMinimized(bool fallback = false) {
  DWORD value = 0;
  DWORD size = sizeof(value);
  if (RegGetValueW(HKEY_CURRENT_USER, kSettingsKey, L"StartMinimized",
                  RRF_RT_REG_DWORD, nullptr, &value, &size) != ERROR_SUCCESS) {
    return fallback;
  }
  return value != 0;
}

inline std::wstring StartupCommand() {
  wchar_t path[32768];
  const DWORD length = GetModuleFileNameW(nullptr, path, ARRAYSIZE(path));
  if (length == 0 || length >= ARRAYSIZE(path)) return L"";
  return L"\"" + std::wstring(path, length) + L"\"";
}

inline std::wstring StartupShortcut() {
  PWSTR folder = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Startup, KF_FLAG_CREATE, nullptr, &folder))) return L"";
  std::wstring path = std::wstring(folder) + L"\\OASX.lnk";
  CoTaskMemFree(folder);
  return path;
}

inline bool LaunchAtStartup() {
  const auto shortcut = StartupShortcut();
  IShellLinkW* link = nullptr;
  bool matches = false;
  if (!shortcut.empty() && SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) {
    IPersistFile* file = nullptr;
    if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&file)))) {
      wchar_t target[32768] = {};
      if (SUCCEEDED(file->Load(shortcut.c_str(), STGM_READ)) &&
          SUCCEEDED(link->GetPath(target, ARRAYSIZE(target), nullptr, SLGP_RAWPATH))) {
        matches = L"\"" + std::wstring(target) + L"\"" == StartupCommand();
      }
      file->Release();
    }
    link->Release();
  }
  if (matches) return true;
  // Recognize the previous Run entry until it is migrated.
  wchar_t value[32768];
  DWORD size = sizeof(value);
  if (RegGetValueW(HKEY_CURRENT_USER, kRunKey, L"OASX", RRF_RT_REG_SZ,
                   nullptr, value, &size) != ERROR_SUCCESS) return false;
  return std::wstring(value) == StartupCommand();
}

inline LSTATUS SetValue(const wchar_t* key, const wchar_t* name, DWORD type,
                        const void* data, DWORD size) {
  HKEY handle;
  const auto status = RegCreateKeyExW(HKEY_CURRENT_USER, key, 0, nullptr, 0,
                                     KEY_SET_VALUE, nullptr, &handle, nullptr);
  if (status != ERROR_SUCCESS) return status;
  const auto result = RegSetValueExW(handle, name, 0, type,
      static_cast<const BYTE*>(data), size);
  RegCloseKey(handle);
  return result;
}

inline LSTATUS SetStartMinimized(bool enabled) {
  DWORD value = enabled ? 1 : 0;
  return SetValue(kSettingsKey, L"StartMinimized", REG_DWORD, &value, sizeof(value));
}

inline LSTATUS SetLaunchAtStartup(bool enabled) {
  const auto shortcut = StartupShortcut();
  if (shortcut.empty()) return ERROR_PATH_NOT_FOUND;
  if (!enabled) {
    if (!DeleteFileW(shortcut.c_str()) && GetLastError() != ERROR_FILE_NOT_FOUND) return GetLastError();
    const auto status = RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, L"OASX");
    return status == ERROR_FILE_NOT_FOUND ? ERROR_SUCCESS : status;
  }
  const auto command = StartupCommand();
  if (command.empty()) return ERROR_BAD_PATHNAME;
  IShellLinkW* link = nullptr;
  HRESULT status = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&link));
  if (FAILED(status)) return ERROR_FUNCTION_FAILED;
  const auto target = command.substr(1, command.size() - 2);
  status = link->SetPath(target.c_str());
  if (SUCCEEDED(status)) status = link->SetWorkingDirectory(target.substr(0, target.find_last_of(L"\\/")).c_str());
  if (SUCCEEDED(status)) status = link->SetDescription(L"OASX");
  IPersistFile* file = nullptr;
  if (SUCCEEDED(status)) status = link->QueryInterface(IID_PPV_ARGS(&file));
  if (SUCCEEDED(status)) { status = file->Save(shortcut.c_str(), TRUE); file->Release(); }
  link->Release();
  if (FAILED(status)) return ERROR_WRITE_FAULT;
  RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, L"OASX");
  return ERROR_SUCCESS;
}
}  // namespace startup_settings

#endif
