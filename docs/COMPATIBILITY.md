# Freeform — Linux Conversion Kit: compatibility

**Idea:** a kit that converts a plain Linux install into one that runs apps from
other operating systems, by installing (1) maximum driver/firmware coverage and
(2) compatibility layers — **no VM**.

## The honest headline

You cannot run a Windows `.exe` or a macOS `.app` *literally* natively on Linux:
they're different binary formats compiled against a different kernel ABI. What
the kit does instead is install **translation layers** that run those apps
without a full virtual machine. For most apps the experience is near-native.

## Coverage matrix

| Source OS | How the kit runs its apps | How close to native | Reality |
|-----------|---------------------------|---------------------|---------|
| **Windows** | Wine + Proton (+ Lutris to manage) | Very close — translates Win32/DirectX calls live, no VM | ✅ Strong. Most apps & games work; anti-cheat and a few deep-hardware apps don't |
| **Android** | Waydroid (containerized Android) | Near-native, shares the Linux kernel | ✅ Strong for apps; some Play-Services apps need extra setup |
| **Linux** | Flatpak / Flathub + distro packages | Native | ✅ Trivial |
| **macOS** | Darling (translation layer) | Partial, mostly command-line | ⚠️ Weak — GUI mac apps largely don't work. The hard case. |

So "run apps from every OS natively" is honestly: **Windows ✅, Android ✅,
Linux ✅, macOS ⚠️ (partial).** macOS is the weak link because Apple's frameworks
are closed and tied to their hardware.

## Drivers side

Running foreign apps well still needs the hardware working, so the kit also
installs:
- `linux-firmware` (Wi-Fi/Bluetooth/GPU firmware blobs),
- CPU microcode (Intel/AMD),
- GPU userspace: Mesa (Intel/AMD) or the NVIDIA driver — **Vulkan matters**, as
  Proton/DXVK translate DirectX → Vulkan,
- printer/scanner backends.

The GPU vendor is auto-detected from PCI class `0x03`. The companion
`apps/driver-checker/` lists any device still without a driver.

## Why no VM

A VM (the earlier "Windows 10 VM" idea) is heavier, needs a Windows license, and
feels non-native. Wine/Proton/Waydroid run foreign apps **as processes on your
Linux desktop** — faster, lighter, no license, and they share your files and
windows directly. The trade-off: compatibility is per-app, not universal.

## Cost & safety note (per owner preferences)

- Everything the kit installs is **free, open source** — no purchases, no
  per-app licensing. Wine, Proton, Waydroid, Flatpak, Mesa are all FOSS.
- No electricity/VM overhead beyond the app you're actually running.
- The only paid thing that could appear is a game store account (e.g. Steam),
  which is optional and the user's choice.

## Usage

```bash
python3 apps/conversion-kit/convert.py          # plan only (safe, no changes)
python3 apps/conversion-kit/convert.py --json    # machine-readable (for a UI)
sudo python3 apps/conversion-kit/convert.py --install   # apply (asks first)
```

Supports apt / dnf / pacman / zypper / apk; packages are mapped per manager.
