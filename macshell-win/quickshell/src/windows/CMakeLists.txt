# Windows backends. Mirrors ../x11 for PanelWindow (Win32 + AppBar), and registers as
# Quickshell.Wayland so shells written for Wayland (MacShell) import it unchanged:
# ToplevelManager from Win32 windows, WlrLayershell mapped onto PanelWindow, ScreencopyView.
qt_add_library(quickshell-windows STATIC
	panel_window.cpp
	toplevel.cpp
	layershell.cpp
	hotkey.cpp
)

qt_add_qml_module(quickshell-windows
	URI Quickshell.Wayland
	VERSION 0.1
	DEPENDENCIES QtQuick
)

qs_add_module_deps_light(quickshell-windows quickshell-core quickshell-window)

install_qml_module(quickshell-windows)

add_library(quickshell-windows-init OBJECT init.cpp)

target_link_libraries(quickshell-windows PRIVATE Qt::Quick shell32 user32 gdi32 dwmapi)
target_link_libraries(quickshell-windows-init PRIVATE Qt::Quick Qt::Qml dwmapi)

qs_module_pch(quickshell-windows SET large)

target_link_libraries(quickshell PRIVATE quickshell-windowsplugin quickshell-windows-init)
