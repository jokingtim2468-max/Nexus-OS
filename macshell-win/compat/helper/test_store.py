"""Tests for the App Store backend:  python -m unittest compat/helper/test_store.py"""
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store as S  # noqa: E402

# Real `winget search vlc` output shape: spinner junk, header, dashes, fixed-width rows.
SEARCH = ("   - \r   \\ \r\r"
          "Name                     Id                     Version Match          Source\n"
          "------------------------------------------------------------------------------\n"
          "VLC                      XPDM1ZW6815MQM         Unknown                msstore\n"
          "VLC media player         VideoLAN.VLC           3.0.21  Moniker: vlc   winget\n"
          "VLC UWP                  VideoLAN.VLC.UWP       3.2.1   Tag: vlc       winget\n")

# German Windows: other header words, same layout.
LIST_DE = ("Name                      ID                         Version     Verfügbar   Quelle\n"
           "-------------------------------------------------------------------------------------\n"
           "Mozilla Firefox (x64 de)  Mozilla.Firefox            130.0       131.0       winget\n"
           "Steam                     Valve.Steam                2.10.91.91              winget\n"
           "2 Aktualisierungen verfügbar.\n")


class WingetParser(unittest.TestCase):
    def test_search(self):
        apps = S.parse_winget_table(SEARCH, "match")
        self.assertEqual([a["id"] for a in apps], ["XPDM1ZW6815MQM", "VideoLAN.VLC", "VideoLAN.VLC.UWP"])
        self.assertEqual(apps[0]["source"], "msstore")
        self.assertEqual(apps[1]["version"], "3.0.21")
        self.assertEqual(apps[1]["name"], "VLC media player")

    def test_list_any_language(self):
        apps = S.parse_winget_table(LIST_DE, "available")
        self.assertEqual(len(apps), 2)
        self.assertEqual(apps[0]["available"], "131.0")
        self.assertEqual(apps[1]["available"], "")
        self.assertEqual(apps[1]["version"], "2.10.91.91")

    def test_no_results(self):
        self.assertEqual(S.parse_winget_table("No package found matching input criteria.\n", "match"), [])


def run(argv, path):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = S.main(argv, "mock", path)
    return code, out.getvalue(), err.getvalue()


class MockStore(unittest.TestCase):
    def setUp(self):
        self.path = os.path.join(tempfile.mkdtemp(), "store.json")

    def test_install_update_uninstall(self):
        _, out, _ = run(["search", "discord"], self.path)
        self.assertEqual(out, "A:Discord.Discord\tDiscord\t1.0.9165\t\twinget\n")
        self.assertEqual(run(["install", "Discord.Discord", "winget"], self.path)[0], 0)
        self.assertIn("A:Discord.Discord", run(["list"], self.path)[1])
        _, out, _ = run(["updates"], self.path)
        self.assertEqual(out, "A:Mozilla.Firefox\tMozilla Firefox\t130.0\t131.0\twinget\n")
        run(["update", "--all"], self.path)
        self.assertEqual(run(["updates"], self.path)[1], "")
        self.assertEqual(run(["uninstall", "Discord.Discord"], self.path)[0], 0)
        self.assertNotIn("Discord", run(["list"], self.path)[1])

    def test_errors_go_to_stderr(self):
        code, _, err = run(["install", "Nope.Nope", "winget"], self.path)
        self.assertEqual(code, 1)
        self.assertIn("No package found", err)


if __name__ == "__main__":
    unittest.main()
