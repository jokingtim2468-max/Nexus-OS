"""Defaults for first launch. After that, everything lives in Settings
(%APPDATA%\\MacShellWin\\settings.json) and is edited from the Settings app.

A dock path starting with "macshell:" opens a built-in panel instead of a program.
"""

DOCK_APPS = [
    {"name": "Explorer", "path": r"C:\Windows\explorer.exe", "glyph": "📁"},
    {"name": "Terminal", "path": "wt.exe", "glyph": "⌨"},
    {"name": "Browser", "path": "https://duckduckgo.com", "glyph": "🌐"},
    {"name": "Settings", "path": "macshell:settings", "glyph": "⚙"},
]

# Commands the Control Center toggles run. {state} -> on/off,
# {connect} -> connect/disconnect.
HOOKS = {
    "mullvad": ["mullvad", "{connect}"],
    "tor": ["python", r"C:\scripts\tor_route.py", "{state}"],
}

WORKSPACES = 5
