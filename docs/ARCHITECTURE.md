# Freeform OS — architecture

> Renamed from "Nexus OS" per the owner. (The git repo is still `Nexus-OS`;
> renaming the repo is a separate GitHub action and wasn't done automatically.)

## The concept

Freeform OS is **an app you open on your Mac** — not a separate OS you boot. When
launched it presents a full-computer desktop (the Liquid Glass shell in
`ui/desktop/`) and spins up background services:

- a **Windows 10 VM** for Windows apps/drivers,
- a **VPN** connection,
- a **Cloudflare** tunnel,

…and a **global keybind closes it** (⌘⇧Q in the prototype), stopping those
services. Because it runs on macOS, it uses **the Mac's own drivers** for all
real hardware — that's automatic, since it's just a macOS process.

## How each piece is really built

| Piece            | Prototype (this repo)        | Real implementation |
|------------------|------------------------------|---------------------|
| Desktop shell    | `ui/desktop/index.html`      | Electron or Tauri window (web UI = the shell) |
| Open/close keybind | JS `keydown` ⌘⇧Q            | OS global hotkey (Electron `globalShortcut` / macOS Services) |
| Windows 10 VM    | status tile + dock icon      | **QEMU/UTM** (Apple-silicon: HVF accel) booting a licensed Win10 image |
| Windows apps     | "Windows Apps" dock icon     | app windows forwarded from the VM (RDP/RemoteApp-style) |
| VPN              | menu-bar status + CC tile    | WireGuard/OpenVPN client managed by the app |
| Cloudflare       | menu-bar status + CC tile    | `cloudflared` tunnel spawned by the app |
| Mac drivers      | — (inherited)                | native: the app runs on macOS, so macOS drivers already serve the hardware |
| Wallpaper        | CSS recreation of Sequoia    | load a licensed image file the user owns |

## Honest limitations

- **Windows 10 needs a license.** You can't legally bundle or redistribute a
  Windows image; the app would download/activate the user's own license. Win10
  is also **end-of-life (Oct 2025)** — consider Windows 11 for the VM.
- **The Mac's drivers do not pass into the Windows VM.** macOS (especially Apple
  silicon) does not expose raw hardware passthrough to guests. The VM sees
  *paravirtual* devices (virtio/VMware-style), and its guest drivers handle
  those. So "Windows uses the Mac's official drivers" is not literally possible;
  what's true is the **Mac handles the hardware and the VM rides on top**.
- **Apple wallpapers are copyrighted** — recreated in CSS here, not shipped.
- **Darling / Docker-OSX** are not needed for this design (we're *on* a Mac, not
  emulating one).

## Cost & safety note (per owner preferences)

- **VM:** no software cost beyond a Windows license; uses CPU/RAM/battery while
  running — the keybind-to-close matters so it's not always draining power.
- **Cloudflare Tunnel:** free tier covers personal use. Verify before relying on
  paid features.
- **VPN:** free self-hosted (WireGuard on a cheap VPS) or a paid provider —
  compare monthly cost vs. a one-time VPS.
- Nothing here requires buying from a third-party site; if that changes, verify
  the seller is reputable and price it first.

## Build order (suggested)

1. Wrap `ui/desktop/` in Tauri (smaller than Electron) → a real openable app.
2. Global open/close hotkey.
3. Spawn/stop `cloudflared` + WireGuard with live status feeding the menu bar.
4. QEMU/UTM Win10 VM, launched/suspended with the app; forward app windows.
5. Settings screen to point at the user's Win10 ISO/license and wallpaper file.
