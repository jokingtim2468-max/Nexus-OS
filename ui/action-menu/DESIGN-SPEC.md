# Nexus OS — Liquid Glass Action Menu (design spec)

> Paste this into Obsidian. (No Obsidian MCP is connected to the session yet,
> so this was written to the repo instead of synced automatically.)

macOS Tahoe "Liquid Glass" look reproduced for the Nexus OS action/context menu.
**Everything except logos** — all icons are generic, hand-drawn glyphs, no Apple
or brand marks.

## Material tokens

| Token              | Dark                              | Light                             |
|--------------------|-----------------------------------|-----------------------------------|
| Glass tint         | `rgba(255,255,255,0.10)`          | `rgba(255,255,255,0.55)`          |
| Glass tint (hover) | `rgba(255,255,255,0.22)`          | `rgba(255,255,255,0.78)`          |
| Rim light (bright) | `rgba(255,255,255,0.55)`          | `rgba(255,255,255,0.95)`          |
| Rim light (soft)   | `rgba(255,255,255,0.14)`          | `rgba(255,255,255,0.50)`          |
| Text               | `rgba(255,255,255,0.92)`          | `rgba(28,28,30,0.95)`             |
| Text dim           | `rgba(255,255,255,0.52)`          | `rgba(60,60,67,0.50)`             |
| Separator          | `rgba(255,255,255,0.14)`          | `rgba(60,60,67,0.16)`             |
| Accent (highlight) | `#0a84ff` → gradient `#3a9bff→#0a84ff` | same                         |

## Glass recipe

```css
background: var(--glass-tint);
backdrop-filter: blur(22px) saturate(180%) brightness(1.08);
border: 1px solid var(--glass-rim-soft);
box-shadow: 0 1px 1px rgba(0,0,0,.10), 0 12px 28px rgba(0,0,0,.38), 0 2px 6px rgba(0,0,0,.22);
```

- **Specular rim:** `::before` gradient-border (mask-composite) catches light on
  the top-left edge and fades on the opposite corner.
- **Inner sheen:** `::after` top 42% white→transparent gradient at 60% opacity.
- **Corners:** menu radius `16px`, item radius `9px` (squircle feel).
- **Open animation:** scale `0.94 → 1` with a slight overshoot
  `cubic-bezier(.2,.9,.3,1.2)`, 160 ms.

## Behavior

- Right-click anywhere (or the **Action ▾** button) opens the menu at the cursor.
- Hover highlights with the accent gradient; submenus open to the side and flip
  left/up near screen edges.
- `Esc` or outside-click dismisses. Light/dark toggle in the toolbar.

## Files

- `ui/action-menu/index.html` — self-contained prototype (open in any browser).
