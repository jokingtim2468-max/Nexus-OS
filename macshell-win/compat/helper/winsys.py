"""Windows stand-ins for the small Linux tools MacShell's Settings and Control Center run.

The helper shim is also built as xdg-open.exe, brightnessctl.exe, powerprofilesctl.exe and
notify-send.exe; each passes its own name first, so `brightnessctl -m` arrives here as
["brightnessctl", "-m"]. Output matches what MacShell parses from the real tools.

  xdg-open URL|PATH                  open with the default app
  brightnessctl -m                   "screen,backlight,N,P%,100"   (brightness.ps1)
  brightnessctl -q set P%
  powerprofilesctl get|set power-saver|balanced|performance   (Windows power plans)
  notify-send [-a APP] TITLE [BODY]  a Windows notification
  pickface                           choose a picture -> ~/.face (512x512), prints "ok"
  pw-play [--volume=V] FILE          play a sound (wav, mp3, ...) through Windows' media player
  pickaudio                          choose a sound file, prints its path (Settings > Notifications)
  ffconfig get                       FreeForm's own options as JSON (Settings > FreeForm)
  ffconfig set KEY 0|1               hideTaskbar hideIcons skipLauncher autoUpdate modSpotify modDiscord (launcher.json), autoStart (Run key)
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
NOWIN = 0x08000000 if os.name == "nt" else 0
PLANS = {
    "power-saver": "a1841308-3541-4fab-bc81-f71556f20b4a",
    "balanced": "381b4222-f694-41f0-9685-ff5bb260df2e",
    "performance": "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c",
}


def ps(script_or_file, *args, file=False, timeout=30):
    cmd = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass"]
    cmd += (["-File", script_or_file] if file else ["-Command", script_or_file]) + list(args)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, creationflags=NOWIN)
        return r.stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def plan_for(guid_text):
    g = (guid_text or "").lower()
    for k, v in PLANS.items():
        if v in g:
            return k
    return "balanced"


CONFIG_KEYS = ("hideTaskbar", "hideIcons", "skipLauncher", "autoUpdate", "modSpotify", "modDiscord")


def config_path():
    return os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "FreeForm", "launcher.json")


def package_root():
    return os.path.normpath(os.path.join(HERE, "..", ".."))


def ffconfig(a):
    cfg = {"hideTaskbar": True, "hideIcons": True, "skipLauncher": False, "autoUpdate": True, "modSpotify": True, "modDiscord": True}
    try:
        with open(config_path(), encoding="utf-8-sig") as f:
            cfg.update(json.load(f))
    except (OSError, ValueError):
        pass
    run_key = r"Software\Microsoft\Windows\CurrentVersion\Run"
    if a[:1] == ["set"] and len(a) > 2:
        key, on = a[1], a[2] in ("1", "on", "true")
        if key == "autoStart":
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, run_key, 0, winreg.KEY_SET_VALUE) as k:
                if on:
                    winreg.SetValueEx(k, "FreeForm", 0, winreg.REG_SZ, '"%s"' % os.path.join(package_root(), "FreeForm.cmd"))
                else:
                    try:
                        winreg.DeleteValue(k, "FreeForm")
                    except OSError:
                        pass
        elif key in CONFIG_KEYS:
            cfg[key] = on
            os.makedirs(os.path.dirname(config_path()), exist_ok=True)
            with open(config_path(), "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2)
        return 0
    auto = False
    if os.name == "nt":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, run_key) as k:
                auto = bool(winreg.QueryValueEx(k, "FreeForm")[0])
        except OSError:
            pass
    try:
        with open(os.path.join(package_root(), "version.txt"), encoding="utf-8") as f:
            version = f.read().strip()
    except OSError:
        version = "dev"
    out = {k: bool(cfg.get(k)) for k in CONFIG_KEYS}
    out.update(autoStart=auto, version=version, root=package_root())
    print(json.dumps(out))
    return 0


def main(argv):
    tool, a = (argv + [""])[0], argv[1:]
    if tool == "xdg-open":
        if a and a[0]:
            os.startfile(a[0]) if os.name == "nt" else subprocess.call(["xdg-open", a[0]])
        return 0
    if tool == "brightnessctl":
        if "set" in a:
            v = re.sub(r"[^0-9]", "", a[a.index("set") + 1] if a.index("set") + 1 < len(a) else "")
            if v:
                ps(os.path.join(HERE, "brightness.ps1"), "set", v, file=True)
            return 0
        v = ps(os.path.join(HERE, "brightness.ps1"), "get", file=True).strip()
        if v.isdigit():
            print(f"screen,backlight,{v},{v}%,100")
        return 0
    if tool == "powerprofilesctl":
        if a[:1] == ["set"] and len(a) > 1 and a[1] in PLANS:
            g = PLANS[a[1]]
            if subprocess.call(["powercfg", "/setactive", g], creationflags=NOWIN,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) != 0:
                # the plan is hidden on this PC: restore Windows' copy of it, then switch
                subprocess.call(["powercfg", "-duplicatescheme", g, g], creationflags=NOWIN,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.call(["powercfg", "/setactive", g], creationflags=NOWIN,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return 0
        try:
            out = subprocess.run(["powercfg", "/getactivescheme"], capture_output=True, text=True,
                                 timeout=10, creationflags=NOWIN).stdout
        except (OSError, subprocess.TimeoutExpired):
            out = ""
        print(plan_for(out))
        return 0
    if tool == "notify-send":
        rest, app = [], "FreeForm"
        i = 0
        while i < len(a):
            if a[i] in ("-a", "--app-name") and i + 1 < len(a):
                app = a[i + 1]; i += 2; continue
            if a[i].startswith("-"):
                i += 2 if a[i] in ("-i", "-u", "-t", "-c", "-h") else 1; continue
            rest.append(a[i]); i += 1
        title, body = (rest + ["", ""])[0], (rest + ["", ""])[1]
        esc = lambda s: s.replace("'", "''")
        ps("[void][Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime];"
           "$x=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);"
           f"$t=$x.GetElementsByTagName('text');[void]$t.Item(0).AppendChild($x.CreateTextNode('{esc(title)}'));"
           f"[void]$t.Item(1).AppendChild($x.CreateTextNode('{esc(body)}'));"
           "$id='{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe';"
           "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($id).Show([Windows.UI.Notifications.ToastNotification]::new($x))")
        return 0
    if tool == "pw-play":
        vol, files = 0.8, []
        for x in a:
            if x.startswith("--volume="):
                try: vol = max(0.0, min(1.0, float(x.split("=", 1)[1])))
                except ValueError: pass
            elif x: files.append(x)
        if not files or not os.path.exists(files[-1]):
            return 1
        uri = files[-1].replace("'", "''")
        ps("Add-Type -AssemblyName PresentationCore; $p = New-Object System.Windows.Media.MediaPlayer; "
           f"$p.Open([Uri]'{uri}'); $p.Volume = {vol}; $p.Play(); "
           "$t = 0; while (-not $p.NaturalDuration.HasTimeSpan -and $t -lt 40) { Start-Sleep -Milliseconds 50; $t++ }; "
           "$d = if ($p.NaturalDuration.HasTimeSpan) { [Math]::Min(15000, $p.NaturalDuration.TimeSpan.TotalMilliseconds) } else { 3000 }; "
           "Start-Sleep -Milliseconds ([int]$d + 150); $p.Close()", timeout=30)
        return 0
    if tool == "pickaudio":
        out = ps("Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.OpenFileDialog; "
                 "$d.Title = 'Choose a notification sound'; $d.Filter = 'Sounds|*.wav;*.mp3;*.ogg;*.m4a;*.wma|All files|*.*'; "
                 "$d.InitialDirectory = [Environment]::GetFolderPath('MyMusic'); if ($d.ShowDialog() -eq 'OK') { $d.FileName }", timeout=600)
        print(out.strip())
        return 0
    if tool == "ffconfig":
        return ffconfig(a)
    if tool == "pickface":
        face = os.path.join(os.path.expanduser("~"), ".face").replace("'", "''")
        out = ps("Add-Type -AssemblyName System.Windows.Forms,System.Drawing;"
                 "$d=New-Object System.Windows.Forms.OpenFileDialog;$d.Title='Choose a picture';"
                 "$d.Filter='Images|*.png;*.jpg;*.jpeg;*.webp;*.bmp';"
                 "$d.InitialDirectory=[Environment]::GetFolderPath('MyPictures');"
                 "if($d.ShowDialog() -eq 'OK'){$i=[System.Drawing.Image]::FromFile($d.FileName);"
                 "$s=[Math]::Min($i.Width,$i.Height);$b=New-Object System.Drawing.Bitmap 512,512;"
                 "$g=[System.Drawing.Graphics]::FromImage($b);$g.InterpolationMode='HighQualityBicubic';"
                 "$g.DrawImage($i,(New-Object System.Drawing.Rectangle 0,0,512,512),[int](($i.Width-$s)/2),[int](($i.Height-$s)/2),$s,$s,'Pixel');"
                 f"$b.Save('{face}',[System.Drawing.Imaging.ImageFormat]::Png);'ok'}}", timeout=600)
        print("ok" if "ok" in out else "")
        return 0
    print(f"macshell-helper: unknown tool: {tool}", file=sys.stderr)
    return 64
