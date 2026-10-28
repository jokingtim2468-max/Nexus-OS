"""`macshell-helper about` — the "About This PC" facts on Windows, in the key=value lines that
MacShell's AboutApp.qml reads from assets/about-info.sh on Linux:
  sub cpu cpusub gpu (| between GPUs) mem disk disksub kernel osname osver
"""
import json
import os
import subprocess
import sys

PS = r"""
$os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic Display|Remote' } | ForEach-Object { $_.Name })
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
$v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
@{ model = "$($cs.Manufacturer) $($cs.Model)"; cpu = $cpu.Name.Trim(); cores = $cpu.NumberOfCores; threads = $cpu.NumberOfLogicalProcessors
   gpu = $gpu; ram = $cs.TotalPhysicalMemory; size = $disk.Size; free = $disk.FreeSpace; drive = $env:SystemDrive
   kernel = $os.Version; caption = $os.Caption; display = $v.DisplayVersion; build = "$($v.CurrentBuild).$($v.UBR)" } | ConvertTo-Json -Compress
"""


def lines(d):
    gb = lambda b: float(b or 0) / 1024 ** 3
    ram = gb(d.get("ram"))
    gpus = d.get("gpu") or []
    if isinstance(gpus, str):
        gpus = [gpus]
    return {
        "sub": d.get("model", "").strip(),
        "cpu": d.get("cpu", ""),
        "cpusub": "%s cores, %s threads" % (d.get("cores", "?"), d.get("threads", "?")),
        "gpu": "|".join(gpus),
        "mem": "%d GB" % round(ram) if ram else "",
        "disk": "%s %d GB" % (d.get("drive", "C:"), round(gb(d.get("size")))),
        "disksub": "%d GB available" % round(gb(d.get("free"))),
        "kernel": "NT " + str(d.get("kernel", "")),
        "osname": str(d.get("caption", "Windows")).replace("Microsoft ", ""),
        "osver": "%s (build %s)" % (d.get("display", ""), d.get("build", "")),
    }


def main(argv):
    flags = 0x08000000 if os.name == "nt" else 0
    r = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", PS],
                       capture_output=True, text=True, creationflags=flags)
    try:
        d = json.loads(r.stdout)
    except ValueError:
        print("about: could not read system information", file=sys.stderr)
        return 1
    for k, v in lines(d).items():
        print("%s=%s" % (k, str(v).replace("\n", " ")))
    return 0
