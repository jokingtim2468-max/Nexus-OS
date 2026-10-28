"""Rebuild our MacBar.qml / MacDock.qml from pristine upstream (vendor/MacShell) + every patch.

    python compat/patches/apply_all.py           # regenerate
    python compat/patches/apply_all.py --check   # verify our copy == upstream + patches

Only these two files are patched; everything else in macshell/ is either upstream unchanged or
our own new files (AppStore.qml, assets/appstore/, ...).
"""
import filecmp
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import net_bt_windows  # noqa: E402
import freeform_apps   # noqa: E402

UPSTREAM = os.path.join(HERE, "..", "..", "..", "vendor", "MacShell", "MacShell")
OURS = net_bt_windows.ROOT
FILES = ["MacBar.qml", "MacDock.qml"]
PATCHES = [net_bt_windows.EDITS, freeform_apps.EDITS]


def build(dest):
    for f in FILES:
        shutil.copy(os.path.join(UPSTREAM, f), os.path.join(dest, f))
    old = net_bt_windows.ROOT
    net_bt_windows.ROOT = dest
    try:
        return all(net_bt_windows.apply(edits_by_file=e) for e in PATCHES)
    finally:
        net_bt_windows.ROOT = old


def main(check):
    tmp = tempfile.mkdtemp()
    if not build(tmp):
        print("a patch no longer applies to upstream")
        return 1
    if check:
        same = all(filecmp.cmp(os.path.join(tmp, f), os.path.join(OURS, f), shallow=False) for f in FILES)
        print("up to date" if same else "macshell/ differs from upstream + patches")
        return 0 if same else 1
    for f in FILES:
        shutil.copy(os.path.join(tmp, f), os.path.join(OURS, f))
    print("regenerated", ", ".join(FILES))
    return 0


if __name__ == "__main__":
    sys.exit(main("--check" in sys.argv))
