# FreeForm OS — distro loader, custom distros & commands

FreeForm opens as a **loader**: pick a distribution, and it boots into the one
FreeForm shell (same UI, dock, menu bar and commands) on top of that distro.

## Loader

`ui/loader/index.html` — the pick-a-distro screen. Recommended distros come from
`distros/registry.json`: **Ubuntu, Kali, Debian, Fedora, Arch, Linux Mint**.
Every distro shares the identical FreeForm UI.

## Customize the Linux used (drop-in)

1. Download a distro image yourself (`.iso`, or a rootfs / manifest).
2. Drop the file into **`distros/custom/`**.
3. It appears in the loader automatically (add an entry under `"custom"` in
   `registry.json`, or the app auto-detects files in the folder).

`registry.json` fields: `id`, `name`, `edition`, `logo`, `accent`, `commands`
(path to its command catalog), `file` (local file in `distros/`) and `url`
(where to fetch it if `file` is empty).

> Nothing is downloaded automatically. You grab the distro, you place the file,
> you stay in control of what runs.

## Commands: auto-scan + keep + custom

`apps/shell/shellkit.py` builds one command catalog per distro by combining:

1. **Base commands** (`distros/commands/base.json`) — always present, including
   FreeForm's **custom** commands: `/help`, `/distro`, `freefetch`.
2. **Curated distro commands** (e.g. `distros/commands/kali.json`) — the
   well-known tools with descriptions.
3. **Auto-scan of the live `$PATH`** — every executable actually installed on
   the loaded distro, so nothing is missed. (Descriptions for scanned commands
   come from `whatis`/man with `--enrich`.)

So we **keep** the distro's own commands and **add** our custom ones.

### `/help`

The base command `/help` lists every command and what it does:

```bash
python3 apps/shell/shellkit.py help --distro kali
```

On a real Kali image this merged **1516** commands (52 documented + ~1464 more
found on PATH). Kali ships 600+ security tools — the curated set names the
famous ones (nmap, metasploit, hydra, sqlmap, aircrack-ng, …) and the scan picks
up the rest. We don't hand-list all of them because the auto-scan is always
accurate to what's actually installed; the curated JSONs just add nicer
descriptions and can be extended anytime.

## freefetch (logo + specs)

`apps/freefetch/freefetch.py` — a fastfetch-style command showing the **FF**
FreeForm logo beside live specs (OS, kernel, CPU, memory, uptime). Per-distro
logos/accents come from `registry.json`.

```bash
python3 apps/freefetch/freefetch.py          # FF logo + specs
python3 apps/freefetch/freefetch.py --logo kali
```

## Note on the UI origin

The shell's look matches macOS, built from **our own tokens**
(`ui/theme/macos-tokens.css`) — not a copy of WhiteSur's GPL-3.0 code, so the
whole project stays freely tailorable. Same look, legally ours.
