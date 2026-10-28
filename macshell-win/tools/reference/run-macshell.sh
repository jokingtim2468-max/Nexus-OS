#!/usr/bin/env bash
# Run the REAL, unmodified upstream MacShell (vendor/MacShell) for use as the visual/behaviour
# reference while porting. Linux + Nix only; works headless (no GPU, no Hyprland needed):
# Quickshell 0.3.x under a headless sway, Mesa llvmpipe software GL, screenshots via grim.
#
#   tools/reference/run-macshell.sh setup              # fetch quickshell, sway, grim, mesa, icons (Nix cache)
#   tools/reference/run-macshell.sh start [wall.jpg]   # launch MacShell on a 1920x1080 virtual screen
#   tools/reference/run-macshell.sh ipc call controlcenter open   # drive it with MacShell's own IPC
#   tools/reference/run-macshell.sh shot name          # screenshot -> $WORK/name.png
#   tools/reference/run-macshell.sh stop
#
# IPC targets MacShell exposes: controlcenter, spotlight, settings (pane <id>), clock, about,
# wallpapers, notifications, widgets, switcher, screenshot, hardware, gaming, glass.
# Without Hyprland, window lists / workspaces / hyprctl actions are empty; everything visual works.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
WORK=${MACSHELL_REF_DIR:-$ROOT/.macshell-reference}
NIXPKGS=${NIXPKGS:-$WORK/nixpkgs}
RUN=/run/macshell-ref                     # short: wayland socket paths must be < 108 chars
mkdir -p "$WORK"
export PATH=/nix/var/nix/profiles/default/bin:$PATH

p() { readlink -f "$WORK/pkgs/$1"; }

case "${1:-}" in
setup)
  [ -f "$NIXPKGS/default.nix" ] || { mkdir -p "$NIXPKGS"; curl -sSL https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz | tar xJ --strip-components=1 -C "$NIXPKGS"; }
  mkdir -p "$WORK/pkgs"
  for a in quickshell sway grim mesa swaybg whitesur-icon-theme; do nix-build "$NIXPKGS" -A $a -o "$WORK/pkgs/$a" >/dev/null || exit 1; done
  echo "ready: quickshell $(nix-instantiate --eval -E "(import $NIXPKGS {}).quickshell.version")"
  exit 0 ;;
esac

export HOME=$WORK/home XDG_RUNTIME_DIR=$RUN XDG_CONFIG_HOME=$WORK/home/.config LANG=C.UTF-8 LC_ALL=C.UTF-8
export PATH=$(p swaybg)/bin:$PATH
export XDG_DATA_DIRS=$HOME/.local/share:$(p whitesur-icon-theme)/share:$(p quickshell)/share
export QS_ICON_THEME=WhiteSur-dark
export __EGL_VENDOR_LIBRARY_FILENAMES=$(p mesa)/share/glvnd/egl_vendor.d/50_mesa.json
export LIBGL_DRIVERS_PATH=$(p mesa)/lib/dri LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1
CFG=$HOME/.config/quickshell/MacShell
QS=$(p quickshell)/bin/qs

case "${1:-}" in
start)
  WALL=${2:-$HOME/wall.jpg}
  mkdir -p "$RUN" "$CFG" "$HOME/.config/hypr" "$HOME/.local/share/applications" && chmod 700 "$RUN"
  cp -r "$ROOT/vendor/MacShell/MacShell/." "$CFG/"
  [ -f "$WALL" ] || { echo "need a wallpaper image: start /path/to/wall.jpg"; exit 1; }
  echo "wallpaper = ,$WALL" > "$HOME/.config/hypr/hyprpaper.conf"      # how MacShell finds the wallpaper
  # stub launchers so the Dock shows its default pins
  for e in "org.gnome.Nautilus|Files" "firefox|Firefox" "kitty|kitty" "code|VS Code" "discord|Discord" "spotify|Spotify" "steam|Steam" "obsidian|Obsidian"; do
    IFS='|' read id name <<<"$e"
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\nIcon=%s\n' "$name" "$([ "$id" = code ] && echo visual-studio-code || echo "$id")" > "$HOME/.local/share/applications/$id.desktop"
  done
  printf 'output HEADLESS-1 resolution 1920x1080 position 0 0 bg %s fill\ndefault_border none\n' "$WALL" > "$WORK/sway.conf"
  "$(p sway)/bin/sway" -c "$WORK/sway.conf" > "$WORK/sway.log" 2>&1 & echo $! > "$WORK/sway.pid"
  for i in $(seq 1 50); do ls "$RUN"/wayland-? >/dev/null 2>&1 && break; sleep 0.2; done
  basename "$(ls "$RUN"/wayland-? | head -1)" > "$WORK/display"
  WAYLAND_DISPLAY=$(cat "$WORK/display") QT_QPA_PLATFORM=wayland "$QS" -p "$CFG/shell.qml" > "$WORK/qs.log" 2>&1 & echo $! > "$WORK/qs.pid"
  echo "MacShell starting (log: $WORK/qs.log)" ;;
shot)
  WAYLAND_DISPLAY=$(cat "$WORK/display") "$(p grim)/bin/grim" "$WORK/${2:-shot}.png" && echo "$WORK/${2:-shot}.png" ;;
ipc)
  shift; WAYLAND_DISPLAY=$(cat "$WORK/display") "$QS" -p "$CFG/shell.qml" ipc "$@" ;;
stop)
  for f in qs sway; do [ -f "$WORK/$f.pid" ] && kill "$(cat "$WORK/$f.pid")" 2>/dev/null; rm -f "$WORK/$f.pid"; done; echo stopped ;;
*) sed -n '2,16p' "$0" ;;
esac
