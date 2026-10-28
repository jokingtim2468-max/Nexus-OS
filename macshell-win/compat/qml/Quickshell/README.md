# Windows stand-ins for Linux-only Quickshell modules

MacShell imports `Quickshell.Hyprland` and `Quickshell.Services.{Mpris,Pipewire,UPower,SystemTray,Notifications}`.
Those modules talk to Hyprland, D-Bus and PipeWire, which don't exist on Windows, so our Windows
`qs.exe` is built without them. These pure-QML modules have the same names and the parts of the API
MacShell uses, backed by Windows:

| Module | Windows backend |
|---|---|
| Hyprland | `ToplevelManager` (our Win32 window list) + `Quickshell.screens`; window-rule dispatches are no-ops (MacShell's windows are normal Windows windows) |
| Mpris | `compat/helper/media.ps1` — Windows media session API (GSMTC): Spotify, browsers, VLC… |
| Pipewire | `compat/helper/audio.ps1` — Core Audio default speaker / microphone volume + mute |
| UPower | `compat/helper/power.ps1` — Win32_Battery |
| SystemTray | empty for now (tray mirroring is a later step) |
| Notifications | a server that never receives (Windows toasts stay Windows'; mirroring is a later step) |

Only used on Windows: the FreeForm launcher puts this folder on `QML_IMPORT_PATH` and sets
`FREEFORM_HELPER` to `compat/helper`. On Linux the real modules are used.
