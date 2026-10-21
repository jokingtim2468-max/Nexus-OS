# Third-party code & attribution

FreeForm OS incorporates open-source components. Their licenses and required
notices are listed here.

## WhiteSur-gtk-theme

- **Source:** https://github.com/vinceliuice/WhiteSur-gtk-theme
- **Vendored at:** `vendor/WhiteSur-gtk-theme` (git submodule)
- **License:** MIT
- **Copyright:** © 2021 WhiteSur Developers (vinceliuice and contributors)

FreeForm uses WhiteSur's source as the basis of its macOS-style shell theme.
The MIT license permits use, modification, distribution and sale; the only
requirement is to preserve the copyright and permission notice, reproduced
below (full text in `vendor/WhiteSur-gtk-theme/COPYING`):

```
Copyright (c) 2021 WhiteSur Developers

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, ...
```

### Because it's MIT (not GPL)

FreeForm itself is **not** forced to be GPL/open source. We may license FreeForm
however we choose and keep our own code private, as long as WhiteSur's MIT notice
(above) travels with the WhiteSur-derived parts. This corrects an earlier note
that assumed GPL-3.0.

### Updating WhiteSur

```bash
git submodule update --remote vendor/WhiteSur-gtk-theme
```

## MacShell

- **Source:** https://github.com/0-ss/MacShell
- **Vendored at:** `vendor/MacShell` (git submodule)
- **License:** MIT
- **Copyright:** © 2026 Rickky

MacShell is FreeForm's actual desktop shell: a macOS-style menu bar + dock +
Control Center + Spotlight + Liquid Glass GLSL shader for **Hyprland**
(Quickshell/QML). It is installed inside each distro's VM so every workspace
shares the same look. MIT — keep the copyright/permission notice (in
`vendor/MacShell/LICENSE`); FreeForm is not forced open by using it.

```bash
git submodule update --remote vendor/MacShell
```
