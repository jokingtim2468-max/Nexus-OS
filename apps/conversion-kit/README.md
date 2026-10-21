# Freeform — Linux Conversion Kit

Converts a plain Linux install into one that runs apps from other OSes, by
installing **driver/firmware coverage** + **compatibility layers** (no VM).

- Windows apps → Wine / Proton (+ Lutris)
- Android apps → Waydroid
- Linux apps → Flatpak / Flathub
- macOS apps → Darling (partial, experimental)

**No dependencies** (Python 3 stdlib). **Safe by default** — prints a plan and
changes nothing until you pass `--install`.

## Run

```bash
python3 convert.py                 # detect + print the install plan
python3 convert.py --only drivers  # just drivers/firmware
python3 convert.py --json          # machine-readable (for the UI dashboard)
sudo python3 convert.py --install  # actually install (asks to confirm)
```

Detects distro + package manager (apt/dnf/pacman/zypper/apk) and GPU vendor
(Intel/AMD/NVIDIA) and maps the right packages. See `../../docs/COMPATIBILITY.md`
for the honest per-OS coverage matrix and `../driver-checker/` for what hardware
still lacks a driver.
