"""User config: dock apps and hooks to your existing VPN/Tor scripts.

Edit these paths freely. Hooks are plain commands run when a toggle changes.
"""

DOCK_APPS = [
    {"name": "Explorer", "path": r"C:\Windows\explorer.exe", "glyph": "📁"},
    {"name": "Terminal", "path": "wt.exe", "glyph": "⌨"},
    {"name": "Browser", "path": r"C:\Program Files\Mozilla Firefox\firefox.exe", "glyph": "🌐"},
    {"name": "Settings", "path": "ms-settings:", "glyph": "⚙"},
]

# Commands for the Control Center toggles. {state} is replaced with on/off.
HOOKS = {
    "mullvad": ["mullvad", "{connect}"],          # connect / disconnect
    "tor": ["python", r"C:\scripts\tor_route.py", "{state}"],
}

WORKSPACES = 5
