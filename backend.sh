#!/usr/bin/env bash
set -u

# Resolved from this script rather than the caller's cwd, so bundled assets
# (the completion chime) are found wherever the project was cloned.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

base_dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell/dynamic-island"
weather_cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/dynamic-island/weather.json"
weather_lock="$base_dir/weather.lock"
slow_cache="$base_dir/slow.json"
slow_lock="$base_dir/slow.lock"
call_state="$base_dir/call.json"
# Which MPRIS instance the UI has pinned. Runtime state rather than a config
# value: it only means anything while that player is still running, so it
# belongs next to call.json, not in the user's settings.
player_state="$base_dir/player"
lyrics_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/dynamic-island/lyrics"
thumbnail_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/dynamic-island/thumbnails"
# Where the UI persists user choices (currently just the language). Created
# here rather than from QML because Quickshell's file writer won't create
# missing parent directories, and this script runs on every poll — so the
# directory is always in place long before anything tries to write to it.
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/dynamic-island"
mkdir -p "$base_dir"
mkdir -p "$(dirname "$weather_cache")"
mkdir -p "$thumbnail_dir"
mkdir -p "$config_dir"

# Apps whose simultaneous playback + capture stream counts as an active call.
# Extend this pattern to cover other VoIP clients as needed.
call_app_pattern='signal|telegram|whatsapp'

# Seconds a cached value may go stale before a background refresh is kicked off.
slow_ttl=4
weather_ttl=900
# Only applies to "we looked and there were none" markers. A track that has
# lyrics keeps them forever (they don't change), but a miss is worth retrying
# eventually since LRCLIB is community-contributed and gains tracks over time.
lyrics_miss_ttl=604800

# Every playerctl call in this script goes through the selection resolved here.
# Without -p, playerctl targets whichever instance it happens to list first,
# which silently changes under you the moment a second player appears — so the
# target is decided once and pinned for the rest of the process.
players_raw=""
selected_player=""
player_args=()

resolve_player() {
    players_raw=$(timeout 1 playerctl -l 2>/dev/null || true)
    selected_player=""
    [[ -s "$player_state" ]] && selected_player=$(<"$player_state")
    # A stored pick only means something while that instance is still alive.
    # When it goes away (tab closed, app quit) fall back to the first listed
    # player — which is exactly what playerctl did before any of this existed,
    # so nothing regresses for the single-player case.
    if [[ -z "$selected_player" ]] || ! grep -qxF "$selected_player" <<<"$players_raw"; then
        selected_player=$(head -n1 <<<"$players_raw")
    fi
    player_args=()
    [[ -n "$selected_player" ]] && player_args=(-p "$selected_player")
}

# Extracts the canonical 11-character id from the common YouTube URL shapes
# emitted by browser MPRIS bridges. Keeping this here (rather than in QML)
# covers youtube.com, music/mobile hosts, youtu.be, Shorts, Live and embeds in
# one place and avoids handing a page URL to the image loader.
youtube_id_from_url() {
    local url="$1" id=""

    if [[ "$url" =~ [\?\&]v=([A-Za-z0-9_-]{11}) ]]; then
        id=${BASH_REMATCH[1]}
    elif [[ "$url" =~ youtu\.be/([A-Za-z0-9_-]{11}) ]]; then
        id=${BASH_REMATCH[1]}
    elif [[ "$url" =~ youtube(-nocookie)?\.com/(shorts|live|embed|v)/([A-Za-z0-9_-]{11}) ]]; then
        id=${BASH_REMATCH[3]}
    fi

    [[ "$id" =~ ^[A-Za-z0-9_-]{11}$ ]] && printf '%s' "$id"
}

# Starts a single background download per video and immediately returns a
# usable source. The next snapshot switches to the local cached file. Quality
# is tried high-to-low, but tiny YouTube "maxres unavailable" placeholders are
# rejected so they can never be mistaken for a successful cover.
youtube_art_for() {
    # Split rather than chained: bash expands every word of a `local` command
    # before running it, so a later assignment referring to an earlier one on
    # the same line reads it while it is still unset — which under `set -u`
    # killed this function's subshell outright and left YouTube covers blank.
    local id="$1"
    local cache="$thumbnail_dir/$id.jpg"
    local lock="$thumbnail_dir/$id.lock"

    if [[ -s "$cache" ]]; then
        printf 'file://%s' "$cache"
        return 0
    fi

    if command -v curl >/dev/null 2>&1 && mkdir "$lock" 2>/dev/null; then
        (
            trap 'rmdir "$lock" 2>/dev/null; rm -f "$cache.tmp"' EXIT
            local quality width height bytes
            for quality in maxresdefault sddefault hqdefault mqdefault; do
                curl -fsSL --connect-timeout 2 --max-time 7 --retry 1 \
                    -o "$cache.tmp" "https://i.ytimg.com/vi/$id/$quality.jpg" || continue

                bytes=$(stat -c %s "$cache.tmp" 2>/dev/null || echo 0)
                width=0; height=0
                if command -v identify >/dev/null 2>&1; then
                    read -r width height < <(identify -format '%w %h' "$cache.tmp" 2>/dev/null || echo '0 0')
                elif command -v magick >/dev/null 2>&1; then
                    read -r width height < <(magick identify -format '%w %h' "$cache.tmp" 2>/dev/null || echo '0 0')
                fi

                # Dimension-aware when ImageMagick exists; byte size is the
                # dependency-free fallback. Both reject 120x90 placeholders.
                if (( width >= 320 && height >= 180 )) || { (( width == 0 )) && (( bytes >= 4096 )); }; then
                    mv "$cache.tmp" "$cache"
                    exit 0
                fi
                rm -f "$cache.tmp"
            done
        ) >/dev/null 2>&1 &
    fi

    # hqdefault exists for effectively every public video and keeps the first
    # frame useful while the higher-quality local cache is being populated.
    printf 'https://i.ytimg.com/vi/%s/hqdefault.jpg' "$id"
}

file_age() {
    local now modified
    now=$(date +%s)
    if [[ -s "$1" ]]; then
        modified=$(stat -c %Y "$1" 2>/dev/null || echo 0)
        echo $((now - modified))
    else
        echo 999999
    fi
}

# Prints the LRC (or plain) lyrics for a track, fetching them once and then
# serving every later request from disk.
#
# This is deliberately NOT part of the snapshot: snapshots run on a timer and
# must never touch the network. The UI calls this separately, once per track
# change, and waits for it out of band.
#
# MPRIS carries no lyrics of its own — Spotify reports xesam:asText as an empty
# string — so they have to come from somewhere else entirely. LRCLIB is the one
# source that needs no account, no key and no client registration, and it
# serves timestamped lines, which is what makes a synced view possible at all.
lyrics_for() {
    local artist="$1" title="$2" duration="${3:-0}"
    [[ -n "$artist" && -n "$title" ]] || return 0
    command -v curl >/dev/null 2>&1 || return 0

    mkdir -p "$lyrics_dir" 2>/dev/null || return 0

    local key cache lock now modified
    # Hashed because track and artist names contain slashes, quotes and
    # newlines that have no business being in a filename.
    key=$(printf '%s\n%s' "${artist,,}" "${title,,}" | sha1sum | cut -d' ' -f1)
    cache="$lyrics_dir/$key.lrc"
    lock="$lyrics_dir/$key.lock"

    if [[ -f "$cache" ]]; then
        # A non-empty cache is a hit and never expires. An empty one is the
        # "checked, none exist" marker and is retried once it goes stale.
        if [[ -s "$cache" ]]; then
            cat "$cache"
            return 0
        fi
        now=$(date +%s)
        modified=$(stat -c %Y "$cache" 2>/dev/null || echo 0)
        (( now - modified < lyrics_miss_ttl )) && return 0
    fi

    # Track changes can fire several lookups in a row (metadata often lands in
    # pieces); without this the same track would be fetched more than once.
    mkdir "$lock" 2>/dev/null || return 0
    trap 'rmdir "$lock" 2>/dev/null' RETURN

    local response synced plain
    response=$(curl -fsSL --max-time 6 -G 'https://lrclib.net/api/get' \
        --data-urlencode "artist_name=$artist" \
        --data-urlencode "track_name=$title" \
        ${duration:+--data-urlencode "duration=$duration"} 2>/dev/null || true)

    # LRCLIB matches duration within a couple of seconds and 404s otherwise.
    # Players round differently, so a miss here is often just that — retry
    # without the constraint before believing the track has no lyrics.
    if [[ -z "$response" ]]; then
        response=$(curl -fsSL --max-time 6 -G 'https://lrclib.net/api/get' \
            --data-urlencode "artist_name=$artist" \
            --data-urlencode "track_name=$title" 2>/dev/null || true)
    fi

    synced=$(jq -r '.syncedLyrics // empty' <<<"$response" 2>/dev/null)
    plain=$(jq -r '.plainLyrics // empty' <<<"$response" 2>/dev/null)

    # Written even when empty: that empty file is the negative-cache marker
    # that stops every later track change from hitting the network again.
    if [[ -n "$synced" ]]; then
        printf '%s\n' "$synced" > "$cache.tmp"
    elif [[ -n "$plain" ]]; then
        printf '%s\n' "$plain" > "$cache.tmp"
    else
        : > "$cache.tmp"
    fi
    mv "$cache.tmp" "$cache" 2>/dev/null || true
    [[ -s "$cache" ]] && cat "$cache"
    return 0
}

# The weather fetch takes seconds. Without a lock every poll during that window
# would start another curl, piling up dozens of concurrent requests.
refresh_weather() {
    (( $(file_age "$weather_cache") > weather_ttl )) || return 0
    mkdir "$weather_lock" 2>/dev/null || return 0
    (
        trap 'rmdir "$weather_lock" 2>/dev/null' EXIT
        local location latitude longitude response code temp apparent condition
        location=$(curl -fsSL --max-time 4 'https://ipapi.co/json/' 2>/dev/null || true)
        latitude=$(jq -r '.latitude // empty' <<<"$location" 2>/dev/null)
        longitude=$(jq -r '.longitude // empty' <<<"$location" 2>/dev/null)
        [[ -n "$latitude" && -n "$longitude" ]] || exit 0
        response=$(curl -fsSL --max-time 5 "https://api.open-meteo.com/v1/forecast?latitude=${latitude}&longitude=${longitude}&current=temperature_2m,apparent_temperature,weather_code&timezone=auto" 2>/dev/null || true)
        temp=$(jq -r '.current.temperature_2m // empty' <<<"$response")
        apparent=$(jq -r '.current.apparent_temperature // empty' <<<"$response")
        code=$(jq -r '.current.weather_code // empty' <<<"$response")
        [[ -n "$temp" && -n "$code" ]] || exit 0
        case "$code" in
            0) condition="󰖙" ;;
            1|2|3) condition="󰖕" ;;
            45|48) condition="󰖑" ;;
            51|53|55|56|57|61|63|65|66|67|80|81|82) condition="󰖗" ;;
            71|73|75|77|85|86) condition="󰖘" ;;
            95|96|99) condition="󰙾" ;;
            *) condition="󰖐" ;;
        esac
        jq -nc --arg icon "$condition" --arg temp "${temp}°C" --arg apparent "${apparent}°C" \
            '{icon:$icon,temp:$temp,apparent:$apparent}' > "$weather_cache.tmp"
        mv "$weather_cache.tmp" "$weather_cache"
    ) >/dev/null 2>&1 &
}

# Everything here costs 10-200ms per call, which is far too slow to run on every
# poll. It is refreshed in the background and the snapshot reads the last result.
refresh_slow() {
    (( $(file_age "$slow_cache") > slow_ttl )) || return 0
    mkdir "$slow_lock" 2>/dev/null || return 0
    (
        trap 'rmdir "$slow_lock" 2>/dev/null' EXIT

        local battery_time bt_device bt_powered camera_active wifi wifi_powered
        local weather_temp weather_icon weather_script

        battery_time=""
        if command -v upower >/dev/null 2>&1; then
            local upower_battery
            upower_battery=$(upower -e 2>/dev/null | grep -m1 battery || true)
            if [[ -n "$upower_battery" ]]; then
                battery_time=$(upower -i "$upower_battery" 2>/dev/null \
                    | awk -F: '/time to (empty|full)/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' || true)
            fi
        fi

        bt_device=$(timeout 2 bluetoothctl devices Connected 2>/dev/null | sed -n '1s/^Device [^ ]* //p' || true)
        bt_powered=false
        if timeout 2 bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then bt_powered=true; fi

        camera_active=false
        if command -v fuser >/dev/null 2>&1 && fuser /dev/video* >/dev/null 2>&1; then camera_active=true; fi

        wifi=$(iwgetid -r 2>/dev/null || true)
        wifi_powered=true
        if command -v nmcli >/dev/null 2>&1; then
            [[ "$(nmcli radio wifi 2>/dev/null)" == "enabled" ]] || wifi_powered=false
        fi

        weather_temp=""
        weather_icon=""
        # Optional hook for an existing weather script; overridable so the
        # project does not depend on one particular dotfiles layout.
        weather_script="${DI_WEATHER_SCRIPT:-$HOME/.config/hypr/scripts/quickshell/calendar/weather.sh}"
        if [[ -x "$weather_script" ]]; then
            local configured_temp configured_icon
            configured_temp=$(timeout 3 "$weather_script" --current-temp 2>/dev/null || true)
            configured_icon=$(timeout 3 "$weather_script" --current-icon 2>/dev/null || true)
            if [[ -n "$configured_temp" && "$configured_temp" != "0.0°C" ]]; then
                weather_temp="$configured_temp"
                weather_icon="$configured_icon"
            fi
        fi

        jq -nc \
            --arg batteryTime "$battery_time" --arg bluetooth "$bt_device" --argjson bluetoothPowered "$bt_powered" \
            --argjson cameraActive "$camera_active" --arg wifi "$wifi" --argjson wifiPowered "$wifi_powered" \
            --arg weatherTemp "$weather_temp" --arg weatherIcon "$weather_icon" \
            '{batteryTime:$batteryTime,bluetooth:$bluetooth,bluetoothPowered:$bluetoothPowered,cameraActive:$cameraActive,wifi:$wifi,wifiPowered:$wifiPowered,weatherTemp:$weatherTemp,weatherIcon:$weatherIcon}' \
            > "$slow_cache.tmp"
        mv "$slow_cache.tmp" "$slow_cache"
    ) >/dev/null 2>&1 &
}

# Per-application playback streams, for the volume mixer panel.
#
# Grouped by application rather than listed per stream: browsers open one sink
# input per tab (and per media element), so a raw stream list is four "Firefox"
# rows the user cannot tell apart. One row per app, driving every stream that
# app owns, is what "per-application volume" actually means to someone looking
# at the panel. Emits TSV because jq does the escaping better than awk would.
app_streams() {
    command -v pactl >/dev/null 2>&1 || { printf '[]'; return; }

    pactl list sink-inputs 2>/dev/null | awk '
        function unquote(s) { sub(/^[^=]*= "/, "", s); sub(/"$/, "", s); return s }
        function emit() {
            if (idx == "") return
            if (name == "") name = binname
            if (name == "") name = "?"
            printf "%s\t%s\t%d\t%s\t%s\t%s\n", idx, name, vol, mute, cork, binname
            idx = ""
        }
        /^Sink Input #/ { emit(); idx = substr($3, 2); name=""; binname=""; vol=0; mute="no"; cork="no"; next }
        idx == "" { next }
        /^[[:space:]]*Corked:/ { cork = $2; next }
        /^[[:space:]]*Mute:/ { mute = $2; next }
        # Only the first channel percentage is read; the island shows one bar
        # per app, so a per-channel balance has nothing to render into.
        /^[[:space:]]*Volume:/ { if (match($0, /[0-9]+%/)) vol = substr($0, RSTART, RLENGTH - 1); next }
        /application\.name = / { name = unquote($0); next }
        /application\.process\.binary = / { binname = unquote($0); next }
        END { emit() }
    ' | jq -Rsc '
        split("\n") | map(select(length > 0)) | map(split("\t")) | map({
            index: .[0],
            name: .[1],
            volume: (.[2] | tonumber),
            muted: (.[3] == "yes"),
            active: (.[4] == "no"),
            binary: (.[5] // "")
        })
        | group_by(.name) | map({
            name: .[0].name,
            binary: .[0].binary,
            indexes: (map(.index) | join(",")),
            volume: (map(.volume) | max),
            muted: (map(.muted) | all),
            active: (map(.active) | any)
        })'
}

# Best-effort "up next", and the only part of this script that talks D-Bus
# directly.
#
# MPRIS has no general queue concept: a player only exposes one if it implements
# the optional TrackList interface, which browsers do not and most others skip.
# The root interface answers HasTrackList itself, so asking costs one cheap
# property read rather than an introspection dump. Everything here degrades to
# {"supported":false} rather than guessing, because a panel that says "this
# player doesn't report a queue" is honest and one that stays mysteriously empty
# is not.
track_queue() {
    local player="$1"
    local unsupported='{"supported":false,"tracks":[]}'

    [[ -n "$player" ]] || { printf '%s' "$unsupported"; return; }
    command -v busctl >/dev/null 2>&1 || { printf '%s' "$unsupported"; return; }

    local bus="org.mpris.MediaPlayer2.$player" has
    has=$(timeout 1 busctl --user --json=short get-property "$bus" /org/mpris/MediaPlayer2 \
        org.mpris.MediaPlayer2 HasTrackList 2>/dev/null | jq -r '.data' 2>/dev/null)
    [[ "$has" == "true" ]] || { printf '%s' "$unsupported"; return; }

    local paths
    paths=$(timeout 1 busctl --user --json=short get-property "$bus" /org/mpris/MediaPlayer2 \
        org.mpris.MediaPlayer2.TrackList Tracks 2>/dev/null | jq -r '.data[]?' 2>/dev/null)
    [[ -n "$paths" ]] || { printf '{"supported":true,"tracks":[]}'; return; }

    local -a track_args=()
    local count=0 path
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        track_args+=("$path")
        count=$((count + 1))
    done <<<"$paths"

    local meta current
    meta=$(timeout 2 busctl --user --json=short call "$bus" /org/mpris/MediaPlayer2 \
        org.mpris.MediaPlayer2.TrackList GetTracksMetadata ao "$count" "${track_args[@]}" 2>/dev/null)
    [[ -n "$meta" ]] || { printf '{"supported":true,"tracks":[]}'; return; }

    # Everything before the playing track has already been heard, so "up next"
    # is whatever follows it in the list.
    current=$(timeout 1 busctl --user --json=short get-property "$bus" /org/mpris/MediaPlayer2 \
        org.mpris.MediaPlayer2.Player Metadata 2>/dev/null \
        | jq -r '.data["mpris:trackid"].data // ""' 2>/dev/null)

    printf '%s' "$meta" | jq -c --arg current "$current" '
        # busctl wraps each variant as {type,data}; unwrap to plain values. The
        # reply may arrive as a bare array or wrapped in the method-call tuple.
        def unwrap(entry; key): (entry[key].data // null);
        [ ((.data[0]? // .data? // []) | if type == "array" then .[] else empty end) | {
            id:     (unwrap(.; "mpris:trackid") // ""),
            title:  (unwrap(.; "xesam:title") // ""),
            artist: ((unwrap(.; "xesam:artist") // "")
                     | if type == "array" then (.[0] // "") else . end),
            # Both are optional and frequently absent — the cover-strip and
            # timeline layouts have to degrade when a player omits them.
            art:    (unwrap(.; "mpris:artUrl") // ""),
            length: (((unwrap(.; "mpris:length") // 0) | tonumber? // 0) / 1000000 | floor)
        } ]
        | (map(.id) | index($current)) as $at
        | { supported: true, tracks: (if $at == null then . else .[$at + 1:] end) }
    ' 2>/dev/null || printf '{"supported":true,"tracks":[]}'
}

json_snapshot() {
    # Which optional, expensive sections to build. The mixer shells out to
    # pactl and parses every stream, which has no business running on each of
    # the ~800ms polls when nobody is looking at it.
    local want="${1:-}"

    refresh_weather
    refresh_slow

    local media status title artist art length_us length_s position_s player shuffle loop track_url
    # One templated call replaces eight separate playerctl invocations.
    # {{position}} is deliberately used instead of {{mpris:position}}: the raw
    # MPRIS property is a snapshot many players (Firefox included) never
    # update while playing, whereas playerctl's normalized {{position}} adds
    # elapsed real time on top of it — the only one of the two that tracks a
    # playing track at all.
    resolve_player
    media=$(timeout 1 playerctl "${player_args[@]}" metadata --format \
        '{{status}}§|§{{title}}§|§{{artist}}§|§{{mpris:artUrl}}§|§{{mpris:length}}§|§{{playerName}}§|§{{position}}§|§{{xesam:url}}' \
        2>/dev/null | head -n1 || true)
    # Split on the §|§ delimiter; parameter expansion handles multi-char safely.
    status=${media%%§|§*}
    local rest=${media#*§|§}
    title=${rest%%§|§*}; rest=${rest#*§|§}
    artist=${rest%%§|§*}; rest=${rest#*§|§}
    art=${rest%%§|§*}; rest=${rest#*§|§}
    length_us=${rest%%§|§*}; rest=${rest#*§|§}
    player=${rest%%§|§*}; rest=${rest#*§|§}
    position_s=${rest%%§|§*}; rest=${rest#*§|§}
    track_url=${rest%%§|§*}

    # Browser MPRIS bridges often omit art entirely, or expose a generic
    # browser favicon. For YouTube the page URL is the reliable identity, so a
    # validated, locally cached thumbnail wins even when artUrl is non-empty.
    local youtube_id
    youtube_id=$(youtube_id_from_url "$track_url")
    if [[ -n "$youtube_id" ]]; then
        art=$(youtube_art_for "$youtube_id")
    fi

    [[ "$status" == "Playing" || "$status" == "Paused" ]] || status="Stopped"
    [[ "$length_us" =~ ^[0-9]+$ ]] || length_us=0
    length_s=$((length_us / 1000000))
    # {{position}} is supposed to be playerctl's own normalized field, already
    # in seconds — but not every MPRIS bridge is spec-compliant about it.
    # Firefox's really is plain seconds; Spotify's (and most spec-following
    # players') is still raw microseconds, matching mpris:length's units.
    # Dividing unconditionally (an earlier version of this script) broke
    # Firefox; never dividing (the version after that) broke Spotify — it
    # reported real positions in the hundreds of millions, which the frontend
    # immediately clamps down to the track length, pinning the bar at the end.
    # A five-day track is not a real thing, so treat anything that large as
    # microseconds and anything smaller as the seconds it claims to be.
    [[ "$position_s" =~ ^[0-9]+(\.[0-9]+)?$ ]] || position_s=0
    position_s=${position_s%%.*}
    (( position_s >= 1000000 )) && position_s=$((position_s / 1000000))

    shuffle="Off"
    loop="None"
    if [[ "$status" != "Stopped" ]]; then
        shuffle=$(timeout 1 playerctl "${player_args[@]}" shuffle 2>/dev/null | head -n1 || true)
        loop=$(timeout 1 playerctl "${player_args[@]}" loop 2>/dev/null | head -n1 || true)
        [[ -n "$shuffle" ]] || shuffle="Off"
        [[ -n "$loop" ]] || loop="None"
    fi

    local sink_raw source_raw volume muted mic_volume mic_muted mic_active brightness
    # Capture each wpctl output once and parse both volume and mute from it.
    sink_raw=$(timeout 1 wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
    source_raw=$(timeout 1 wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || true)
    volume=$(awk '{printf "%d", $2*100}' <<<"$sink_raw" 2>/dev/null)
    mic_volume=$(awk '{printf "%d", $2*100}' <<<"$source_raw" 2>/dev/null)
    [[ "$volume" =~ ^[0-9]+$ ]] || volume=0
    [[ "$mic_volume" =~ ^[0-9]+$ ]] || mic_volume=0
    [[ "$sink_raw" == *MUTED* ]] && muted=true || muted=false
    [[ "$source_raw" == *MUTED* ]] && mic_muted=true || mic_muted=false

    mic_active=false
    if [[ "$mic_muted" == "false" ]] && command -v pactl >/dev/null 2>&1; then
        local default_source source_state
        default_source=$(pactl get-default-source 2>/dev/null || true)
        source_state=$(pactl list sources 2>/dev/null \
            | awk -v target="$default_source" '$1=="Name:" {hit=($2==target)} hit && $1=="State:" {print tolower($2); exit}')
        [[ "$source_state" == "running" ]] && mic_active=true
    fi

    brightness=$(timeout 1 brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/,"",$4); print $4; exit}' || true)
    [[ "$brightness" =~ ^[0-9]+$ ]] || brightness=0

    # A call is inferred from PipeWire, not any one app's API: whichever known
    # VoIP app has both a playback stream (remote audio) and a capture stream
    # (our mic) open at once is, by construction, mid-call. This is what lets
    # one heuristic cover Signal/Telegram/WhatsApp without touching any of
    # their private protocols.
    local call_active=false call_app="" call_duration=0
    if command -v pactl >/dev/null 2>&1; then
        local playback_apps capture_apps
        playback_apps=$(pactl list sink-inputs 2>/dev/null \
            | awk -F'= ' '/application\.(name|process\.binary)/ {gsub(/"/,"",$2); print tolower($2)}')
        capture_apps=$(pactl list source-outputs 2>/dev/null \
            | awk -F'= ' '/application\.(name|process\.binary)/ {gsub(/"/,"",$2); print tolower($2)}')
        if [[ -n "$playback_apps" && -n "$capture_apps" ]]; then
            call_app=$(grep -iE "$call_app_pattern" <<<"$playback_apps" | while read -r app; do
                grep -qxF "$app" <<<"$capture_apps" && { echo "$app"; break; }
            done)
            [[ -n "$call_app" ]] && call_active=true
        fi
    fi

    local now_epoch prev_app prev_start
    now_epoch=$(date +%s)
    if [[ "$call_active" == "true" ]]; then
        prev_app="" prev_start=""
        [[ -s "$call_state" ]] && read -r prev_app prev_start < <(jq -r '"\(.app // "") \(.start // "")"' "$call_state" 2>/dev/null)
        [[ "$prev_app" == "$call_app" && "$prev_start" =~ ^[0-9]+$ ]] || prev_start=$now_epoch
        jq -nc --arg app "$call_app" --argjson start "$prev_start" '{app:$app,start:$start}' > "$call_state.tmp" && mv "$call_state.tmp" "$call_state"
        call_duration=$((now_epoch - prev_start))
    else
        rm -f "$call_state"
    fi

    local bat_path battery battery_status
    bat_path=$(find /sys/class/power_supply -maxdepth 1 -type l -name 'BAT*' 2>/dev/null | head -n1 || true)
    if [[ -n "$bat_path" ]]; then
        battery=$(< "$bat_path/capacity") 2>/dev/null || battery=0
        battery_status=$(< "$bat_path/status") 2>/dev/null || battery_status=Unknown
    else
        battery=100
        battery_status="Desktop"
    fi
    [[ "$battery" =~ ^[0-9]+$ ]] || battery=0

    local active_window fullscreen hypr

    # One hyprctl call and one jq for both fields instead of two of each.
    hypr=$(timeout 1 hyprctl activewindow -j 2>/dev/null | jq -r '[(.class // ""), ((.fullscreen // 0)|tostring)] | @tsv' 2>/dev/null || true)
    active_window=${hypr%%$'\t'*}
    fullscreen=${hypr##*$'\t'}
    [[ "$fullscreen" =~ ^[0-9]+$ ]] || fullscreen=0

    # One jq pass turns the newline-separated instance list into the array the
    # switcher renders. The label drops playerctl's ".instanceN" suffix so two
    # windows of the same browser don't produce two unreadable chips.
    local players_json
    players_json=$(printf '%s' "$players_raw" | jq -Rsc --arg sel "$selected_player" '
        split("\n") | map(select(length > 0)) | map({
            name: .,
            label: (split(".")[0]),
            selected: (. == $sel)
        })' 2>/dev/null || true)
    [[ -n "$players_json" ]] || players_json="[]"

    local apps_json="[]"
    [[ "$want" == *apps* ]] && apps_json=$(app_streams)
    [[ -n "$apps_json" ]] || apps_json="[]"

    local queue_json='{"supported":false,"tracks":[]}'
    [[ "$want" == *queue* ]] && queue_json=$(track_queue "$selected_player")
    [[ -n "$queue_json" ]] || queue_json='{"supported":false,"tracks":[]}'

    local weather slow
    [[ -s "$weather_cache" ]] && weather=$(<"$weather_cache") || weather='{"icon":"󰖐","temp":"--°","apparent":"--°"}'
    [[ -s "$slow_cache" ]] && slow=$(<"$slow_cache") \
        || slow='{"batteryTime":"","bluetooth":"","bluetoothPowered":false,"cameraActive":false,"wifi":"","wifiPowered":true,"weatherTemp":"","weatherIcon":""}'

    # A single jq invocation assembles the payload; the cached blobs are merged
    # in the filter so no extra processes are needed to read them.
    jq -nc \
        --arg status "$status" --arg title "$title" --arg artist "$artist" --arg art "$art" \
        --arg player "$player" --arg shuffle "$shuffle" --arg loop "$loop" \
        --argjson length "$length_s" --argjson position "$position_s" \
        --argjson volume "$volume" --argjson muted "$muted" --argjson micVolume "$mic_volume" \
        --argjson micMuted "$mic_muted" --argjson micActive "$mic_active" --argjson brightness "$brightness" \
        --argjson battery "$battery" --arg batteryStatus "$battery_status" \
        --argjson weather "$weather" --argjson slow "$slow" \
        --arg activeWindow "$active_window" --argjson fullscreen "$fullscreen" \
        --argjson callActive "$call_active" --arg callApp "$call_app" --argjson callDuration "$call_duration" \
        --argjson players "$players_json" --argjson apps "$apps_json" \
        --argjson queue "$queue_json" \
        '{
            apps:$apps,
            queue:$queue,
            media: {status:$status,title:$title,artist:$artist,art:$art,player:$player,shuffle:$shuffle,loop:$loop,length:$length,position:$position},
            players:$players,
            volume:$volume, muted:$muted, micVolume:$micVolume, micMuted:$micMuted, micActive:$micActive,
            brightness:$brightness, battery:$battery, batteryStatus:$batteryStatus,
            batteryTime:$slow.batteryTime, bluetooth:$slow.bluetooth, bluetoothPowered:$slow.bluetoothPowered,
            weather: {
                icon: (if ($slow.weatherIcon | length) > 0 then $slow.weatherIcon else $weather.icon end),
                temp: (if ($slow.weatherTemp | length) > 0 then $slow.weatherTemp else $weather.temp end),
                apparent: $weather.apparent
            },
            cameraActive:$slow.cameraActive,
            call: {active:$callActive, app:$callApp, duration:$callDuration},
            system: {wifi:$slow.wifi, wifiPowered:$slow.wifiPowered, activeWindow:$activeWindow, fullscreen:$fullscreen}
        }'
}

case "${1:-snapshot}" in
    snapshot) json_snapshot "${2:-}" ;;
    play-pause|next|previous)
        resolve_player
        timeout 2 playerctl "${player_args[@]}" "$1" >/dev/null 2>&1 || true ;;
    seek)
        resolve_player
        timeout 2 playerctl "${player_args[@]}" position "${2:-0}" >/dev/null 2>&1 || true ;;
    select-player)
        printf '%s' "${2:-}" > "$player_state.tmp" && mv "$player_state.tmp" "$player_state" ;;
    volume)
        wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ "${2:-50}%" >/dev/null 2>&1 || true ;;
    mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle >/dev/null 2>&1 || true ;;
    mic-volume)
        wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SOURCE@ "${2:-50}%" >/dev/null 2>&1 || true ;;
    mic-mute) wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle >/dev/null 2>&1 || true ;;
    # $2 is the comma-separated stream list one app owns (see app_streams), so
    # every stream of that app moves together and none drift out of sync.
    app-volume)
        IFS=',' read -ra app_idx <<< "${2:-}"
        for i in "${app_idx[@]}"; do
            [[ -n "$i" ]] && pactl set-sink-input-volume "$i" "${3:-50}%" >/dev/null 2>&1 || true
        done ;;
    # The target state is passed in rather than toggled per stream: toggling
    # each one individually would invert an app whose streams disagree.
    app-mute)
        IFS=',' read -ra app_idx <<< "${2:-}"
        for i in "${app_idx[@]}"; do
            [[ -n "$i" ]] && pactl set-sink-input-mute "$i" "${3:-1}" >/dev/null 2>&1 || true
        done ;;
    shuffle)
        resolve_player
        playerctl "${player_args[@]}" shuffle Toggle >/dev/null 2>&1 || true ;;
    loop)
        resolve_player
        current=$(playerctl "${player_args[@]}" loop 2>/dev/null || echo None)
        [[ "$current" == "None" ]] && next=Playlist || { [[ "$current" == "Playlist" ]] && next=Track || next=None; }
        playerctl "${player_args[@]}" loop "$next" >/dev/null 2>&1 || true ;;
    brightness) brightnessctl set "${2:-50}%" >/dev/null 2>&1 || true ;;
    lyrics) lyrics_for "${2:-}" "${3:-}" "${4:-0}" ;;
    # Quick-settings tiles. Read the current power state fresh rather than
    # trusting the (up to 15s stale) slow cache, so a rapid toggle always
    # flips from where the radio actually is, not from a stale snapshot.
    bluetooth-toggle)
        if timeout 2 bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
            bluetoothctl power off >/dev/null 2>&1 || true
        else
            bluetoothctl power on >/dev/null 2>&1 || true
        fi ;;
    # Completion chime. Uses ALSA aplay for reliability (produces audible output),
# with PipeWire/pulseaudio fallbacks. A chime-stop command is also provided
    # to halt playback when the timer/alarm dismissal card is closed.
    chime)
        sound_name="${2:-timesup}"
        sound="$script_dir/assets/$sound_name.wav"
        if [[ -r "$sound" ]]; then
            # Try aplay first (most reliable for audible output)
            if command -v aplay >/dev/null 2>&1; then
                aplay -q "$sound" >/dev/null 2>&1 &
                echo $! > "$base_dir/chime.pid"
            elif command -v pw-play >/dev/null 2>&1; then
                pw-play "$sound" >/dev/null 2>&1 &
                echo $! > "$base_dir/chime.pid"
            elif command -v paplay >/dev/null 2>&1; then
                paplay "$sound" >/dev/null 2>&1 &
                echo $! > "$base_dir/chime.pid"
            fi
        elif command -v canberra-gtk-play >/dev/null 2>&1; then
            canberra-gtk-play -i complete >/dev/null 2>&1 &
            echo $! > "$base_dir/chime.pid"
        fi ;;
    chime-stop)
        if [[ -f "$base_dir/chime.pid" ]]; then
            kill "$(cat "$base_dir/chime.pid")" 2>/dev/null || true
            rm -f "$base_dir/chime.pid"
        fi
        # Also kill any stray pw-play/paplay/aplay playing our chime files
        pkill -f "pw-play.*chime" 2>/dev/null || true
        pkill -f "paplay.*chime" 2>/dev/null || true
        pkill -f "aplay.*chime" 2>/dev/null || true
        pkill -f "pw-play.*timesup" 2>/dev/null || true
        pkill -f "paplay.*timesup" 2>/dev/null || true
        pkill -f "aplay.*timesup" 2>/dev/null || true
        ;;
    wifi-toggle)
        if [[ "$(nmcli radio wifi 2>/dev/null)" == "enabled" ]]; then
            nmcli radio wifi off >/dev/null 2>&1 || true
        else
            nmcli radio wifi on >/dev/null 2>&1 || true
        fi ;;
    visualizer)
        if command -v cava >/dev/null 2>&1; then
            exec cava -p <(printf '%s\n' '[general]' 'bars = 16' 'framerate = 30' '[output]' 'method = raw' 'raw_target = /dev/stdout' 'data_format = ascii' 'ascii_max_range = 100' 'channels = mono' '[smoothing]' 'monstercat = 1' 'waves = 0')
        fi ;;
esac
