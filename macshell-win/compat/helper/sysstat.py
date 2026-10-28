"""`macshell-helper stats watch` (Linux) — CPU / RAM load for desktop widgets, a JSON line every 2 s.
Same shape as sysstat.ps1 on Windows: {"cpu", "ram", "ramUsed", "ramTotal", "gpu"} (gpu: 0 here)."""
import json
import sys
import time


def cpu_times():
    with open("/proc/stat") as fh:
        f = [int(x) for x in fh.readline().split()[1:]]
    return sum(f), f[3] + (f[4] if len(f) > 4 else 0)                    # total, idle + iowait


def mem():
    m = {}
    with open("/proc/meminfo") as fh:
        for line in fh:
            k, v = line.split(":", 1)
            m[k] = int(v.split()[0])
    total, avail = m.get("MemTotal", 0), m.get("MemAvailable", 0)
    return total, total - avail


def main(argv):
    if argv[:1] != ["watch"]:
        print("usage: stats watch", file=sys.stderr)
        return 64
    last = cpu_times()
    while True:
        time.sleep(2)
        now = cpu_times()
        dt, di = now[0] - last[0], now[1] - last[1]
        last = now
        total, used = mem()
        out = {"cpu": int(100 * (dt - di) / dt) if dt else 0, "gpu": 0}
        if total:
            out.update(ram=int(100 * used / total), ramUsed=round(used / 1048576, 1), ramTotal=round(total / 1048576, 1))
        print(json.dumps(out), flush=True)
