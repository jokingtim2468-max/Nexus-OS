"""python -m unittest compat/helper/test_theme.py"""
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import theme as T  # noqa: E402


class Spicetify(unittest.TestCase):
    def test_every_preset_has_a_scheme(self):
        ini = T.spicetify_color_ini()
        for n in T.PRESETS:
            self.assertIn("[%s]" % n, ini)
        self.assertIn("sidebar            = 000000", ini)

    def test_without_spicetify_spotify_is_left_alone(self):
        with mock.patch("shutil.which", return_value=None):
            self.assertIn("isn't installed", T.apply_spotify("black"))

    def test_with_spicetify_writes_theme_and_applies(self):
        d = tempfile.mkdtemp()
        ok = mock.Mock(returncode=0, stdout="", stderr="")
        with mock.patch("shutil.which", return_value="/bin/spicetify"), \
             mock.patch.object(T, "spicetify_dir", return_value=d), \
             mock.patch("subprocess.run", return_value=ok) as run:
            self.assertIn("themed", T.apply_spotify("graphite"))
        self.assertTrue(os.path.isfile(os.path.join(d, "Themes", "FreeForm", "color.ini")))
        self.assertEqual(run.call_args_list[0][0][0][1:], ["config", "current_theme", "FreeForm", "color_scheme", "graphite"])


if __name__ == "__main__":
    unittest.main()
