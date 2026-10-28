"""python -m unittest compat/helper/test_apps.py"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apps as A  # noqa: E402


class Entries(unittest.TestCase):
    def test_entry_matches_our_window_ids(self):
        t = A.entry({"name": "Firefox", "launch": r"C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Firefox.lnk",
                     "target": r"C:\Program Files\Mozilla Firefox\firefox.exe", "icon": r"C:\icons\firefox.png"})
        self.assertIn("StartupWMClass=firefox\n", t)                         # == Toplevel.appId on Windows
        self.assertIn('Exec=explorer.exe "C:' + "\\" * 4 + 'ProgramData', t)   # quoted Exec: 4 backslashes = 1
        self.assertIn("Icon=C:/icons/firefox.png", t)

    def test_store_app_has_no_wm_class(self):
        t = A.entry({"name": "Spotify", "launch": "shell:AppsFolder\\SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify", "target": "", "icon": ""})
        self.assertNotIn("StartupWMClass", t)
        self.assertNotIn("Icon=", t)

    def test_sync_removes_uninstalled_apps_only(self):
        d = tempfile.mkdtemp()
        open(os.path.join(d, "org.gnome.Mine.desktop"), "w").close()        # not ours: kept
        A.write_all([{"name": "A", "launch": "a.lnk"}, {"name": "B", "launch": "b.lnk"}], d)
        A.write_all([{"name": "A", "launch": "a.lnk"}], d)
        self.assertEqual(sorted(os.listdir(d)), ["ff-a.desktop", "org.gnome.Mine.desktop"])


if __name__ == "__main__":
    unittest.main()
