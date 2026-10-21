# Nexus OS — driver strategy notes

Goal (as stated): **support every driver an OS can have — Windows, Linux, and
macOS drivers all usable on Nexus OS.**

These are working notes kept in the repo. They're meant to be honest about what
is realistic so we build the right thing instead of chasing the impossible.

## The hard reality (read this first)

A "driver" is not portable code. It is compiled against one kernel's internal
ABI and driver model. The three worlds are fundamentally different:

| OS      | Driver model      | Format         | Why it won't just load elsewhere |
|---------|-------------------|----------------|----------------------------------|
| Linux   | kernel modules    | `.ko`          | Built per kernel version/config; GPL symbol gating |
| Windows | WDM / WDF (KMDF/UMDF) | `.sys` + INF | Closed ABI, PatchGuard, signing (WHQL) |
| macOS   | IOKit / DriverKit | `.kext` / `.dext` | Apple-only ABI, platform locked, notarized |

So "load a Windows `.sys` directly on our kernel" is not achievable — those
binaries call into NT internals that don't exist outside Windows. Honest
framing: **Nexus OS cannot execute foreign driver binaries as-is.** What it
*can* realistically do is one or more of the approaches below.

## Realistic approaches to "support all three"

1. **Pick one driver model as the native base.** Linux has the largest open
   driver set and runs the most hardware out of the box. Building Nexus OS on
   (or compatible with) the Linux driver model gives us thousands of real
   drivers for free. This is the cheapest path to "supports the most hardware."

2. **Compatibility shims for the other two:**
   - *Windows:* a reimplemented driver ABI in the spirit of ReactOS / NDISwrapper
     — load certain classes of `.sys` (historically network/NDIS) by emulating
     the NT kernel calls they expect. Narrow, per-class, lots of work.
   - *macOS:* DriverKit (`.dext`) drivers are user-space and better isolated;
     a DriverKit-compatible runtime is more tractable than kernel kexts, but
     still Apple-ABI work.

3. **Virtualization / passthrough (the pragmatic win).** Run the OS that owns a
   driver in a VM and pass the device through (VFIO-style). The native driver
   runs in its own OS; Nexus OS brokers the hardware. This is how you honestly
   "support" a device whose only driver is Windows- or macOS-only.

4. **Device-class generic drivers.** Many devices (USB HID, USB mass storage,
   NVMe, AHCI, standard GPUs via VESA/ UEFI GOP) follow open class specs. One
   generic driver per class covers huge swaths of hardware regardless of vendor.

**Recommendation:** base on the Linux driver model (approach 1) + class drivers
(approach 4) for breadth now, and treat Windows/macOS support as
passthrough/VM (approach 3) first, shims (approach 2) only where a class really
matters. This is buildable; "run any `.sys` natively" is not.

> Cost / profit note (per project preferences): approaches 1, 3, 4 reuse
> existing open-source drivers and hypervisor tech — no per-driver licensing
> cost. Writing closed-ABI shims (approach 2) is high-effort, low-coverage, and
> would be the main money/time sink, so defer it until a specific device
> demands it.

## The driver checker app

`apps/driver-checker/` — enumerates the host's hardware and reports which
devices currently have a driver bound and which don't. The unbound ones are the
concrete gap list Nexus OS must cover. Runnable today on Linux; Windows and
macOS backends are stubbed with their implementation plan.

### What "missing" means
The checker only counts **physical buses** (pci, usb, virtio, platform, acpi,
pnp, hid, serial, i2c, spi, mmc, scsi, thunderbolt). Virtual kernel objects
(cpu, memory blocks, workqueues, clock events, numa nodes) are excluded by
default because they never bind a driver in any OS — counting them just
inflates the number. Use `--all` to see them anyway.

Note: some ACPI namespace nodes (`device:NN`, `LNXSYBUS`) legitimately have no
driver — they're firmware description nodes, not attachable hardware. Treat the
PCI/USB/virtio "NO DRIVER" rows as the real signal.

## First run on this dev machine (2026-10-21)

Linux x86_64 VM. 78 physical-bus devices, 26 with a driver, 52 "missing" —
almost all of the 52 are ACPI firmware nodes. Every actual PCI/virtio device
(`virtio_net`, `virtio_blk`, `virtio_rng`, `virtio_balloon`, serial) is bound.
The one real unbound PCI device is `0000:00:00.0` (Intel host bridge
`8086:0d57`), which needs no functional driver. So this VM is effectively fully
covered — expected, since it's paravirtualized hardware.

## Next steps

- [ ] Decide the native driver base (recommend: Linux driver model).
- [ ] Implement the Windows backend of the checker (`Get-PnpDevice`, Problem
      codes 28 = no driver installed).
- [ ] Implement the macOS backend (`ioreg -l`, nodes without an `IOService`).
- [ ] Map a vendor/device ID → human name table (bundle a trimmed pci.ids/usb.ids).
- [ ] Prototype device-class generic drivers for USB HID + mass storage.

---

## Desktop & distro strategy (2026-10-21)

Decision direction from the owner: **Mac-style look on a Linux base, with
dual-boot.** This is sound and buildable.

### "Can we use a Mac container?"
There is no drop-in that converts Linux into macOS. The honest options:

| Option        | What it is                               | Verdict for Nexus OS |
|---------------|------------------------------------------|----------------------|
| Themed Linux  | Linux + a Mac-style shell (our UI)       | ✅ the real plan — free, uses all Linux drivers |
| `Docker-OSX`  | Real macOS in a KVM VM                    | ⚠️ heavy, Apple-hardware licensing; use only to *run* a mac app |
| `Darling`     | "Wine for macOS" translation layer        | ⚠️ partial; some CLI/apps only |

**Plan:** Linux base + the Liquid Glass shell in `ui/desktop/` as the face of
the OS. Dual-boot handled by GRUB (install alongside an existing OS). Because
the base is Linux, **most drivers already exist** — "implement drivers apps
require" becomes "enable the kernel modules a given device/app needs," which the
driver-checker (`apps/driver-checker/`) surfaces. Running actual macOS/Windows
apps is the same foreign-ABI problem as drivers: prefer VM/passthrough, not
native execution.

### UI shell built so far (`ui/desktop/index.html`)
- Top menu bar: Nexus menu, app menus (File/Edit/View/Go/Window/Help), and a
  right cluster with battery, Wi-Fi, search, Control Center, and a **live clock**.
- Liquid Glass **dock**: pinned apps (Finder, Terminal, Browser, Mail, Messages,
  Music, Photos, Calendar, Settings, **Driver Checker**) with hover
  magnification, running-app dots, and Trash.
- Right-click action/context menu (New Folder, Get Info, Change Wallpaper, Sort
  By →, Paste) in the same glass material.
- Generic icons only — **no brand/Apple logos**. Light & dark themes.
