"""`macshell-helper store ...` — the package backend behind the App Store app (AppStore.qml).

  store search QUERY        apps matching QUERY
  store list                installed apps
  store updates             installed apps with a newer version
  store install ID SOURCE   install (SOURCE as printed by search: winget | msstore | flathub ...)
  store uninstall ID
  store update ID           (ID "--all" updates everything)

Output, one app per line (tab separated), which AppStore.qml parses:
  A:<id>\t<name>\t<version>\t<available version or "">\t<source>
Actions print nothing and exit 0; on failure the last useful line goes to stderr.

Backends: windows = winget (built into Windows 10/11; source "msstore" is the Microsoft Store),
linux = flatpak, mock = a JSON file (tests, the reference rig).
"""
import json
import os
import re
import subprocess
import sys

WINGET_FLAGS = ["--accept-source-agreements", "--disable-interactivity"]


class Fail(Exception):
    pass


def fmt(apps):
    return "".join("A:%s\t%s\t%s\t%s\t%s\n" % (a["id"], a["name"], a.get("version", ""),
                                                 a.get("available", ""), a.get("source", ""))
                   for a in apps)


# ── winget ──────────────────────────────────────────────────────────────────────────────
def _clean(text):
    """winget draws spinners and progress bars with \\r and \\b; keep what's left on each line."""
    out = []
    for line in text.replace("\r\n", "\n").split("\n"):
        line = line.split("\r")[-1]
        while "\b" in line:
            line = re.sub(r"[^\b]?\b", "", line, count=1)
        out.append(line.rstrip())
    return out


def parse_winget_table(text, extra_key):
    """Parse winget's fixed-width table without relying on its (localized) header words.

    The header row sits just above the row of dashes; each column starts where a header word
    starts. Columns are Name, Id, Version, [extra], Source, where the optional extra column is
    "Match" for search and "Available" for list/upgrade.
    """
    lines = _clean(text)
    dash = next((i for i, l in enumerate(lines) if re.fullmatch(r"-{10,}", l.strip())), None)
    if dash is None or dash == 0:
        return []
    header = lines[dash - 1]
    # winget pads columns to their widest cell plus one space, so every header word starts a column
    starts = [m.start() for m in re.finditer(r"\S+", header)]
    if len(starts) < 3:
        return []
    keys = ["name", "id", "version"] + ([extra_key] if len(starts) >= 5 else []) + ["source"]
    keys = keys[:len(starts)]
    apps = []
    for line in lines[dash + 1:]:
        if not line.strip():
            break
        # a table row has a column gap before every column it reaches; footers ("2 upgrades
        # available.", in any language) don't line up
        if any(s < len(line) and line[s - 1] != " " for s in starts[1:]):
            break
        cells = []
        for i, s in enumerate(starts):
            e = starts[i + 1] if i + 1 < len(starts) else None
            cells.append(line[s:e].strip() if s < len(line) else "")
        app = dict(zip(keys, cells))
        if app.get("id") and " " not in app["id"]:
            app.setdefault("source", "")
            apps.append(app)
    return apps


class Winget:
    def _run(self, *args, check=True):
        flags = 0x08000000 if os.name == "nt" else 0          # CREATE_NO_WINDOW
        r = subprocess.run(["winget", *args], capture_output=True, encoding="utf-8",
                           errors="replace", creationflags=flags)
        if check and r.returncode != 0:
            lines = [l for l in _clean(r.stdout + "\n" + r.stderr) if l.strip()]
            raise Fail(lines[-1] if lines else "winget failed (%d)" % r.returncode)
        return r.stdout

    def search(self, q):
        return parse_winget_table(self._run("search", q, *WINGET_FLAGS, check=False), "match")

    def list(self):
        return parse_winget_table(self._run("list", *WINGET_FLAGS, check=False), "available")

    def updates(self):
        return parse_winget_table(self._run("upgrade", *WINGET_FLAGS, check=False), "available")

    def install(self, id_, source):
        self._run("install", "--id", id_, "--exact", *(["--source", source] if source else []),
                  "--silent", "--accept-package-agreements", *WINGET_FLAGS)

    def uninstall(self, id_):
        self._run("uninstall", "--id", id_, "--exact", "--silent", *WINGET_FLAGS)

    def update(self, id_):
        if id_ == "--all":
            self._run("upgrade", "--all", "--silent", "--accept-package-agreements", *WINGET_FLAGS)
        else:
            self._run("upgrade", "--id", id_, "--exact", "--silent", "--accept-package-agreements",
                      *WINGET_FLAGS)


# ── flatpak ─────────────────────────────────────────────────────────────────────────────
class Flatpak:
    COLS = "--columns=name,application,version,origin"

    def _rows(self, *args):
        r = subprocess.run(["flatpak", *args], capture_output=True, text=True)
        apps = []
        for line in r.stdout.splitlines():
            f = line.split("\t")
            if len(f) >= 4 and f[1]:
                apps.append({"name": f[0], "id": f[1], "version": f[2], "source": f[3].split(",")[0]})
        return apps

    def _act(self, *args):
        r = subprocess.run(["flatpak", *args, "-y", "--noninteractive"], capture_output=True, text=True)
        if r.returncode != 0:
            lines = [l for l in (r.stderr + r.stdout).splitlines() if l.strip()]
            raise Fail(lines[-1] if lines else "flatpak failed")

    def search(self, q):     return self._rows("search", "--columns=name,application,version,remotes", q)
    def list(self):          return self._rows("list", "--app", self.COLS)

    def updates(self):
        apps = self._rows("remote-ls", "--updates", "--app", self.COLS)
        for a in apps:
            a["available"] = a["version"]
        return apps

    def install(self, id_, source): self._act("install", *([source] if source else []), id_)
    def uninstall(self, id_):       self._act("uninstall", id_)
    def update(self, id_):          self._act("update", *([] if id_ == "--all" else [id_]))


# ── mock ────────────────────────────────────────────────────────────────────────────────
class Mock:
    CATALOG = [
        {"id": "Mozilla.Firefox", "name": "Mozilla Firefox", "version": "131.0", "source": "winget"},
        {"id": "Discord.Discord", "name": "Discord", "version": "1.0.9165", "source": "winget"},
        {"id": "Spotify.Spotify", "name": "Spotify", "version": "1.2.48", "source": "winget"},
        {"id": "Valve.Steam", "name": "Steam", "version": "2.10.91", "source": "winget"},
        {"id": "Microsoft.VisualStudioCode", "name": "Visual Studio Code", "version": "1.95.0", "source": "winget"},
        {"id": "VideoLAN.VLC", "name": "VLC media player", "version": "3.0.21", "source": "winget"},
        {"id": "9NKSQGP7F2NH", "name": "WhatsApp", "version": "Unknown", "source": "msstore"},
        {"id": "9WZDNCRFJ3TJ", "name": "Netflix", "version": "Unknown", "source": "msstore"},
    ]

    def __init__(self, path):
        self.path = path
        try:
            with open(path, encoding="utf-8") as fh:
                self.s = json.load(fh)
        except (OSError, ValueError):
            self.s = {}
        self.s.setdefault("installed", {"Mozilla.Firefox": "130.0", "VideoLAN.VLC": "3.0.21"})

    def _save(self):
        with open(self.path, "w", encoding="utf-8") as fh:
            json.dump(self.s, fh, indent=2)

    def _app(self, id_):
        return next((dict(a) for a in self.CATALOG if a["id"] == id_), None)

    def search(self, q):
        q = q.lower()
        return [dict(a) for a in self.CATALOG if q in a["name"].lower() or q in a["id"].lower()]

    def list(self):
        out = []
        for id_, ver in self.s["installed"].items():
            a = self._app(id_) or {"id": id_, "name": id_, "source": "winget"}
            if ver != a.get("version"):
                a["available"] = a.get("version", "")
            a["version"] = ver
            out.append(a)
        return out

    def updates(self):  return [a for a in self.list() if a.get("available")]

    def install(self, id_, source):
        a = self._app(id_)
        if not a:
            raise Fail("No package found matching input criteria.")
        self.s["installed"][id_] = a["version"]
        self._save()

    def uninstall(self, id_):
        if self.s["installed"].pop(id_, None) is None:
            raise Fail("No installed package found matching input criteria.")
        self._save()

    def update(self, id_):
        for i in list(self.s["installed"]) if id_ == "--all" else [id_]:
            a = self._app(i)
            if a:
                self.s["installed"][i] = a["version"]
        self._save()


def backend(name, mock_path):
    if name == "windows":
        return Winget()
    if name == "linux":
        return Flatpak()
    return Mock(mock_path)


def main(argv, name, mock_path):
    be = backend(name, mock_path)
    a = argv + ["", ""]
    try:
        if a[0] == "search":      sys.stdout.write(fmt(be.search(" ".join(argv[1:]))))
        elif a[0] == "list":      sys.stdout.write(fmt(be.list()))
        elif a[0] == "updates":   sys.stdout.write(fmt(be.updates()))
        elif a[0] == "install":   be.install(a[1], a[2])
        elif a[0] == "uninstall": be.uninstall(a[1])
        elif a[0] == "update":    be.update(a[1] or "--all")
        else:
            raise Fail("macshell-helper: unknown store command: %s" % " ".join(argv))
    except Fail as f:
        print(str(f), file=sys.stderr)
        return 1
    return 0
