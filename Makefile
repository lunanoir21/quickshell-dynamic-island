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
#
# The actual cropping lives in tools/capture.sh, not here — see AGENTS.md for
# why a hand-rolled `grim -g` is the one thing not to do on this project.
SS_DIR ?= /tmp/dynamic-island-screenshots
SS_DELAY ?= 0.6

.PHONY: help ss \
	open close toggle settings settings-ss \
	mic-on mic-off camera-on camera-off \
	battery-animation battery-full battery-half battery-low battery-alert battery-reset \
	timer stopwatch focus alarm time-toggle time-reset timer-done timer-dismiss \
	notification call reply dismiss-call \
	lyrics-toggle clock-toggle mixer-toggle queue-toggle \
	language-tr language-en language-toggle \
	hover-on hover-off compact-on compact-off \
	theme-black theme-umbra theme-gray theme-white theme-gold theme-amber theme-red theme-cycle \
	demo demo-dry

help:
	@echo "Dynamic Island widget test shortcuts (edit Makefile to add more):"
	@echo ""
	@echo "  island:      open close toggle"
	@echo "  settings:    settings (opens to Appearance — settings-ss to capture it)"
	@echo "  privacy:     mic-on mic-off camera-on camera-off"
	@echo "  battery:     battery-animation battery-full battery-half battery-low battery-alert battery-reset"
	@echo "  time:        timer stopwatch focus alarm time-toggle time-reset"
	@echo "               timer-done timer-dismiss"
	@echo "  notify:      notification call reply dismiss-call"
	@echo "  panel:       lyrics-toggle clock-toggle mixer-toggle queue-toggle"
	@echo "  language:    language-tr language-en language-toggle"
	@echo "  behaviour:   hover-on hover-off compact-on compact-off"
	@echo "  theme:       theme-black theme-umbra theme-gray theme-white theme-gold theme-amber theme-red theme-cycle"
	@echo ""
	@echo "  Append -ss to any of the above to also grab a screenshot once the"
	@echo "  card has settled, e.g. make battery-alert-ss. make ss on its own"
	@echo "  just grabs whatever the island looks like right now."
	@echo ""
	@echo "  demo:        record the front-page tour to docs/demo.mp4"
	@echo "  demo-dry:    play the same scene list without recording"
	@echo ""
	@echo "SHELL_QML=$(SHELL_QML)  SS_DIR=$(SS_DIR)  SS_DELAY=$(SS_DELAY)"

ss:
	@tools/capture.sh --dir "$(SS_DIR)" --delay 0 manual

# Generic: any target's -ss suffix runs the target, waits SS_DELAY for the
# card to settle, then screenshots the island. Applies to every recipe below
# without needing a screenshot variant hand-written for each one. An explicit
# rule (like settings-ss, below) always wins over this pattern, so the one
# target that isn't the island can still override which surface gets cropped.
%-ss: %
	@sleep $(SS_DELAY)
	@tools/capture.sh --dir "$(SS_DIR)" --delay 0 $*

settings-ss: settings
	@sleep $(SS_DELAY)
	@tools/capture.sh --target settings --dir "$(SS_DIR)" --delay 0 settings

# ------------------------------------------------------------------- island
open:
	$(IPC) open
close:
	$(IPC) close
toggle:
	$(IPC) toggle
# Opens the settings window — a separate layer-shell surface from the island,
# which is why it needs its own screenshot target (settings-ss, above) rather
# than the generic %-ss pattern.
settings:
	$(IPC) settingsSection appearance

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
theme-gold:
	$(IPC) theme gold
theme-amber:
	$(IPC) theme amber
theme-red:
	$(IPC) theme red
theme-cycle:
	$(IPC) theme cycle

# ---------------------------------------------------------------------- tour
demo:
	tools/demo.sh
demo-dry:
	tools/demo.sh --dry-run
