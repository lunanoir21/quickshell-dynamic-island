#!/usr/bin/env bash
set -u

base_dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell/dynamic-island"
weather_cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/dynamic-island/weather.json"
weather_lock="$base_dir/weather.lock"
slow_cache="$base_dir/slow.json"
slow_lock="$base_dir/slow.lock"
mkdir -p "$base_dir"
mkdir -p "$(dirname "$weather_cache")"

# Seconds a cached value may go stale before a background refresh is kicked off.
slow_ttl=4
weather_ttl=900

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

    local media status title artist art length_us length_s position_us position_s player lyrics shuffle loop
    # One templated call replaces eight separate playerctl invocations.
    media=$(timeout 1 playerctl metadata --format \
        '{{status}}§|§{{title}}§|§{{artist}}§|§{{mpris:artUrl}}§|§{{mpris:length}}§|§{{playerName}}§|§{{position}}§|§{{xesam:asText}}' \
        2>/dev/null | head -n1 || true)
    # Split on the §|§ delimiter; parameter expansion handles multi-char safely.
    status=${media%%§|§*}
    local rest=${media#*§|§}
    title=${rest%%§|§*}; rest=${rest#*§|§}
    artist=${rest%%§|§*}; rest=${rest#*§|§}
    art=${rest%%§|§*}; rest=${rest#*§|§}
    length_us=${rest%%§|§*}; rest=${rest#*§|§}
    player=${rest%%§|§*}; rest=${rest#*§|§}
    position_us=${rest%%§|§*}; rest=${rest#*§|§}
    lyrics=${rest%%§|§*}
    lyrics=$(printf '%s' "$lyrics" | tr '\n' ' ' | head -c 300)

    [[ "$status" == "Playing" || "$status" == "Paused" ]] || status="Stopped"
    [[ "$length_us" =~ ^[0-9]+$ ]] || length_us=0
    [[ "$position_us" =~ ^[0-9]+$ ]] || position_us=0
    length_s=$((length_us / 1000000))
    position_s=$((position_us / 1000000))

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
        --arg player "$player" --arg lyrics "$lyrics" --arg shuffle "$shuffle" --arg loop "$loop" \
        --argjson length "$length_s" --argjson position "$position_s" \
        --argjson volume "$volume" --argjson muted "$muted" --argjson micVolume "$mic_volume" \
        --argjson micMuted "$mic_muted" --argjson micActive "$mic_active" --argjson brightness "$brightness" \
        --argjson battery "$battery" --arg batteryStatus "$battery_status" \
        --argjson weather "$weather" --argjson slow "$slow" \
        --arg activeWindow "$active_window" --argjson fullscreen "$fullscreen" \
        '{
            media: {status:$status,title:$title,artist:$artist,art:$art,player:$player,lyrics:$lyrics,shuffle:$shuffle,loop:$loop,length:$length,position:$position},
            volume:$volume, muted:$muted, micVolume:$micVolume, micMuted:$micMuted, micActive:$micActive,
            brightness:$brightness, battery:$battery, batteryStatus:$batteryStatus,
            batteryTime:$slow.batteryTime, bluetooth:$slow.bluetooth,
            weather: {
                icon: (if ($slow.weatherIcon | length) > 0 then $slow.weatherIcon else $weather.icon end),
                temp: (if ($slow.weatherTemp | length) > 0 then $slow.weatherTemp else $weather.temp end),
                apparent: $weather.apparent
            },
            cameraActive:$slow.cameraActive,
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
    visualizer)
        if command -v cava >/dev/null 2>&1; then
            exec cava -p <(printf '%s\n' '[general]' 'bars = 16' 'framerate = 30' '[output]' 'method = raw' 'raw_target = /dev/stdout' 'data_format = ascii' 'ascii_max_range = 100' 'channels = mono' '[smoothing]' 'monstercat = 1' 'waves = 0')
        fi ;;
esac
