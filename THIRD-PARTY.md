# Third-party

## MacShell — MIT, Copyright (c) 2026 Rickky
https://github.com/0-ss/MacShell — vendored at `vendor/MacShell` (pristine upstream) and copied into
`macshell-win/macshell/` and `macshell-win/maclock/` (our Windows port, modified).
Bundles the Open Runde font (SIL Open Font License 1.1) and gemoji emoji data (MIT). Full license text: `vendor/MacShell/LICENSE`.

## Quickshell — LGPL-3.0, Copyright (c) outfoxxed and contributors
https://github.com/quickshell-mirror/quickshell — vendored at `macshell-win/quickshell/`
(commit recorded in `macshell-win/quickshell/UPSTREAM`). The first commit adding it is unmodified
upstream; our Windows changes are separate commits on top, so `git diff` shows exactly what we changed.
Full license text: `macshell-win/quickshell/LICENSE` (and `LICENSE-GPL`).

## MacTahoe icon theme — GPL-3.0, Copyright (c) vinceliuice
https://github.com/vinceliuice/MacTahoe-icon-theme — not stored here: `macshell-win/tools/icons/build-theme.sh`
takes its app and place icons (pinned commit) into the package as `icons/FreeForm-Mac`, with its COPYING.
It is the icon set MacShell recommends (via Scrimas/MacOS-Like).

## Landscape wallpapers (Wikimedia Commons, downloaded unmodified when the package is built)
- `FreeForm Yosemite.jpg` (default): "Tunnel View, Yosemite Valley, Yosemite NP" by Diliff, CC BY-SA 3.0 —
  https://commons.wikimedia.org/wiki/File:Tunnel_View,_Yosemite_Valley,_Yosemite_NP_-_Diliff.jpg
- `FreeForm Big Sur.jpg`: "Central Californian Coastline, Big Sur - May 2013" by Diliff, CC BY-SA 3.0 —
  https://commons.wikimedia.org/wiki/File:Central_Californian_Coastline,_Big_Sur_-_May_2013.jpg
- `FreeForm Sierra.jpg`: "Last snow, Eastern Sierra Nevada, CA" (Flickr via Commons; license as printed by the CI build log) —
  https://commons.wikimedia.org/wiki/File:Last_snow,_Eastern_Sierra_Nevada,_CA_5-15_(21142042529).jpg
