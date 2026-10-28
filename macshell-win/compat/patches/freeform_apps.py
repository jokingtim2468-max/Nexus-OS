"""Patch: hook FreeForm's own apps into MacShell's menus.

Applied after net_bt_windows.py (same engine: exact find -> replace, each must match once).

1. Apple menu: "App Store..." under System Settings, like macOS (opens AppStore.qml).

    python compat/patches/freeform_apps.py          # apply (idempotent)
    python compat/patches/freeform_apps.py --check  # verify it is applied
"""
import sys

from net_bt_windows import apply

EDITS = {
    "MacBar.qml": [
        ('''            m.push(mi("System Settings\\u2026", "", function () { root.openSettings(); }));
            m.push(msep());
            m.push(mi("Lock Screen", "", function () { root.lockScreen(); }));''',
         '''            m.push(mi("System Settings\\u2026", "", function () { root.openSettings(); }));
            m.push(mi("App Store\\u2026", "", function () { if (hub && hub.appStore) hub.appStore.open(""); }));
            m.push(msep());
            m.push(mi("Lock Screen", "", function () { root.lockScreen(); }));'''),
    ],
}

if __name__ == "__main__":
    sys.exit(0 if apply(check="--check" in sys.argv, edits_by_file=EDITS) else 1)
