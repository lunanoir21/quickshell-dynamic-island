#!/usr/bin/env bash
set -u

base_dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell/dynamic-island"
weather_cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/dynamic-island/weather.json"
weather_lock="$base_dir/weather.lock"
slow_cache="$base_dir/slow.json"
slow_lock="$base_dir/slow.lock"
call_state="$base_dir/call.json"
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
    local id="$1" cache="$thumbnail_dir/$id.jpg" lock="$thumbnail_dir/$id.lock"

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

        local battery_time bt_device camera_active wifi
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

        camera_active=false
        if command -v fuser >/dev/null 2>&1 && fuser /dev/video* >/dev/null 2>&1; then camera_active=true; fi

        wifi=$(iwgetid -r 2>/dev/null || true)

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
            --arg batteryTime "$battery_time" --arg bluetooth "$bt_device" \
            --argjson cameraActive "$camera_active" --arg wifi "$wifi" \
            --arg weatherTemp "$weather_temp" --arg weatherIcon "$weather_icon" \
            '{batteryTime:$batteryTime,bluetooth:$bluetooth,cameraActive:$cameraActive,wifi:$wifi,weatherTemp:$weatherTemp,weatherIcon:$weatherIcon}' \
            > "$slow_cache.tmp"
        mv "$slow_cache.tmp" "$slow_cache"
    ) >/dev/null 2>&1 &
}

json_snapshot() {
    refresh_weather
    refresh_slow

    local media status title artist art length_us length_s position_s player shuffle loop track_url
    # One templated call replaces eight separate playerctl invocations.
    # {{position}} is deliberately used instead of {{mpris:position}}: the raw
    # MPRIS property is a snapshot many players (Firefox included) never
    # update while playing, whereas playerctl's normalized {{position}} adds
    # elapsed real time on top of it — the only one of the two that tracks a
    # playing track at all.
    media=$(timeout 1 playerctl metadata --format \
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
        shuffle=$(timeout 1 playerctl shuffle 2>/dev/null | head -n1 || true)
        loop=$(timeout 1 playerctl loop 2>/dev/null | head -n1 || true)
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

    local weather slow
    [[ -s "$weather_cache" ]] && weather=$(<"$weather_cache") || weather='{"icon":"󰖐","temp":"--°","apparent":"--°"}'
    [[ -s "$slow_cache" ]] && slow=$(<"$slow_cache") \
        || slow='{"batteryTime":"","bluetooth":"","cameraActive":false,"wifi":"","weatherTemp":"","weatherIcon":""}'

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
        '{
            media: {status:$status,title:$title,artist:$artist,art:$art,player:$player,shuffle:$shuffle,loop:$loop,length:$length,position:$position},
            volume:$volume, muted:$muted, micVolume:$micVolume, micMuted:$micMuted, micActive:$micActive,
            brightness:$brightness, battery:$battery, batteryStatus:$batteryStatus,
            batteryTime:$slow.batteryTime, bluetooth:$slow.bluetooth,
            weather: {
                icon: (if ($slow.weatherIcon | length) > 0 then $slow.weatherIcon else $weather.icon end),
                temp: (if ($slow.weatherTemp | length) > 0 then $slow.weatherTemp else $weather.temp end),
                apparent: $weather.apparent
            },
            cameraActive:$slow.cameraActive,
            call: {active:$callActive, app:$callApp, duration:$callDuration},
            system: {wifi:$slow.wifi, activeWindow:$activeWindow, fullscreen:$fullscreen}
        }'
}

case "${1:-snapshot}" in
    snapshot) json_snapshot ;;
    play-pause|next|previous)
        timeout 2 playerctl "$1" >/dev/null 2>&1 || true ;;
    seek)
        timeout 2 playerctl position "${2:-0}" >/dev/null 2>&1 || true ;;
    volume)
        wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ "${2:-50}%" >/dev/null 2>&1 || true ;;
    mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle >/dev/null 2>&1 || true ;;
    mic-volume)
        wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SOURCE@ "${2:-50}%" >/dev/null 2>&1 || true ;;
    mic-mute) wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle >/dev/null 2>&1 || true ;;
    shuffle) playerctl shuffle Toggle >/dev/null 2>&1 || true ;;
    loop)
        current=$(playerctl loop 2>/dev/null || echo None)
        [[ "$current" == "None" ]] && next=Playlist || { [[ "$current" == "Playlist" ]] && next=Track || next=None; }
        playerctl loop "$next" >/dev/null 2>&1 || true ;;
    brightness) brightnessctl set "${2:-50}%" >/dev/null 2>&1 || true ;;
    lyrics) lyrics_for "${2:-}" "${3:-}" "${4:-0}" ;;
    visualizer)
        if command -v cava >/dev/null 2>&1; then
            exec cava -p <(printf '%s\n' '[general]' 'bars = 16' 'framerate = 30' '[output]' 'method = raw' 'raw_target = /dev/stdout' 'data_format = ascii' 'ascii_max_range = 100' 'channels = mono' '[smoothing]' 'monstercat = 1' 'waves = 0')
        fi ;;
esac
