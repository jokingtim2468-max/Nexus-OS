# Driver Checker

Scans the host for hardware and reports which devices have a driver bound and
which don't. The unbound physical devices are the gap list Nexus OS must cover.

**No dependencies** — pure Python 3 standard library. Reads `/sys` directly.

## Run

```bash
python3 driverscan.py            # readable report (physical buses only)
python3 driverscan.py --missing  # only devices with NO driver bound
python3 driverscan.py --all      # include virtual kernel objects too
python3 driverscan.py --json     # machine-readable, for a UI
```

## Platforms

| Platform | Status        | How it reads devices                         |
|----------|---------------|----------------------------------------------|
| Linux    | ✅ implemented | `/sys/bus/*/devices/*` + `driver` symlink    |
| Windows  | ⏳ stubbed      | planned: `Get-PnpDevice` / SetupAPI problem codes |
| macOS    | ⏳ stubbed      | planned: `ioreg -l` IORegistry               |

See `../../docs/DRIVERS.md` for the overall driver strategy and why foreign
driver binaries can't just be loaded natively.

## Output

Each device shows: bus, sysfs name, bound driver (or `— NO DRIVER —`), and
vendor:device IDs where available. A summary line gives total / bound / missing
counts for physical-bus devices.
