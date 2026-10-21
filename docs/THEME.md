# Freeform OS — theme & settings ("our settings", mac-matched)

Goal: make the Freeform shell match macOS down to the text size, as a reusable
set of **our** tokens — not Apple's files.

## What can and can't be copied

| Thing | Can we copy it? | What we do |
|-------|-----------------|------------|
| macOS **metrics** (text sizes, control heights, radii, spacing, menu-bar height) | Yes — these are published numbers/behaviour | Re-expressed as open tokens in `ui/theme/macos-tokens.css` |
| **SF Pro** font | No — Apple-licensed, can't ship on Linux | Use **Inter** (free, near-identical); `-apple-system` still wins on a real Mac |
| macOS **wallpapers** | No — copyrighted images | CSS recreation; user drops in their own licensed file |
| **WhiteSur** theme code | Yes — it's **MIT** | Vendored at `vendor/WhiteSur-gtk-theme`. MIT only requires keeping their copyright notice (see `THIRD-PARTY.md`); FreeForm need NOT be GPL/open. (Corrects an earlier GPL-3.0 note.) |

## The tokens (`ui/theme/macos-tokens.css`)

macOS standard (AppKit) values, applied to the shell:

- **Type scale:** body/system **13px**, small **11px**, menu bar **14px**,
  title2 17, title1 22, large title 26, footnote/caption 10.
- **Menu bar height:** **24px**. **Dock icon:** 52px default (16–128 adjustable).
- **Control heights:** 22 / 19 / 15 (regular / small / mini).
- **Radii:** control 6, menu 10, window 11, tile 12.
- **System colors:** blue `#0a84ff`, green `#32d74b`, red `#ff453a`, etc.
- **Vibrancy:** blur 22px, saturate 180% (our Liquid Glass material).

Applied in `ui/desktop/index.html`: menu bar is now 24px / 14px text, body is
13px, font stack leads with `-apple-system` then Inter.

## Using WhiteSur (now vendored)

WhiteSur-gtk-theme (github.com/vinceliuice/WhiteSur-gtk-theme) is **MIT**, not
GPL (an earlier note here was wrong). It's vendored as a git submodule at
`vendor/WhiteSur-gtk-theme`, and we build our macOS-style shell theme on its
source. MIT only requires preserving their copyright/permission notice — kept in
`THIRD-PARTY.md` — so FreeForm itself stays whatever license we choose (it does
NOT have to be GPL/open). Our `ui/theme/macos-tokens.css` remains the layer where
we set FreeForm's own accent, radii and wallpaper on top.

## Privacy stack — Mullvad + Tor (design, NOT yet built)

The earlier VPN/Cloudflare chips were **mock UI** — nothing was installed. New
target:

- **Mullvad VPN** — privacy-first (no-logs, anonymous accounts, pays with cash),
  WireGuard-based. Managed by the app via the Mullvad CLI/daemon.
- **Tor routing** — chain it as **Mullvad → Tor** (VPN first, then Tor): your ISP
  sees only Mullvad, and Tor entry nodes see only Mullvad's IP, not yours.
  Simplest robust form is app traffic through the Tor SOCKS proxy / Tor Browser
  while Mullvad is up. (Mullvad also ships the **Mullvad Browser**, a Tor-Browser
  fork, which pairs well.)
- **Honest limits:** full system-wide "everything over Tor" is fragile (many
  apps leak, Tor is slow, some sites block it) — hence per-app Tor routing is the
  realistic default. Mullvad→Tor is doable; Tor→Mullvad is harder and rarely
  worth it.

**Cost (per owner preferences):** Mullvad is a flat ~€5/month, no tiers, cancel
anytime; Tor is free. No per-device or bandwidth upsell.

Status in the UI is a **placeholder** until the app actually manages these
daemons.
