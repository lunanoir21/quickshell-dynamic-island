#!/usr/bin/env bash
# Records the tour video that leads the site: every feature, in order, on an
# empty desktop.
#
# The hard part of a GUI demo is usually driving the app reliably. That is
# already solved here — every widget can be raised over IPC (the same calls
# the Makefile exposes), so the reel is a list of scenes rather than a
# recording of someone clicking. Re-running it after a visual change produces
# the same video with the new look, which is the point.
#
#   tools/demo.sh              # record → docs/demo.mp4
#   tools/demo.sh --dry-run    # play the scenes, record nothing
#   tools/demo.sh --keep-raw   # keep the pre-compression capture
#
# It moves you to an empty workspace while recording and puts you back where
# you were afterwards, including if it is interrupted.
set -euo pipefail

# Scene durations are written with a decimal point, which under a comma-decimal
# locale (tr_TR here) makes both printf and sleep reject them outright.
export LC_NUMERIC=C

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "$script_dir")"

SHELL_QML="${SHELL_QML:-$HOME/.config/hypr/scripts/quickshell/Shell.qml}"
out="$repo_dir/docs/demo.mp4"
fps="60"
dry_run=0
keep_raw=0
# Quality-targeted rather than bitrate-targeted. The reel is a mostly-static
# dark desktop with one small moving surface, which h264 compresses to a
# fraction of any fixed bitrate worth picking — a constant 1400k spent ~14MB
# on 80 seconds of near-still frames and actually made the file *larger* than
# the raw capture. CRF spends bits only where there is motion; the ceiling is
# there so a busy scene still cannot run away with the file size.
crf="30"
max_kbps="2000"

die() { printf '%s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: tools/demo.sh [options]

Options:
  --out FILE     Output file (default: docs/demo.mp4)
  --fps N        Capture frame rate (default: 60)
  --dry-run      Run the scene list without recording
  --keep-raw     Keep the uncompressed capture next to the output
  -h, --help     This message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) out="${2:-}"; shift 2 ;;
        --fps) fps="${2:-}"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        --keep-raw) keep_raw=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1 (see --help)" ;;
    esac
done

command -v hyprctl >/dev/null || die "hyprctl not found — this needs Hyprland."
command -v jq >/dev/null || die "jq not found (pacman -S jq)"
if (( ! dry_run )); then
    command -v gpu-screen-recorder >/dev/null \
        || die "gpu-screen-recorder not found (pacman -S gpu-screen-recorder)"
    command -v ffmpeg >/dev/null || die "ffmpeg not found (pacman -S ffmpeg)"
fi

ipc() { qs -p "$SHELL_QML" ipc call dynamicIsland "$@" >/dev/null 2>&1 || true; }

qs -p "$SHELL_QML" ipc call dynamicIsland close >/dev/null 2>&1 \
    || die "cannot reach the island over IPC — is the shell running? (SHELL_QML=$SHELL_QML)"

# ------------------------------------------------------------------ workspace
origin_ws="$(hyprctl activeworkspace -j | jq -r '.id')"
# The lowest id in 1..20 with no windows on it. A demo filmed over a desktop
# full of the author's windows is neither reusable nor safe to publish.
empty_ws=""
used="$(hyprctl workspaces -j | jq -r '.[] | select(.windows > 0) | .id')"
for candidate in $(seq 1 20); do
    if ! grep -qx "$candidate" <<<"$used"; then empty_ws="$candidate"; break; fi
done
[[ -n "$empty_ws" ]] || die "no empty workspace in 1..20 — close something first."

# The tour cycles themes to show them off, and setTheme() persists to
# settings.json — so without putting it back, filming a demo silently
# rewrites the user's own theme. Same for the language the reel assumes.
settings_file="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/dynamic-island/settings.json"
origin_theme=""
[[ -s "$settings_file" ]] && origin_theme="$(jq -r '.themeName // empty' "$settings_file" 2>/dev/null || true)"

recorder_pid=""
restored=0
restore() {
    (( restored )) && return
    restored=1
    [[ -n "$recorder_pid" ]] && kill -INT "$recorder_pid" 2>/dev/null || true
    [[ -n "$recorder_pid" ]] && wait "$recorder_pid" 2>/dev/null || true
    ipc close
    [[ -n "$origin_theme" ]] && ipc theme "$origin_theme"
    hyprctl dispatch workspace "$origin_ws" >/dev/null 2>&1 || true
}
trap restore EXIT INT TERM

# ---------------------------------------------------------------- scene list
# Each scene: how long it stays on screen, then the IPC call that sets it up.
# Read top to bottom, this is the video's script — edit here to change the
# tour, and keep the narration in sync with what the island actually shows.
scene() {
    local hold="$1"; shift
    local label="$1"; shift
    printf '  %5ss  %s\n' "$hold" "$label"
    (( $# )) && ipc "$@"
    sleep "$hold"
}

run_scenes() {
    printf 'Scenes:\n'

    ipc close;                    sleep 1.5
    scene 2.5 "Collapsed pill"
    scene 3.5 "Expanded panel"                open
    scene 3.0 "Pixel clock"                   clock
    scene 3.0 "Calendar"                      calendar
    scene 2.0 "Back to the panel"             calendar

    scene 3.0 "Time tools — timer"            timeMode timer
    scene 2.5 "Timer running"                 timeToggle
    scene 3.0 "Stopwatch"                     timeMode stopwatch
    scene 3.0 "Focus cycle"                   timeMode focus
    scene 3.0 "Alarm"                         timeMode alarm
    scene 1.0 "Reset"                         timeReset
    scene 4.0 "A timer finishing"             timerTest
    scene 1.0 ""                              timerDismiss

    scene 4.0 "Notification"                  notification "Signal" "Ada" "Are you seeing this?"
    # The island infers a call from the accept/decline action ids rather than
    # from any dedicated call API, so this is a notification carrying those
    # two actions — see isIncomingCall in DynamicIsland.qml.
    scene 4.5 "Incoming call"                 notifyWithActions "Signal" "Incoming call" "Calling…" "" \
        "$(printf '[{"id":"accept","text":"Answer"},{"id":"decline","text":"Decline"}]' | base64 -w0)" \
        "demo-call-1" false ""
    scene 1.0 ""                              dismissCall

    scene 3.0 "Microphone in use"             deviceEvent microphone true 62
    scene 1.5 ""                              deviceEvent microphone false 0
    scene 3.0 "Camera in use"                 deviceEvent camera true 0
    scene 1.5 ""                              deviceEvent camera false 0
    scene 3.0 "Battery"                       battery 18 Discharging
    scene 1.5 ""                              batteryReset

    scene 3.0 "App volume mixer"              appVolumes
    scene 2.0 ""                              appVolumes

    scene 3.5 "Settings"                      settingsSection appearance
    scene 2.5 "Theme — Gold"                  theme gold
    scene 2.5 "Theme — Red"                   theme red
    scene 2.5 "Theme — Umbra"                 theme umbra
    scene 2.5 "Time tools settings"           settingsSection timetools
    scene 1.5 "Close"                         settings

    scene 2.5 "Back to the pill"              close
}

# -------------------------------------------------------------------- record
printf 'Moving to empty workspace %s (you are on %s)\n' "$empty_ws" "$origin_ws"
hyprctl dispatch workspace "$empty_ws" >/dev/null
sleep 1.2

if (( dry_run )); then
    printf 'Dry run — nothing is being recorded.\n\n'
    run_scenes
    printf '\nDone.\n'
    exit 0
fi

monitor="$(hyprctl monitors -j | jq -r '[.[] | select(.focused)][0].name')"
[[ -n "$monitor" && "$monitor" != "null" ]] || die "could not determine the focused monitor"

raw="$(mktemp -u "${TMPDIR:-/tmp}/di-demo-raw-XXXXXX.mp4")"
mkdir -p "$(dirname "$out")"

printf 'Recording %s at %s fps → %s\n\n' "$monitor" "$fps" "$out"
gpu-screen-recorder -w "$monitor" -f "$fps" -o "$raw" >/dev/null 2>&1 &
recorder_pid=$!
sleep 2

run_scenes

sleep 1
kill -INT "$recorder_pid" 2>/dev/null || true
wait "$recorder_pid" 2>/dev/null || true
recorder_pid=""
[[ -s "$raw" ]] || die "the recorder produced nothing — check gpu-screen-recorder works on this session"

printf '\nCompressing…\n'
# faststart so the site can start playing before the file finishes arriving.
ffmpeg -y -loglevel error -i "$raw" \
    -c:v libx264 -preset slow -crf "$crf" \
    -maxrate "${max_kbps}k" -bufsize "$((max_kbps * 2))k" \
    -pix_fmt yuv420p -movflags +faststart -an \
    "$out"

if (( keep_raw )); then
    mv "$raw" "${out%.mp4}-raw.mp4"
    printf 'Raw capture: %s\n' "${out%.mp4}-raw.mp4"
else
    rm -f "$raw"
fi

printf '%s  (%s)\n' "$out" "$(du -h "$out" | cut -f1)"
