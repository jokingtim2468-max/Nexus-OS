"""Tests for the Wallpaper Engine backend:  python -m unittest compat/helper/test_wallpaper_engine.py"""
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wallpaper_engine as W  # noqa: E402


def project(d, **p):
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "project.json"), "w", encoding="utf-8") as fh:
        json.dump(p, fh)
    if p.get("preview"):
        open(os.path.join(d, p["preview"]), "wb").close()


class Library(unittest.TestCase):
    def setUp(self):
        self.steam = tempfile.mkdtemp()
        self.second = tempfile.mkdtemp()                       # another drive's library
        os.makedirs(os.path.join(self.steam, "steamapps"))
        with open(os.path.join(self.steam, "steamapps", "libraryfolders.vdf"), "w") as fh:
            fh.write('"libraryfolders"\n{\n "0" { "path" "%s" }\n "1" { "path" "%s" }\n}\n'
                     % (self.steam.replace("\\", "\\\\"), self.second.replace("\\", "\\\\")))
        we = os.path.join(self.second, "steamapps", "common", "wallpaper_engine")
        os.makedirs(we)
        open(os.path.join(we, "wallpaper64.exe"), "wb").close()
        ws = os.path.join(self.steam, "steamapps", "workshop", "content", "431960")
        project(os.path.join(ws, "111"), title="Neon City", type="scene", preview="preview.gif", file="scene.json")
        project(os.path.join(ws, "222"), title="Rain\twindow", type="Video", preview="preview.jpg", file="rain.mp4")
        project(os.path.join(ws, "333"), title="Broken", type="preset")          # not a wallpaper
        project(os.path.join(we, "projects", "myprojects", "mine"), title="My Own", type="web", file="index.html")

    def test_finds_every_library_and_the_install(self):
        libs = W.libraries(self.steam)
        self.assertEqual(len(libs), 2)
        self.assertTrue(W.exe_path(W.install_dir(libs)).endswith("wallpaper64.exe"))

    def test_lists_wallpapers_sorted_with_previews(self):
        libs = W.libraries(self.steam)
        items = W.wallpapers(libs, W.install_dir(libs))
        self.assertEqual([w["title"] for w in items], ["My Own", "Neon City", "Rain window"])
        self.assertTrue(items[1]["preview"].endswith("preview.gif"))
        self.assertEqual(items[2]["type"], "video")
        self.assertEqual(items[0]["preview"], "")                             # none given
        self.assertTrue(items[1]["file"].endswith(os.path.join("111", "project.json")))

    def test_list_command_format(self):
        out = io.StringIO()
        with mock.patch.dict(os.environ, {"MACSHELL_WE_STEAM": self.steam}), redirect_stdout(out):
            self.assertEqual(W.main(["list"]), 0)
        first = out.getvalue().split("\n")[0].split("\t")
        self.assertEqual(first[0], "W:mine")
        self.assertEqual(first[2], "web")
        self.assertEqual(len(first), 5)

    def test_apply_uses_the_documented_cli(self):
        with mock.patch.object(W, "_running", return_value=True), \
             mock.patch("subprocess.run", return_value=mock.Mock(returncode=0, stdout="", stderr="")) as run:
            W.apply_windows("C:/we/wallpaper64.exe", "C:/w/project.json", "1")
        self.assertEqual(run.call_args[0][0][1:], ["-control", "openWallpaper", "-file", "C:/w/project.json",
                                                   "-monitor", "1"])


if __name__ == "__main__":
    unittest.main()
