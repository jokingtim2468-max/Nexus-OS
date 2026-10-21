# Freeform OS — theme & settings ("our settings", mac-matched)

Goal: make the Freeform shell match macOS down to the text size, as a reusable
set of **our** tokens — not Apple's files.

## What can and can't be copied

| Thing | Can we copy it? | What we do |
|-------|-----------------|------------|
| macOS **metrics** (text sizes, control heights, radii, spacing, menu-bar height) | Yes — these are published numbers/behaviour | Re-expressed as open tokens in `ui/theme/macos-tokens.css` |
| **SF Pro** font | No — Apple-licensed, can't ship on Linux | Use **Inter** (free, near-identical); `-apple-system` still wins on a real Mac |
| macOS **wallpapers** | No — copyrighted images | CSS recreation; user drops in their own licensed file |
| **WhiteSur** theme code | Yes, *with conditions* | It's **GPL-3.0**. A fork is allowed but must stay GPL-3.0 and credit vinceliuice. See below. |

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

## Using WhiteSur properly (if we fork it)

WhiteSur-gtk-theme (github.com/vinceliuice/WhiteSur-gtk-theme) is the closest
"macOS on Linux" theme and is **GPL-3.0-only**. If we base our GTK/shell theme
on it:
1. Keep the derivative **GPL-3.0** and include their `LICENSE` + a NOTICE
   crediting vinceliuice.
2. Track what we changed (our accent, radii, our wallpaper).
3. Don't mix it into MIT/proprietary parts of the project without checking
   compatibility.

This is why I didn't bulk-copy their repo in — a fork needs to be done as a
proper GPL fork, not a silent paste. Say the word and I'll set it up that way.

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
