# Porting MacShell to Windows — the full map

Source taken in full from https://github.com/0-ss/MacShell (MIT, © 2026 Rickky):

- `macshell/` — the shell (all 40 QML files, 7 shaders, fonts, assets) — **our editable copy**
- `maclock/` — the lock screen
- `../vendor/MacShell` — pristine upstream (git submodule) to diff against / pull updates from

## Strategy: run MacShell's own QML, replace only the Linux layer

MacShell is QML on Qt 6. Qt's QML engine runs on Windows, so the UI code is kept
**as is**. What doesn't exist on Windows is (1) the `Quickshell` QML modules it
imports and (2) the ~27 Linux command-line tools it shells out to. We provide
both as a **Windows compatibility layer** (`compat/`, PyQt6), so every feature is
MacShell's real implementation, not a redraw.

### Reference: the real MacShell, running

`tools/reference/run-macshell.sh` launches the **unmodified upstream MacShell** in
real Quickshell 0.3.2 (headless sway + Mesa software GL, Linux + Nix) and drives it
through MacShell's own IPC (`controlcenter`, `spotlight`, `settings pane <id>`,
`clock`, `wallpapers`, …). Every Windows screen is compared against it. Verified:
menu bar, Dock, Control Center (Liquid Glass shader compiles and renders),
Spotlight, the System Settings window with all its panes, and the Clock app.

What the run also confirmed for the port:
- The Settings window (Wi-Fi … About, ~23 panes) lives in `MacDock.qml`, so
  "every setting" comes straight from MacShell's code.
- 26 of 40 components import only `QtQuick` and need no changes.
- All 7 shaders already contain **HLSL** (Direct3D) in their `.qsb` files.

## Done so far

### Network & Bluetooth (patch `compat/patches/net_bt_windows.py`, backend `compat/helper/`)
- All 14 `nmcli` / `bluetoothctl` / `rfkill` call sites in `MacBar.qml` and `MacDock.qml`
  now call **`macshell-helper`**, which prints the exact text MacShell already parses — so
  MacShell's UI and parsing code are unchanged. Backends: **Windows** (`winnet.ps1`: WinRT
  Radio / WiFiAdapter / NetworkInformation / Bluetooth + NetAdapter / VPN cmdlets — language
  independent, no admin except Ethernet on/off), **Linux** (MacShell's original commands,
  verbatim), **mock** (tests and the reference rig).
- Ethernet: **cable icon** (RJ45 plug + cord, drawn in MacShell's Glyph style) and the Windows
  rule — wired connected ⇒ cable icon, even if Wi-Fi is also joined. Ethernet rows in the menu
  use it too.
- The Wi-Fi menu gets a **Bluetooth on/off row** (shows the connected device), using
  MacShell's own `PSwitch` and `toggleBt()`.
- **Bluetooth menu = remembered devices only** (bar icon, the Bluetooth row in the Wi-Fi menu —
  click the row, the switch still toggles — and the Control Center page). Finding and pairing new
  devices lives in **Settings → Bluetooth → Nearby Devices** (scan, Connect = pair), which also
  gets a **Forget** button per remembered device. Windows backend: WinRT discovery of classic + LE
  devices (`btscan`, cached for `bt status`), `DeviceInformation.Pairing.PairAsync` (`btpair`),
  `UnpairAsync` (`btforget`). IPC `network bluetooth` opens the Bluetooth menu.
- New IPC `network toggle|open|close` (same pattern as `controlcenter`) — for a Win+A hotkey.
- Verified in real Quickshell with the mock backend (wired → cable; join Wi-Fi → ✓ in list;
  Bluetooth off → row + bar icon update). `winnet.ps1` itself still needs a run on real Windows.
- Known Windows limit: there's no public API to force a *paired* Bluetooth device to
  connect/disconnect (Windows reconnects them itself); planned: `BluetoothSetServiceState`
  for headphones, like ToothTray.

### Quickshell itself on Windows (`quickshell/`, CI: `.github/workflows/quickshell-windows.yml`)
Instead of re-implementing Quickshell's QML modules in Python, we build **Quickshell itself** as a
native Windows `qs.exe` (C++/Qt 6, MSYS2 UCRT64 toolchain). MacShell then runs unmodified-as-possible
on the same engine it runs on Linux, at native speed and without WSL or a VM — the lowest resource
option. Done so far:
- Build profile: Wayland, X11, i3, D-Bus services (tray, MPRIS, UPower, notifications, Bluetooth,
  NetworkManager), PipeWire, PAM, polkit, greetd, crash handler, jemalloc and libdrm default **OFF**
  on Windows. Each gets a Windows backend later (table below).
- POSIX → Windows in core/launch/io:
  | Linux | Windows |
  |---|---|
  | DRM GPU info (`debuginfo.cpp`) | OS name/version via `QSysInfo` |
  | `memfd_create` early logs, `sendfile` copy (`logging.cpp`) | anonymous `QTemporaryFile`, Qt copy |
  | `fcntl` instance lock + `F_GETLK` liveness (`paths.cpp`) | pid stored in the lock file, `OpenProcess` liveness (`platform_win.cpp`) |
  | `fcntl` tooling lock (`toolsupport.cpp`) | session-local named mutex |
  | `/run/user/<uid>` runtime dir | `%TEMP%` |
  | `fork`+`setsid` for `--daemonize` (`command.cpp`) | `QProcess::startDetached` copy |
  | `kill(pid, sig)` in `Process.signal()` | `terminate()` / `kill()` |
  | Unix socket IPC (`qs ipc call …`) | unchanged — `QLocalSocket` is a named pipe on Windows |
- CI builds `qs.exe` plus the Qt runtime DLLs on `windows-latest` (free for public repos) and
  uploads it as the `qs-windows-x64` artifact.

Next in this layer: a Windows `PanelWindow` backend (frameless top-most window + AppBar to reserve
the bar/dock area), then `Hyprland`/`ToplevelManager` on Win32 windows and virtual desktops, and
`DesktopEntries` from Start Menu shortcuts (dock pinning + running apps).

### Still Linux-only underneath
Pinning already exists in MacShell (right-click → **Keep in Dock** / **Remove from Dock**, drag
to reorder, `pinned.json`), but on Windows it needs the app list and running windows — the
host layer below (`DesktopEntries` → Start Menu shortcuts, `ToplevelManager`/`Hyprland` → Win32
windows). That host is also what gets the bar and dock on screen on Windows at all.

## 1. Quickshell modules → Windows

| Quickshell API (uses) | Used for | Windows replacement |
|---|---|---|
| `ShellRoot`, `Scope`, `Variants`, `LazyLoader`, `Quickshell.screens` (23) | app root, per-monitor instances | plain QML objects; `Qt.application.screens` |
| `PanelWindow` + `WlrLayershell` / `WlrLayer.*` / `ExclusionMode` (10/28) | bar, dock, widget layer, overlays | frameless top-level `QQuickWindow` + Win32: always-on-top/bottom z-order, **AppBar (`SHAppBarMessage`) to reserve screen space** (fixes maximized windows), click-through via `WS_EX_TRANSPARENT` |
| `Process` + `StdioCollector`/`SplitParser` (60/51), `Quickshell.execDetached` (56) | every system action | `compat.Process`: same API, routes each command through a **command translator** (section 2) |
| `FileView`, `JsonAdapter` (8) | settings / pinned apps JSON | QFile-backed file object; paths moved from `~/.config/...` to `%APPDATA%\MacShell\...` |
| `IpcHandler` (13) | `qs ipc call spotlight toggle`, lock, etc. | local named pipe + `macshell.exe ipc …` CLI |
| `Quickshell.env`, `Quickshell.iconPath` (30/10) | env vars, app icons | `os.environ`; icon lookup from Start Menu `.lnk` / exe icons (`SHGetFileInfo`) |
| `Hyprland.*` — `dispatch`, `toplevels`, `workspaces`, `focusedMonitor`, `monitors` (≈40) | windows list, focus, workspaces, Alt+Tab | Win32 `EnumWindows`/`SetForegroundWindow`/`ShowWindow`, **Windows virtual desktops** (VirtualDesktopAccessor), `SetWinEventHook` for open/close/focus events |
| `ToplevelManager`, `ScreencopyView` (7/7) | dock window previews, glass backdrop of live windows | **DWM thumbnails** (`DwmRegisterThumbnail`) for previews; Windows.Graphics.Capture for live backdrops |
| `Pipewire.*` (≈15) | volume, mic, output/input device lists | Core Audio (pycaw: `IAudioEndpointVolume`, `IMMDeviceEnumerator`, `IPolicyConfig` to switch default device) |
| `UPower.displayDevice` | battery % / charging | `GetSystemPowerStatus` |
| `Mpris.players` | now playing, media controls | Windows `GlobalSystemMediaTransportControlsSessionManager` (WinRT, via `winsdk`) |
| `SystemTray.items` | tray icons in the bar | `Shell_NotifyIcon` tray mirroring (hardest item — Explorer owns the tray) |
| `NotificationServer` | notification center | `UserNotificationListener` (WinRT) to read Windows toasts |
| `Pam` (MacLock) | lock screen password check | `LogonUserW` against the current account; real lock via `LockWorkStation` |

## 2. Linux commands → Windows (`compat.Process` translator)

| Linux tool (uses) | Feature | Windows equivalent |
|---|---|---|
| `hyprctl` (44) | windows, monitors, dispatch, keyword | Win32 window APIs (see above) |
| `nmcli` (18) | Wi-Fi list/connect, network status | `netsh wlan` / WinRT `WiFiAdapter` |
| `bluetoothctl` (15) | Bluetooth toggle, devices | WinRT `Windows.Devices.Radios` / `Bluetooth` |
| `wpctl`, `pactl` (5) | volume, mute, devices | Core Audio (pycaw) |
| `brightnessctl` (3) | brightness | WMI `WmiMonitorBrightnessMethods` (laptops); DDC/CI for desktops |
| `hyprsunset` | Night Shift | Windows Night light registry state / gamma ramp (`SetDeviceGammaRamp`) |
| `powerprofilesctl` | power mode | `powercfg /setactive` (power plans / overlays) |
| `systemd-inhibit` | Keep Awake | `SetThreadExecutionState` |
| `systemctl` (6) | suspend / reboot / shutdown | `SetSuspendState`, `shutdown /r`, `shutdown /s` |
| `grim`, `slurp` (11) | screenshots, region select | Qt `QScreen.grabWindow` + our own region overlay |
| `wf-recorder`, `ffmpeg` (18) | screen recording | `ffmpeg -f gdigrab` / `ddagrab` (ships ffmpeg) |
| `cliphist`, `wl-copy`, `wl-paste` (34) | clipboard history (Spotlight) | our own clipboard history (`AddClipboardFormatListener`), Qt clipboard |
| `wtype`, `ydotool` (30) | type emoji / paste into apps | `SendInput` (Unicode) |
| `swww`, `awww`, `gsettings` (41) | wallpaper set / transitions / dark mode | `SystemParametersInfoW(SPI_SETDESKWALLPAPER)`; app/system dark mode registry keys |
| `notify-send` (12) | MacShell's own toasts | our notification popup (MacBar's own UI) |
| `xdg-open`, `gtk-launch` (19) | open files/URLs/apps | `os.startfile`, `.lnk` launch |
| `curl` (8) | weather, lyrics | unchanged (`curl.exe` ships with Windows 10+) |
| `inotifywait` | watch settings files | `QFileSystemWatcher` |
| `upower`, `jq`, `pkill`, `python3` | misc | native equivalents |

## 3. Order of work

1. **Compat skeleton** — `Quickshell`/`Quickshell.Io` modules, `Process` with
   pass-through + translator table, `PanelWindow` on Win32. Goal: `shell.qml`
   loads with bar + dock visible.
2. **Windows & workspaces** — `Hyprland.*` on Win32 + virtual desktops, dock
   running-app indicators, window previews, Alt+Tab.
3. **Control Center** — audio, brightness, Wi-Fi, Bluetooth, Night Shift, Keep
   Awake, power modes.
4. **Spotlight** — app search (Start Menu), clipboard history, emoji.
5. **Media & notifications** — Now Playing, notification center.
6. **Screenshots / recording / wallpaper picker.**
7. **Desktop widgets layer, Clock app, About.**
8. **MacLock.**
9. **Our branding** — FF logo replaces the Apple logo
   (`apple-logo-*.svg`, menu bar), app name, About page — then fold in the
   launcher / auto-start / tutorial already built in this folder.

Honest size: `MacBar.qml` is 9,473 lines and `MacDock.qml` 5,553; MacShell does
a lot. Steps 1–3 make it usable day to day; 4–8 complete the feature set.
