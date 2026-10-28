"""python -m unittest compat/helper/test_wallpaper.py"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wallpaper as W  # noqa: E402


class Scan(unittest.TestCase):
    def test_matches_macshells_find_output(self):
        d = tempfile.mkdtemp()
        for n in ["b10.jpg", "b2.PNG", "notes.txt", "sub/clip.mp4", "sub/deeper/x.webp", "sub/deeper/deepest/no.jpg"]:
            os.makedirs(os.path.dirname(os.path.join(d, n)), exist_ok=True)
            open(os.path.join(d, n), "w").close()
        out = W.scan(d, "0", [os.path.join(d, "b2.PNG"), "/nope.jpg"]).splitlines()
        names = [l.split("/")[-1] for l in out if l.startswith("A:")]
        self.assertEqual(names, ["b2.PNG", "b10.jpg", "clip.mp4", "x.webp"])      # natural sort, 3 levels
        self.assertEqual([l for l in out if l.startswith("F:")], ["F:" + os.path.join(d, "b2.PNG")])

    def test_creates_the_default_folder(self):
        d = os.path.join(tempfile.mkdtemp(), "Wallpapers")
        W.scan(d, "1", [])
        self.assertTrue(os.path.isdir(d))


if __name__ == "__main__":
    unittest.main()
