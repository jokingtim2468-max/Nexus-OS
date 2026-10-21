# FreeForm — architecture (VM hub)

FreeForm is a **VM hub**. You open it, pick a Linux distro from the loader, and
it runs that distro in its **own VM with a persistent workspace** (saved disk).
Every guest runs the **real MacShell** (Hyprland + Quickshell) so all distros
share the same macOS-style Liquid Glass look. Mullvad/Tor/kill-switch ride
along. Later, FreeForm can be built into an **ISO** to run on bare metal as the
main OS.

```
                 ┌──────────────── FreeForm (the hub) ────────────────┐
   Loader  ───►  │  pick distro → launch its VM → persistent workspace │
 ui/loader/      │                                                     │
                 │   ┌─ VM: Ubuntu ─┐  ┌─ VM: Kali ─┐  ┌─ VM: Parrot ─┐ │
                 │   │  MacShell    │  │  MacShell  │  │  MacShell    │ │
                 │   │  workspace    │  │  workspace │  │  workspace   │ │
                 │   └──────────────┘  └────────────┘  └──────────────┘ │
                 │   NetGuard: Mullvad + Tor + fail-closed kill switch  │
                 └─────────────────────────────────────────────────────┘
```

## Components (in this repo)

| Piece | Path | What it does |
|-------|------|--------------|
| Loader | `ui/loader/` | Pick a distro (or drop your own) |
| VM Hub | `apps/vmhub/` | Create workspace disks, build/run the QEMU command per distro |
| Shell | `vendor/MacShell` | The real MacShell (MIT) installed inside each guest |
| Theme base | `vendor/WhiteSur-gtk-theme` | MIT GTK theme values (for non-Hypr guests / mock) |
| Conversion kit | `apps/conversion-kit/` | Install drivers + compat layers in a guest |
| NetGuard | `apps/netguard/` | Mullvad auto-connect, Tor, fail-closed kill switch |
| Driver checker | `apps/driver-checker/` | What hardware lacks a driver |
| freefetch | `apps/freefetch/` | FF logo + specs |
| Command registry | `apps/shell/` | `/help`, auto-scan of a distro's commands |
| Design mock | `ui/desktop/` | HTML Liquid Glass shell (reference) |

## VM hub details

- **Workspaces** live in `workspaces/<id>/` (git-ignored). First launch installs
  the distro from its ISO into the workspace disk; later launches resume it.
- **QEMU** runs each guest with `virtio-vga-gl` + `-display gtk,gl=on` so
  MacShell's **Liquid Glass GLSL shader** gets GPU acceleration.
- **MacShell provisioning**: `vmhub.py provision <id>` prints the one-time steps
  (Hyprland + Quickshell + `vendor/MacShell/install.sh`) to run in the guest.

## Any distro (actual ISOs)

Because a distro is just an ISO + workspace, **any** real distro ISO works. The
registry already lists 20 (Ubuntu, Kubuntu, Mint, Pop!_OS, Zorin, elementary,
Debian, Fedora, Nobara, openSUSE, Arch, EndeavourOS, Manjaro, Garuda, CachyOS,
Kali, Kali Everything, Parrot, BlackArch, Tails). To add any other ISO or respin
you downloaded (e.g. a specific Dark Kali spin), drop the `.iso` into
`distros/custom/` and it appears in the loader. Every guest gets the real
MacShell installed so they all look the same; the hub doesn't care which distro
it is.

## Honest status & limits

- The managers (`vmhub`, `netguard`, `conversion-kit`, etc.) are real, runnable,
  and **safe by default** (they print plans; `--run`/`--arm`/`--install` apply).
  They need `qemu`/`nftables`/root on the target machine — not present in this
  cloud container, so here they run in plan mode.
- **MacShell needs Hyprland + Quickshell + a GPU** for the shader; a headless or
  software-rendered VM won't show the full glass refraction.
- **Nested virtualization / KVM** must be available on the host for good VM
  speed. On a plain laptop that's fine; inside another VM it may be slow.

## Toward "main OS" (ISO, later)

The same pieces become a bootable FreeForm ISO: a minimal Linux base +
Hyprland + MacShell + NetGuard + the conversion kit, with the loader as the
first-run picker. The VM-hub stage is how we build and test that image before
committing it to bare metal.
