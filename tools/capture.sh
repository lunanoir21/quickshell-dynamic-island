#!/usr/bin/env bash
# The one way this project takes screenshots.
#
# Why a script instead of `grim -g "x,y wxh"`: both of the island's surfaces
# are full-screen layer-shell windows with their real content centred inside,
# so `hyprctl layers` reports the *screen*, not the pill. Cropping by hand
# means guessing a rectangle that is wrong the moment the island changes size
# — and guessing wrong on a full-screen surface captures whatever the user
# happens to have open behind it. This asks the shell where its content
# actually is (see the islandWidth/islandHeight IPC properties in
# DynamicIsland.qml) and crops to exactly that.
#
#   tools/capture.sh media                    # island → docs/screenshots/media.png
#   tools/capture.sh --target settings themes # settings window
#   tools/capture.sh --target island --pad 24 --dir /tmp shot
#
# See AGENTS.md — screenshots that go into the repo are taken with this.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "$script_dir")"

SHELL_QML="${SHELL_QML:-$HOME/.config/hypr/scripts/quickshell/Shell.qml}"
target="island"
out_dir="$repo_dir/docs/screenshots"
delay="0.6"
pad="0"
name=""

die() { printf '%s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: tools/capture.sh [options] <name>

Options:
  --target island|settings|full   What to crop to (default: island)
  --dir DIR                       Output directory (default: docs/screenshots)
  --delay SEC                     Wait before capturing (default: 0.6)
  --pad PX                        Extra margin around the crop (default: 0)
  -h, --help                      This message

The name becomes <dir>/<name>.png. Existing files are overwritten, so a
screenshot can be re-taken under the same name after a visual change.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) target="${2:-}"; shift 2 ;;
        --dir)    out_dir="${2:-}"; shift 2 ;;
        --delay)  delay="${2:-}"; shift 2 ;;
        --pad)    pad="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*) die "Unknown option: $1 (see --help)" ;;
        *) name="$1"; shift ;;
    esac
done

[[ -n "$name" ]] || { usage >&2; die "A name is required."; }
command -v grim >/dev/null || die "grim not found (pacman -S grim)"
command -v jq   >/dev/null || die "jq not found (pacman -S jq)"
command -v hyprctl >/dev/null || die "hyprctl not found — this needs Hyprland."

ipc_prop() {
    qs -p "$SHELL_QML" ipc prop get dynamicIsland "$1" 2>/dev/null || true
}

# Geometry of a layer-shell surface by namespace, as "x y w h".
layer_geom() {
    hyprctl layers -j | jq -r --arg ns "$1" \
        '[.[] | .levels[] | .[] | select(.namespace==$ns)][0]
         | select(. != null) | "\(.x) \(.y) \(.w) \(.h)"'
}

sleep "$delay"

case "$target" in
island)
    read -r lx ly lw _lh <<<"$(layer_geom qs-dynamic-island)" \
        || die "island layer not found — is the shell running?"
    [[ -n "${lx:-}" ]] || die "island layer not found — is the shell running?"

    iw="$(ipc_prop islandWidth)"
    ih="$(ipc_prop islandHeight)"
    top="$(ipc_prop islandTopMargin)"
    [[ "$iw" =~ ^[0-9]+$ && "$ih" =~ ^[0-9]+$ ]] \
        || die "could not read island geometry over IPC — is Shell.qml the running config? (SHELL_QML=$SHELL_QML)"
    [[ "$top" =~ ^[0-9]+$ ]] || top=8

    # The island is centred in its layer and pinned `top` px from its edge.
    x=$(( lx + (lw - iw) / 2 ))
    y=$(( ly + top ))
    w="$iw"
    h="$ih"
    ;;
settings)
    read -r lx ly lw lh <<<"$(layer_geom qs-dynamic-island-settings)" \
        || die "settings layer not found"
    [[ -n "${lx:-}" ]] || die "settings layer not found — open it first (make settings)"

    # Mirrors SettingsMenu.qml's `win`: capped at 920x640, inset 32px from the
    # screen on smaller displays, centred. Keep these in sync with that file.
    w=$(( 920 < lw - 32 ? 920 : lw - 32 ))
    h=$(( 640 < lh - 32 ? 640 : lh - 32 ))
    x=$(( lx + (lw - w) / 2 ))
    y=$(( ly + (lh - h) / 2 ))
    ;;
full)
    # Captures the whole screen, including anything else that is open. Only
    # for deliberate full-desktop shots — never as a fallback for a crop that
    # failed. See AGENTS.md.
    printf 'capture.sh: full-screen target — everything on screen will be in the image.\n' >&2
    read -r x y w h <<<"$(hyprctl monitors -j | jq -r '[.[] | select(.focused)][0] | "\(.x) \(.y) \(.width) \(.height)"')"
    ;;
*)
    die "Unknown target: $target (island|settings|full)"
    ;;
esac

if (( pad > 0 )); then
    x=$(( x - pad )); y=$(( y - pad ))
    w=$(( w + pad * 2 )); h=$(( h + pad * 2 ))
    (( x < 0 )) && x=0
    (( y < 0 )) && y=0
fi

(( w > 0 && h > 0 )) || die "computed an empty crop (${w}x${h}) — nothing captured"

mkdir -p "$out_dir"
file="$out_dir/$name.png"
grim -g "$x,$y ${w}x${h}" "$file"
printf '%s  (%sx%s)\n' "$file" "$w" "$h"
