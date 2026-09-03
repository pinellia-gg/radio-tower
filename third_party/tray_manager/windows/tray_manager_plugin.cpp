#include "include/tray_manager/tray_manager_plugin.h"

// This must be included before many other Windows headers.
#include <stdio.h>
#include <windows.h>

#include <shellapi.h>
#include <strsafe.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <codecvt>
#include <map>
#include <memory>
#include <sstream>
#include <vector>

#define WM_MYMESSAGE (WM_USER + 1)

namespace {

const flutter::EncodableValue* ValueOrNull(const flutter::EncodableMap& map,
                                           const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return nullptr;
  }
  return &(it->second);
}
std::unique_ptr<
    flutter::MethodChannel<flutter::EncodableValue>,
    std::default_delete<flutter::MethodChannel<flutter::EncodableValue>>>
    channel = nullptr;

class TrayManagerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  TrayManagerPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~TrayManagerPlugin();

 private:
  static constexpr UINT kStatusRowId = 0xFFFE;
  static constexpr UINT kControlsRowId = 0xFFFF;

  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> g_converter;

  flutter::PluginRegistrarWindows* registrar;
  NOTIFYICONDATA nid;
  NOTIFYICONIDENTIFIER niif;
  // do create pop-up menu only once.
  HMENU hMenu = CreatePopupMenu();
  std::vector<HBITMAP> menu_item_bitmaps;
  int play_pause_item_id_ = -1;
  bool is_playing_ = false;
  bool has_station_ = false;
  std::wstring status_text_ = L"\x672A\x64AD\x653E\x7535\x53F0";
  HICON play_pause_icon_ = nullptr;
  bool tray_icon_setted = false;
  UINT windows_taskbar_created_message_id = 0;

  // The ID of the WindowProc delegate registration.
  int window_proc_id = -1;

  void TrayManagerPlugin::_CreateMenu(HMENU menu, flutter::EncodableMap args);
  void TrayManagerPlugin::_ClearMenu();
  void TrayManagerPlugin::_ConfigureControls(
      const flutter::EncodableMap& args);
  void TrayManagerPlugin::_ClearControls();
  void TrayManagerPlugin::_ApplyIcon();
  HBITMAP TrayManagerPlugin::_CreateMenuItemBitmap(
      const std::string& icon_path);
  HICON TrayManagerPlugin::_LoadControlIcon(const std::string& icon_path);
  HFONT TrayManagerPlugin::_CreateMenuTextFont(int height);
  bool TrayManagerPlugin::_MeasureControls(MEASUREITEMSTRUCT* measure_item);
  bool TrayManagerPlugin::_DrawControls(DRAWITEMSTRUCT* draw_item);
  void TrayManagerPlugin::_EmitMenuItemClick(int item_id);

  // Called for top-level WindowProc delegation.
  std::optional<LRESULT> TrayManagerPlugin::HandleWindowProc(HWND hwnd,
                                                             UINT message,
                                                             WPARAM wparam,
                                                             LPARAM lparam);
  HWND TrayManagerPlugin::GetMainWindow();
  void TrayManagerPlugin::Destroy(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::SetIcon(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::SetToolTip(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::SetContextMenu(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::PopUpContextMenu(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::GetBounds(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

static bool plugin_already_registered = false;

// static
void TrayManagerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  if (plugin_already_registered) {
    // Skip registration in subwindow
    return;
  }

  plugin_already_registered = true;

  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "tray_manager",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<TrayManagerPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

TrayManagerPlugin::TrayManagerPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar(registrar) {
  window_proc_id = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
  windows_taskbar_created_message_id = RegisterWindowMessage(L"TaskbarCreated");
}

TrayManagerPlugin::~TrayManagerPlugin() {
  registrar->UnregisterTopLevelWindowProcDelegate(window_proc_id);
  _ClearMenu();
  DestroyMenu(hMenu);
}

void TrayManagerPlugin::_CreateMenu(HMENU menu, flutter::EncodableMap args) {
  flutter::EncodableList items = std::get<flutter::EncodableList>(
      args.at(flutter::EncodableValue("items")));

  for (flutter::EncodableValue item_value : items) {
    flutter::EncodableMap item_map =
        std::get<flutter::EncodableMap>(item_value);
    int id = std::get<int>(item_map.at(flutter::EncodableValue("id")));
    if (id == play_pause_item_id_) {
      continue;
    }
    std::string type =
        std::get<std::string>(item_map.at(flutter::EncodableValue("type")));
    std::string label =
        std::get<std::string>(item_map.at(flutter::EncodableValue("label")));
    auto* checked = std::get_if<bool>(ValueOrNull(item_map, "checked"));
    bool disabled =
        std::get<bool>(item_map.at(flutter::EncodableValue("disabled")));

    UINT_PTR item_id = id;
    UINT uFlags = MF_STRING;

    if (disabled) {
      uFlags |= MF_GRAYED;
    }

    if (type.compare("separator") == 0) {
      AppendMenuW(menu, MF_SEPARATOR, item_id, NULL);
    } else {
      if (type.compare("checkbox") == 0) {
        if (checked == nullptr) {
          // skip
        } else {
          uFlags |= (*checked == true ? MF_CHECKED : MF_UNCHECKED);
        }
      } else if (type.compare("submenu") == 0) {
        uFlags |= MF_POPUP;
        HMENU sub_menu = ::CreatePopupMenu();
        _CreateMenu(sub_menu, std::get<flutter::EncodableMap>(item_map.at(
                                  flutter::EncodableValue("submenu"))));
        item_id = reinterpret_cast<UINT_PTR>(sub_menu);
      }
      AppendMenuW(menu, uFlags, item_id, g_converter.from_bytes(label).c_str());
      if (type.compare("submenu") != 0) {
        const auto* icon_value = ValueOrNull(item_map, "icon");
        if (icon_value != nullptr) {
          if (const auto* icon_path = std::get_if<std::string>(icon_value)) {
            auto bitmap = _CreateMenuItemBitmap(*icon_path);
            if (bitmap != nullptr) {
              MENUITEMINFOW menu_item_info{};
              menu_item_info.cbSize = sizeof(menu_item_info);
              menu_item_info.fMask = MIIM_BITMAP;
              menu_item_info.hbmpItem = bitmap;
              SetMenuItemInfoW(menu, static_cast<UINT>(item_id), FALSE,
                               &menu_item_info);
              menu_item_bitmaps.emplace_back(bitmap);
            }
          }
        }
      }
    }
  }
}

void TrayManagerPlugin::_ClearMenu() {
  const int count = GetMenuItemCount(hMenu);
  for (int index = count - 1; index >= 0; --index) {
    HMENU submenu = GetSubMenu(hMenu, index);
    RemoveMenu(hMenu, index, MF_BYPOSITION);
    if (submenu != nullptr) {
      DestroyMenu(submenu);
    }
  }
  for (auto bitmap : menu_item_bitmaps) {
    DeleteObject(bitmap);
  }
  menu_item_bitmaps.clear();
  _ClearControls();
}

void TrayManagerPlugin::_ConfigureControls(
    const flutter::EncodableMap& args) {
  const auto* controls_value = ValueOrNull(args, "controls");
  if (controls_value == nullptr) {
    return;
  }
  const auto* controls =
      std::get_if<flutter::EncodableMap>(controls_value);
  if (controls == nullptr) {
    return;
  }

  const auto* play_pause_id = ValueOrNull(*controls, "playPauseItemId");
  if (play_pause_id == nullptr) {
    return;
  }
  const auto* play_pause_item_id = std::get_if<int>(play_pause_id);
  if (play_pause_item_id == nullptr) {
    return;
  }

  play_pause_item_id_ = *play_pause_item_id;
  if (const auto* is_playing = ValueOrNull(*controls, "isPlaying")) {
    if (const auto* value = std::get_if<bool>(is_playing)) {
      is_playing_ = *value;
    }
  }
  if (const auto* has_station = ValueOrNull(*controls, "hasStation")) {
    if (const auto* value = std::get_if<bool>(has_station)) {
      has_station_ = *value;
    }
  }
  if (const auto* status = ValueOrNull(*controls, "statusText")) {
    if (const auto* value = std::get_if<std::string>(status)) {
      status_text_ = g_converter.from_bytes(*value);
    }
  }
  if (const auto* icon = ValueOrNull(*controls, "playPauseIcon")) {
    if (const auto* icon_path = std::get_if<std::string>(icon)) {
      play_pause_icon_ = _LoadControlIcon(*icon_path);
    }
  }

  AppendMenuW(hMenu, MF_OWNERDRAW | MF_DISABLED, kStatusRowId, nullptr);
  AppendMenuW(hMenu, MF_OWNERDRAW, kControlsRowId, nullptr);
  AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);
}

void TrayManagerPlugin::_ClearControls() {
  if (play_pause_icon_ != nullptr) {
    DestroyIcon(play_pause_icon_);
    play_pause_icon_ = nullptr;
  }
  play_pause_item_id_ = -1;
  is_playing_ = false;
  has_station_ = false;
  status_text_ = L"\x672A\x64AD\x653E\x7535\x53F0";
}

HBITMAP TrayManagerPlugin::_CreateMenuItemBitmap(
    const std::string& icon_path) {
  constexpr int kIconSize = 20;
  HICON icon = static_cast<HICON>(LoadImageW(
      nullptr, g_converter.from_bytes(icon_path).c_str(), IMAGE_ICON,
      kIconSize, kIconSize, LR_LOADFROMFILE));
  if (icon == nullptr) {
    return nullptr;
  }

  HDC screen_dc = GetDC(nullptr);
  if (screen_dc == nullptr) {
    DestroyIcon(icon);
    return nullptr;
  }
  HDC memory_dc = CreateCompatibleDC(screen_dc);
  HBITMAP bitmap = CreateCompatibleBitmap(screen_dc, kIconSize, kIconSize);
  if (memory_dc == nullptr || bitmap == nullptr) {
    if (memory_dc != nullptr) {
      DeleteDC(memory_dc);
    }
    if (bitmap != nullptr) {
      DeleteObject(bitmap);
    }
    ReleaseDC(nullptr, screen_dc);
    DestroyIcon(icon);
    return nullptr;
  }
  HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);
  RECT bounds{0, 0, kIconSize, kIconSize};
  FillRect(memory_dc, &bounds, GetSysColorBrush(COLOR_MENU));
  DrawIconEx(memory_dc, 0, 0, icon, kIconSize, kIconSize, 0, nullptr,
             DI_NORMAL);
  SelectObject(memory_dc, old_bitmap);
  DeleteDC(memory_dc);
  ReleaseDC(nullptr, screen_dc);
  DestroyIcon(icon);
  return bitmap;
}

HICON TrayManagerPlugin::_LoadControlIcon(const std::string& icon_path) {
  constexpr int kIconSize = 24;
  return static_cast<HICON>(LoadImageW(
      nullptr, g_converter.from_bytes(icon_path).c_str(), IMAGE_ICON,
      kIconSize, kIconSize, LR_LOADFROMFILE));
}

HFONT TrayManagerPlugin::_CreateMenuTextFont(int height) {
  NONCLIENTMETRICSW metrics{};
  metrics.cbSize = sizeof(metrics);

  LOGFONTW menu_font{};
  if (SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof(metrics),
                            &metrics, 0)) {
    menu_font = metrics.lfMenuFont;
  } else {
    menu_font.lfCharSet = DEFAULT_CHARSET;
    StringCchCopyW(menu_font.lfFaceName, _countof(menu_font.lfFaceName),
                   L"Microsoft YaHei UI");
  }
  menu_font.lfHeight = -height;
  menu_font.lfWeight = FW_NORMAL;
  menu_font.lfQuality = CLEARTYPE_QUALITY;
  return CreateFontIndirectW(&menu_font);
}

bool TrayManagerPlugin::_MeasureControls(MEASUREITEMSTRUCT* measure_item) {
  if (measure_item == nullptr || measure_item->CtlType != ODT_MENU) {
    return false;
  }
  if (measure_item->itemID == kStatusRowId) {
    measure_item->itemWidth = 280;
    measure_item->itemHeight = 52;
    return true;
  }
  if (measure_item->itemID != kControlsRowId) {
    return false;
  }
  measure_item->itemWidth = 280;
  measure_item->itemHeight = 58;
  return true;
}

bool TrayManagerPlugin::_DrawControls(DRAWITEMSTRUCT* draw_item) {
  if (draw_item == nullptr || draw_item->CtlType != ODT_MENU ||
      (draw_item->itemID != kStatusRowId &&
       draw_item->itemID != kControlsRowId)) {
    return false;
  }

  const RECT& item_rect = draw_item->rcItem;
  FillRect(draw_item->hDC, &item_rect, GetSysColorBrush(COLOR_MENU));

  if (draw_item->itemID == kStatusRowId) {
    constexpr int kHorizontalPadding = 16;
    const int title_top = item_rect.top + 9;
    const int status_top = item_rect.top + 29;
    RECT title_rect{item_rect.left + kHorizontalPadding, title_top,
                    item_rect.right - kHorizontalPadding, status_top};
    RECT status_rect{item_rect.left + kHorizontalPadding, status_top,
                     item_rect.right - kHorizontalPadding,
                     item_rect.bottom - 7};

    HFONT title_font = _CreateMenuTextFont(15);
    HFONT status_font = _CreateMenuTextFont(13);
    const int old_background_mode = SetBkMode(draw_item->hDC, TRANSPARENT);
    HGDIOBJ old_font = GetCurrentObject(draw_item->hDC, OBJ_FONT);
    if (title_font != nullptr) {
      SelectObject(draw_item->hDC, title_font);
    }
    SetTextColor(draw_item->hDC, RGB(32, 35, 40));
    DrawTextW(draw_item->hDC,
              !has_station_ ? L"\x672A\x64AD\x653E"
                            : (is_playing_ ? L"\x6B63\x5728\x64AD\x653E"
                                           : L"\x5DF2\x6682\x505C"),
              -1,
              &title_rect, DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);
    if (old_font != nullptr) {
      SelectObject(draw_item->hDC, old_font);
    }
    if (status_font != nullptr) {
      SelectObject(draw_item->hDC, status_font);
    }
    SetTextColor(draw_item->hDC, RGB(112, 118, 126));
    DrawTextW(draw_item->hDC, status_text_.c_str(), -1, &status_rect,
              DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);
    if (old_font != nullptr) {
      SelectObject(draw_item->hDC, old_font);
    }
    SetBkMode(draw_item->hDC, old_background_mode);
    if (title_font != nullptr) {
      DeleteObject(title_font);
    }
    if (status_font != nullptr) {
      DeleteObject(status_font);
    }
    return true;
  }

  const bool selected = (draw_item->itemState & ODS_SELECTED) != 0;
  constexpr int kButtonSize = 40;
  constexpr int kIconSize = 24;
  const int center_y = (item_rect.top + item_rect.bottom) / 2;
  const int center_x = (item_rect.left + item_rect.right) / 2;
  const COLORREF button_color = selected ? RGB(226, 238, 250)
                                         : RGB(244, 248, 252);
  HBRUSH button_brush = CreateSolidBrush(button_color);
  HPEN border_pen = CreatePen(PS_SOLID, 1, RGB(205, 216, 228));
  HGDIOBJ old_brush = SelectObject(draw_item->hDC, button_brush);
  HGDIOBJ old_pen = SelectObject(draw_item->hDC, border_pen);
  Ellipse(draw_item->hDC, center_x - kButtonSize / 2,
          center_y - kButtonSize / 2, center_x + kButtonSize / 2,
          center_y + kButtonSize / 2);
  SelectObject(draw_item->hDC, old_pen);
  SelectObject(draw_item->hDC, old_brush);
  DeleteObject(border_pen);
  DeleteObject(button_brush);

  if (play_pause_icon_ != nullptr) {
    DrawIconEx(draw_item->hDC, center_x - kIconSize / 2,
               center_y - kIconSize / 2, play_pause_icon_, kIconSize,
               kIconSize, 0, nullptr, DI_NORMAL);
  }
  return true;
}

void TrayManagerPlugin::_EmitMenuItemClick(int item_id) {
  flutter::EncodableMap event_data = flutter::EncodableMap();
  event_data[flutter::EncodableValue("id")] = flutter::EncodableValue(item_id);
  channel->InvokeMethod(
      "onTrayMenuItemClick",
      std::make_unique<flutter::EncodableValue>(event_data));
}

std::optional<LRESULT> TrayManagerPlugin::HandleWindowProc(HWND hWnd,
                                                           UINT message,
                                                           WPARAM wParam,
                                                           LPARAM lParam) {
  std::optional<LRESULT> result;
  if (message == WM_DESTROY) {
    if (tray_icon_setted) {
      Shell_NotifyIcon(NIM_DELETE, &nid);
      DestroyIcon(nid.hIcon);
    }
  } else if (message == WM_MEASUREITEM) {
    if (_MeasureControls(reinterpret_cast<MEASUREITEMSTRUCT*>(lParam))) {
      return 0;
    }
  } else if (message == WM_DRAWITEM) {
    if (_DrawControls(reinterpret_cast<DRAWITEMSTRUCT*>(lParam))) {
      return 0;
    }
  } else if (message == WM_COMMAND) {
    const UINT command_id = LOWORD(wParam);
    if (command_id == kControlsRowId) {
      if (play_pause_item_id_ > 0) {
        _EmitMenuItemClick(play_pause_item_id_);
      }
      return 0;
    }
    if (command_id == kStatusRowId) {
      return 0;
    }
    _EmitMenuItemClick(static_cast<int>(command_id));
  } else if (message == WM_MYMESSAGE) {
    switch (lParam) {
      case WM_LBUTTONUP:
        channel->InvokeMethod("onTrayIconMouseDown",
                              std::make_unique<flutter::EncodableValue>());
        break;
      case WM_RBUTTONUP:
        channel->InvokeMethod("onTrayIconRightMouseDown",
                              std::make_unique<flutter::EncodableValue>());
        break;
      default:
        return DefWindowProc(hWnd, message, wParam, lParam);
    };
  } else if (message == windows_taskbar_created_message_id) {
    if (windows_taskbar_created_message_id != 0 && tray_icon_setted) {
      // restore the icon with the existing resource.
      tray_icon_setted = false;
      _ApplyIcon();
    }
  } else if (message == WM_POWERBROADCAST) {
    // Handle power management events (sleep/wake)
    switch (wParam) {
      case PBT_APMRESUMEAUTOMATIC:
      case PBT_APMRESUMESUSPEND:
        // System is resuming from sleep/hibernation
        if (tray_icon_setted) {
          // Restore the tray icon after system wakes up
          tray_icon_setted = false;
          _ApplyIcon();
        }
        break;
      default:
        break;
    }
  }
  return result;
}

HWND TrayManagerPlugin::GetMainWindow() {
  return ::GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT);
}

void TrayManagerPlugin::Destroy(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  Shell_NotifyIcon(NIM_DELETE, &nid);
  DestroyIcon(nid.hIcon);
  tray_icon_setted = false;

  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::SetIcon(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  std::string iconPath =
      std::get<std::string>(args.at(flutter::EncodableValue("iconPath")));

  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;

  if (nid.hIcon != nullptr) {
    DestroyIcon(nid.hIcon);
  }

  nid.hIcon = static_cast<HICON>(
      LoadImage(nullptr, (LPCWSTR)(converter.from_bytes(iconPath).c_str()),
                IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
                GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE));

  _ApplyIcon();

  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::_ApplyIcon() {
  if (tray_icon_setted) {
    Shell_NotifyIcon(NIM_MODIFY, &nid);
  } else {
    HICON hIconBackup = nid.hIcon;
    WCHAR szTipBackup[128];
    StringCchCopy(szTipBackup, _countof(szTipBackup), nid.szTip);

    ZeroMemory(&nid, sizeof(NOTIFYICONDATA));
    nid.cbSize = sizeof(NOTIFYICONDATA);
    nid.hWnd = GetMainWindow();
    nid.uID = 1;
    nid.hIcon = hIconBackup;
    StringCchCopy(nid.szTip, _countof(nid.szTip), szTipBackup);
    nid.uCallbackMessage = WM_MYMESSAGE;
    nid.uFlags = NIF_MESSAGE | NIF_ICON;
    if (nid.szTip[0] != '\0') {
      nid.uFlags |= NIF_TIP;
    }
    Shell_NotifyIcon(NIM_ADD, &nid);
  }

  niif.cbSize = sizeof(NOTIFYICONIDENTIFIER);
  niif.hWnd = nid.hWnd;
  niif.uID = nid.uID;
  niif.guidItem = GUID_NULL;

  tray_icon_setted = true;
}

void TrayManagerPlugin::SetToolTip(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  std::string toolTip =
      std::get<std::string>(args.at(flutter::EncodableValue("toolTip")));

  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  StringCchCopy(nid.szTip, _countof(nid.szTip),
                converter.from_bytes(toolTip).c_str());
  Shell_NotifyIcon(NIM_MODIFY, &nid);

  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::SetContextMenu(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  _ClearMenu();
  _ConfigureControls(args);
  _CreateMenu(hMenu, std::get<flutter::EncodableMap>(
                         args.at(flutter::EncodableValue("menu"))));

  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::PopUpContextMenu(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  bool bringAppToFront =
      std::get<bool>(args.at(flutter::EncodableValue("bringAppToFront")));

  HWND hWnd = GetMainWindow();

  double x, y;

  // RECT rect;
  // Shell_NotifyIconGetRect(&niif, &rect);

  // x = rect.left + ((rect.right - rect.left) / 2);
  // y = rect.top + ((rect.bottom - rect.top) / 2);

  POINT cursorPos;
  GetCursorPos(&cursorPos);
  x = cursorPos.x;
  y = cursorPos.y;

  if (bringAppToFront) {
    SetForegroundWindow(hWnd);
  }
  TrackPopupMenu(hMenu, TPM_BOTTOMALIGN | TPM_LEFTALIGN, static_cast<int>(x),
                 static_cast<int>(y), 0, hWnd, NULL);
  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::GetBounds(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  if (!tray_icon_setted) {
    result->Success();
    return;
  }

  double devicePixelRatio =
      std::get<double>(args.at(flutter::EncodableValue("devicePixelRatio")));

  RECT rect;
  Shell_NotifyIconGetRect(&niif, &rect);
  flutter::EncodableMap resultMap = flutter::EncodableMap();

  double x = rect.left / devicePixelRatio * 1.0f;
  double y = rect.top / devicePixelRatio * 1.0f;
  double width = (rect.right - rect.left) / devicePixelRatio * 1.0f;
  double height = (rect.bottom - rect.top) / devicePixelRatio * 1.0f;

  resultMap[flutter::EncodableValue("x")] = flutter::EncodableValue(x);
  resultMap[flutter::EncodableValue("y")] = flutter::EncodableValue(y);
  resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
  resultMap[flutter::EncodableValue("height")] =
      flutter::EncodableValue(height);

  result->Success(flutter::EncodableValue(resultMap));
}

void TrayManagerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("destroy") == 0) {
    Destroy(method_call, std::move(result));
  } else if (method_call.method_name().compare("setIcon") == 0) {
    SetIcon(method_call, std::move(result));
  } else if (method_call.method_name().compare("setToolTip") == 0) {
    SetToolTip(method_call, std::move(result));
  } else if (method_call.method_name().compare("setContextMenu") == 0) {
    SetContextMenu(method_call, std::move(result));
  } else if (method_call.method_name().compare("popUpContextMenu") == 0) {
    PopUpContextMenu(method_call, std::move(result));
  } else if (method_call.method_name().compare("getBounds") == 0) {
    GetBounds(method_call, std::move(result));
  } else {
    result->NotImplemented();
  }
}

}  // namespace

void TrayManagerPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  TrayManagerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
