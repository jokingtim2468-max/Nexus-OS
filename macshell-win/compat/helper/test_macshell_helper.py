"""Tests for macshell-helper:  python -m unittest compat/helper/test_macshell_helper.py"""
import io
import json
import os
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import macshell_helper as H  # noqa: E402

UPSTREAM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..",
                        "vendor", "MacShell", "MacShell")


def run(argv, state_path):
    out, err = io.StringIO(), io.StringIO()
    with mock.patch.dict(os.environ, {"MACSHELL_HELPER_MOCK": state_path}, clear=False), \
            redirect_stdout(out), redirect_stderr(err):
        code = H.main(argv)
    return code, out.getvalue(), err.getvalue()


class Formats(unittest.TestCase):
    """The text must match what MacShell's QML parsers read."""

    def test_net_status_wired(self):
        t = H.fmt_net_status({"wifi_on": True, "ssid": "", "signal": 0, "ethernet_up": True}).split("\n")
        self.assertEqual(t[0], "enabled")
        self.assertEqual(t[1], "")                      # no active Wi-Fi -> MacShell shows Ethernet
        self.assertIn("eth", [x.strip() for x in t])

    def test_net_status_wifi_ssid_with_colon(self):
        t = H.fmt_net_status({"wifi_on": True, "ssid": "Cafe:2", "signal": 71, "ethernet_up": False})
        line = t.split("\n")[1]
        # MacShell: parts = line.split(":"); signal = last; ssid = middle joined, backslashes removed
        parts = line.split(":")
        self.assertEqual(parts[0], "yes")
        self.assertEqual(int(parts[-1]), 71)
        self.assertEqual(":".join(parts[1:-1]).replace("\\", ""), "Cafe:2")
        self.assertNotIn("eth", [x.strip() for x in t.split("\n")])

    def test_wifi_list(self):
        t = H.fmt_wifi_list({"saved": ["Home"], "networks": [
            {"ssid": "Home", "signal": 80, "secure": True, "inUse": True},
            {"ssid": "Open", "signal": 20, "secure": False}]})
        self.assertEqual(t.split("\n")[:3], ["S:Home", "N:*:Home:80:WPA2", "N::Open:20:--"])

    def test_conn_list(self):
        t = H.fmt_conn_list({"eth": [{"name": "Ethernet", "device": "eth0", "up": True},
                                     {"name": "Ethernet 2", "up": False}],
                             "vpn": [{"name": "Mullvad", "connected": False}]})
        self.assertEqual(t.split("\n")[:3], ["Ethernet:802-3-ethernet:eth0", "Ethernet 2:802-3-ethernet:--",
                                             "Mullvad:vpn:--"])

    def test_bt_status(self):
        t = H.fmt_bt_status({"on": True, "devices": [{"mac": "AA:BB", "name": "Buds", "paired": True,
                                                      "connected": True, "battery": "60"}]})
        self.assertEqual(t.split("\n")[:2], ["P:Powered: yes", "D:AA:BB\t1\t1\t60\tBuds"])


class Mock(unittest.TestCase):
    def setUp(self):
        self.path = os.path.join(tempfile.mkdtemp(), "state.json")

    def test_toggle_wifi_and_bt(self):
        run(["wifi", "radio", "off"], self.path)
        run(["bt", "power", "off"], self.path)
        _, out, _ = run(["net", "status"], self.path)
        self.assertEqual(out.split("\n")[0], "disabled")
        _, out, _ = run(["bt", "status"], self.path)
        self.assertEqual(out.split("\n")[0], "P:Powered: no")

    def test_wrong_password_message_maps_to_macshell_text(self):
        code, _, err = run(["wifi", "connect", "Neighbour", "password", "nope"], self.path)
        self.assertNotEqual(code, 0)
        self.assertRegex(err, re.compile("secrets were required", re.I))   # MacShell -> "Incorrect password."

    def test_join_then_ethernet_icon_gives_way_to_wifi(self):
        code, _, _ = run(["wifi", "connect", "Home-5G"], self.path)        # saved network
        self.assertEqual(code, 0)
        _, out, _ = run(["net", "status"], self.path)
        self.assertTrue(out.split("\n")[1].startswith("yes:Home-5G:"))

    def test_airplane(self):
        run(["airplane", "on"], self.path)
        with open(self.path) as fh:
            s = json.load(fh)
        self.assertFalse(s["wifi_on"] or s["bt_on"])
        run(["airplane", "off"], self.path)
        with open(self.path) as fh:
            s = json.load(fh)
        self.assertTrue(s["wifi_on"] and s["bt_on"])


class WindowsBackend(unittest.TestCase):
    def test_error_text_passes_through(self):
        be = H.WindowsBackend()
        fake = mock.Mock(returncode=4, stdout="", stderr="Error: Secrets were required, but not provided.")
        with mock.patch("subprocess.run", return_value=fake):
            with self.assertRaises(H.Fail) as cm:
                be.wifi_connect("x", "y")
        self.assertIn("Secrets were required", str(cm.exception))

    def test_status_json(self):
        be = H.WindowsBackend()
        fake = mock.Mock(returncode=0, stderr="",
                         stdout=json.dumps({"wifi_on": True, "ssid": "", "signal": 0, "ethernet_up": True}))
        with mock.patch("subprocess.run", return_value=fake):
            out = H.fmt_net_status(be.status())
        self.assertIn("eth", out.split("\n"))


class LinuxPassThrough(unittest.TestCase):
    """The Linux backend must still be MacShell's original commands."""

    def test_single_line_commands_are_verbatim(self):
        with open(os.path.join(UPSTREAM, "MacBar.qml"), encoding="utf-8") as fh:
            src = fh.read()
        for key in ("net status", "conn list"):
            self.assertIn(json.dumps(H.LINUX[key]), src, key)


if __name__ == "__main__":
    unittest.main()
