# Fires one-off IPC calls at a running instance of the island so each widget
# can be exercised on demand — a low battery, an incoming call, a mic toggle —
# without waiting for the real hardware/app state to produce it.
#
# Requires the shell to actually be running (see hyprland.conf's SUPER bind,
# or start it yourself: `qs -p $(SHELL_QML)`). Override the path if your
# checkout lives somewhere other than the default keybind's location:
#   make SHELL_QML=/path/to/Shell.qml mic-on
SHELL_QML ?= $(HOME)/.config/hypr/scripts/quickshell/Shell.qml
IPC := qs -p $(SHELL_QML) ipc call dynamicIsland

# Screenshots (make <target>-ss, e.g. `make battery-alert-ss`): a plain CLI
# flag isn't something a Make target can read — argv after the target name is
# make's own option parsing, not ours — so an -ss *suffix* is the closest
# equivalent that's actually valid make syntax. SS_DELAY gives the card's
# entrance animation time to settle before the capture; SS_DIR is where shots
# land.
SS_DIR ?= /tmp/dynamic-island-screenshots
SS_DELAY ?= 0.6

.PHONY: help ss \
	open close toggle \
	mic-on mic-off camera-on camera-off \
	battery-animation battery-full battery-half battery-low battery-alert battery-reset \
	timer stopwatch focus alarm time-toggle time-reset timer-done timer-dismiss \
	notification call reply dismiss-call \
	lyrics-toggle clock-toggle mixer-toggle queue-toggle \
	language-tr language-en language-toggle \
	hover-on hover-off compact-on compact-off \
	theme-black theme-umbra theme-gray theme-white theme-cycle

help:
	@echo "Dynamic Island widget test shortcuts (edit Makefile to add more):"
	@echo ""
	@echo "  island:      open close toggle"
	@echo "  privacy:     mic-on mic-off camera-on camera-off"
	@echo "  battery:     battery-animation battery-full battery-half battery-low battery-alert battery-reset"
	@echo "  time:        timer stopwatch focus alarm time-toggle time-reset"
	@echo "               timer-done timer-dismiss"
	@echo "  notify:      notification call reply dismiss-call"
	@echo "  panel:       lyrics-toggle clock-toggle mixer-toggle queue-toggle"
	@echo "  language:    language-tr language-en language-toggle"
	@echo "  behaviour:   hover-on hover-off compact-on compact-off"
	@echo "  theme:       theme-black theme-umbra theme-gray theme-white theme-cycle"
	@echo ""
	@echo "  Append -ss to any of the above to also grab a screenshot of the"
	@echo "  island once the card has settled, e.g. make battery-alert-ss"
	@echo "  make ss on its own just grabs whatever the island looks like now."
	@echo ""
	@echo "SHELL_QML=$(SHELL_QML)  SS_DIR=$(SS_DIR)  SS_DELAY=$(SS_DELAY)"

# Crops to the island's own layer-shell surface (namespace qs-dynamic-island)
# rather than a fixed region or an interactive slurp select, so it stays
# correct across monitors/resolutions and needs no pointer input.
define screenshot
	@command -v grim >/dev/null || { echo "grim not found (pacman -S grim)"; exit 1; }
	@command -v jq >/dev/null || { echo "jq not found (pacman -S jq)"; exit 1; }
	@mkdir -p "$(SS_DIR)"
	@geom="$$(hyprctl layers -j | jq -r '[.[] | .levels[] | .[] | select(.namespace=="qs-dynamic-island")][0] | select(. != null) | "\(.x),\(.y) \(.w)x\(.h)"')"; \
	if [ -z "$$geom" ]; then echo "qs-dynamic-island layer not found — is the shell running?"; exit 1; fi; \
	file="$(SS_DIR)/$(1)-$$(date +%H%M%S).png"; \
	grim -g "$$geom" "$$file" && echo "-> $$file"
endef

ss:
	$(call screenshot,manual)

# Generic: any target's -ss suffix runs the target, waits SS_DELAY for the
# card to settle, then screenshots. Applies to every recipe below without
# needing a screenshot variant hand-written for each one.
%-ss: %
	@sleep $(SS_DELAY)
	$(call screenshot,$*)

# ------------------------------------------------------------------- island
open:
	$(IPC) open
close:
	$(IPC) close
toggle:
	$(IPC) toggle

# ------------------------------------------------------------------ privacy
mic-on:
	$(IPC) deviceEvent microphone true 62
mic-off:
	$(IPC) deviceEvent microphone false 0
camera-on:
	$(IPC) deviceEvent camera true 0
camera-off:
	$(IPC) deviceEvent camera false 0

# ------------------------------------------------------------------ battery
# Overrides the displayed level/status for ~8s — long enough to see the
# colour and the charging pulse without needing real hardware.
battery-animation:
	$(IPC) battery 55 Charging
battery-full:
	$(IPC) battery 92 Discharging
battery-half:
	$(IPC) battery 35 Discharging
battery-low:
	$(IPC) battery 12 Discharging
# Fires the critical-battery alert card directly (see showBatteryAlert in
# DynamicIsland.qml), independent of the override above.
battery-alert:
	$(IPC) batteryAlert 8
# Drops the override early instead of waiting out its ~8s expiry.
battery-reset:
	$(IPC) batteryReset

# ---------------------------------------------------------------- time tools
timer:
	$(IPC) timeMode timer
stopwatch:
	$(IPC) timeMode stopwatch
focus:
	$(IPC) timeMode focus
alarm:
	$(IPC) timeMode alarm
# Start/pause and reset whichever mode is on the stage.
time-toggle:
	$(IPC) timeToggle
time-reset:
	$(IPC) timeReset
# Raises the completion card (and plays the chime) without waiting out a real
# countdown, so the arrival animation and the dismissal paths stay testable.
timer-done:
	$(IPC) timerTest
timer-dismiss:
	$(IPC) timerDismiss

# --------------------------------------------------------------- notify/call
notification:
	$(IPC) notify "Test App" "Test notification" "This is a sample notification body." ""
# A minimal incoming-call notification: the island recognises a call from its
# own accept/decline action ids (see isIncomingCall/classifyCallActions), and
# the accept/decline buttons call back into notificationBridge — which only
# exists on the real, running shell, so pressing them here is a no-op unless
# that bridge is wired up. Good enough to see the ring/card animation.
call:
	$(IPC) notifyWithActions "Signal" "Incoming call" "Calling…" "" \
		"$$(printf '[{"id":"accept","text":"Answer"},{"id":"decline","text":"Decline"}]' | base64 -w0)" \
		"test-call-1" false ""
reply:
	$(IPC) notifyWithActions "Messages" "Ada" "Are you around?" "" \
		"$$(printf '[{"id":"inline-reply","text":"Reply"}]' | base64 -w0)" \
		"test-reply-1" true "Type a reply…"
dismiss-call:
	$(IPC) dismissCall

# ------------------------------------------------------------------- panels
lyrics-toggle:
	$(IPC) lyrics
clock-toggle:
	$(IPC) clock
mixer-toggle:
	$(IPC) appVolumes
queue-toggle:
	$(IPC) queue

# ----------------------------------------------------------------- language
language-tr:
	$(IPC) language tr
language-en:
	$(IPC) language en
language-toggle:
	$(IPC) language toggle

# ---------------------------------------------------------------- behaviour
hover-on:
	$(IPC) hover true
hover-off:
	$(IPC) hover false
compact-on:
	$(IPC) compactControls true
compact-off:
	$(IPC) compactControls false

# -------------------------------------------------------------------- theme
theme-black:
	$(IPC) theme black
theme-umbra:
	$(IPC) theme umbra
theme-gray:
	$(IPC) theme gray
theme-white:
	$(IPC) theme white
theme-cycle:
	$(IPC) theme cycle
