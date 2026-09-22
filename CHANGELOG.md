# Changelog

All notable changes to Dynamic Island are listed here, newest first. Versions
are the date the work landed (`YYYY.MM.DD`), because that is how this project
releases — not semver.

This file and [CHANGELOG.tr.md](CHANGELOG.tr.md) are the only places release
notes are written. `python3 scripts/changelog.py` copies the latest release
into both READMEs, under "What changed", and regenerates `docs/changelog.json`,
which the website reads. The Turkish changelog must list the same versions.

Each release adds three things the plain format has no slot for: a `**title**`
line, a short `summary` paragraph, and a `### Shots` section:

    ## [2026.08.17] - 2026-08-17

    **A short sentence, not a version bump**

    Two or three sentences: what changed and why it was worth doing.

    ### Added
    - One change per bullet; wrapped lines are indented two spaces.

    ### Shots
    - ![what the image shows](screenshots/name.png "wide") — **caption** — the
      sentence underneath. The image's markdown title `"wide"` makes it span
      the grid.

## [2026.09.23] - 2026-09-23

**Proactive hardening pass ahead of an Omarchy marketplace submission**

Before submitting to the Omarchy marketplace, a security and robustness audit
went through everything the island takes from the outside world: strings from
notifications and media players, external shell commands, background processes
and the settings file. Every finding was fixed up front rather than waiting
for a reviewer to hit it — no visual changes, just the same island made harder
to wedge, confuse or inject into.

### Fixed

- Text arriving from notifications, media players, the volume mixer and IPC
  commands now always renders as plain text with a length cap at the point it
  enters the island, so a hostile or broken app can no longer smuggle styled
  markup into the UI or grow a label without bound.
- External commands that previously ran with no deadline (mixer volume changes,
  bluetooth/wifi/battery reads, media player actions) are now time-bounded, and
  the background locks guarding them recover on their own if left stale — one
  hung command can no longer freeze polling or make buttons dead until reload.
- Dismissing a timed alarm now actually releases the keyboard lock the alert
  took, instead of leaving the island locked open with an exclusive keyboard
  grab and nothing on screen to explain why.
- The lyrics search and the state snapshot process now have stall deadlines —
  a track change can no longer leave the lyrics pane stuck "searching" forever,
  and a hung snapshot can no longer freeze every value the island shows until
  it is reloaded.
- The track queue panel is capped in size and no longer recomputes every row's
  position offset from scratch on every tick, so a player advertising a huge
  queue cannot make the panel grow without bound or cost O(N²) per update.
- The volume-mixer and player-switcher rows only rebuild when their contents
  actually change, instead of tearing down and recreating every row on every
  refresh.
- Saving settings on one screen now merges with what is already on disk and
  only writes the keys that screen actually changed, so two monitors saving
  near-simultaneously no longer overwrite each other's choice (last-writer-wins).
- Fetches of remote artwork and lyrics are capped in size and stale cache files
  are swept, so a misbehaving endpoint cannot fill the disk.

## [2026.08.17] - 2026-08-17

**YouTube covers, fixed for non-English locales**

Under locales like tr_TR.UTF-8, glibc's regex engine treats [A-Za-z] as
collation-aware rather than a plain byte range. That silently broke the video-id
match in backend.sh for any id containing a letter Turkish collation sorts
outside the perceived A-Z/a-z range, so the island fell back to a blank cover
for a large share of videos instead of fetching one.

### Fixed

- YouTube cover art failed to fetch for many videos under non-C locales
  (confirmed on tr_TR.UTF-8) — the video-id regex is now matched in the C locale
  regardless of the system locale.

## [2026.08.16] - 2026-08-16

**Settings that move, and three themes that are not grey**

The settings window was legible but static: every control changed state by
cutting to it. It now animates what it is doing — the selection slides,
switches slide, sections fade in — and it finally follows the theme it is used
to pick. Gold, Amber and Red join the four neutrals.

### Added

- Gold, Amber and Red themes. Each is built on a tinted dark base rather than
  another neutral, so the surface hints at the colour before the accent
  confirms it.
- Keyboard navigation in settings — Up and Down move between sections.

### Changed

- The settings window follows the active theme instead of staying fixed to
  Umbra, and crossfades between palettes rather than cutting.
- The sidebar's active section is now one indicator that slides between items,
  instead of each row fading its own background in and out.
- On/off controls are real sliding switches rather than pills reading ON and
  OFF, and segmented pickers slide a single highlight to the picked option.
- Theme cards are miniature islands drawn in each theme's own fill, hairline
  and accent, laid out as a grid with a staggered entrance.
- Switching sections fades and rises the new content instead of hard-cutting
  to it.
- Appearance is split into Theme, Borders and Media Panel — three groups that
  each do one thing, replacing one vague Surfaces group with a stray sentence
  wedged inside it.

### Fixed

- The chime test button now turns into Stop while a sound plays and can
  actually stop it, instead of silently restarting the sound on every click.
- The chime picker ran past the right edge of the window — four of the eleven
  sounds could not be reached at all. It wraps now, and picking one plays it.

### Removed

- Weather, entirely. It cost two network calls and a geolocation lookup per
  refresh and nothing on the island ever displayed it.
- Four dead backend commands (volume, mic-volume, brightness, seek) that the
  UI had long since stopped calling, and nine unused interface strings.

### Shots

- ![The Appearance section of the settings window in the Amber theme, showing
  seven theme cards in a grid](screenshots/changelog/themes.png "wide") —
  **Seven themes, shown as themes** — Each card draws a shrunken island in that
  theme's own colours. The active one carries a glow and a check badge in its
  accent — and the window around it is wearing the theme too.
- ![The time tools settings section with eleven chime chips wrapped onto one
  row](screenshots/changelog/chime-test.png) — **Eleven chimes, all
  reachable** — The old picker ran off the edge of the window past the seventh
  sound. Picking one now plays it — choosing a sound you cannot hear is not a
  choice.
- ![Notification settings rows with sliding toggle switches and a segmented
  duration picker](screenshots/changelog/settings-switches.png) — **Switches
  that slide** — Position and fill say on or off, instead of a 10px word — and
  the duration picker slides one highlight rather than repainting two segments.

## [2026.08.15] - 2026-08-15

**It keeps time now — and tells you when the time is up**

A timer, a stopwatch with laps, a focus cycle and an alarm, rebuilt as one
instrument that retunes rather than four widgets splitting the width. Finishing
is an event: the island changes shape, chimes, and waits to be answered. A tool
left running stays visible on the collapsed pill.

### Added

- Time tools: timer, stopwatch with laps, focus cycle and alarm, as one
  instrument with four modes.
- A completion card that chimes and waits — dismissed with Esc, Space, Return
  or a click, but not by the pointer that happened to be where it appeared.
- A running tool stays on the collapsed pill as a capsule, turning amber and
  doubling pace inside the last minute.
- A Makefile of IPC shortcuts for exercising every widget without waiting for
  real hardware state.

### Shots

- ![The time page with a running timer, a progress strip of square cells,
  duration presets and a rail of four modes](screenshots/time-tools.png "wide")
  — **One instrument, four modes** — The readout uses the same 5×7 matrix as
  the clock, so its digits roll the same way, and progress is drawn from those
  same square cells rather than a bar parked underneath.
- ![A completion card reading Time's up with a dismiss button](screenshots/time-alert.png)
  — **Finishing is an event** — Esc, Space, Return or a click — but not the
  pointer that happened to be where it appeared, and not the island collapsing.
- ![The collapsed pill carrying a green capsule with a running timer](screenshots/time-capsule.png)
  — **Still counting while closed** — Mode icon, live value, a drain line and
  a travelling sweep. Amber and twice the pace inside the last minute.

## [2026.08.14] - 2026-08-14

**Calls, a per-app mixer, and what plays next**

Incoming calls get the surface to themselves, every app that makes noise gets
its own fader, and the queue the player reports becomes something you can read.

### Added

- Incoming call handling, inferred from simultaneous playback and capture
  streams rather than any one app's API — so Signal, Telegram and WhatsApp are
  covered by one heuristic.
- A per-application volume mixer, grouped by app rather than by stream, so a
  browser with four tabs is one row.
- An up-next queue panel, marked experimental because most players never
  report one.

### Shots

- ![An incoming call card with answer and decline buttons](screenshots/call.png)
  — **The only colour in the project** — Green and red on answer and decline —
  the two controls where guessing wrong actually costs you something.

## [2026.08.09] - 2026-08-09

**Themes, a compact player, and audio that becomes the surface**

Four palettes to choose from, a player-only pill for people who do not want the
full panel, and a spectrum drawn from real audio.

### Added

- Four themes — Black, Umbra, Gray and White — applied to the island, its
  panels and its notifications at once.
- Compact media controls: a player-only pill that stays out of the way.
- A progress track on the mini player.
- Wave, Live and Calm animation variants sharing real cava data, at Soft,
  Balanced or Bold intensity.

### Shots

- ![Expanded Umbra media panel with a live audio spectrum](screenshots/changelog/media-animation.png "wide")
  — **Audio becomes the surface** — Wave, Live and Calm variants share real
  cava data; visibility can be set to Soft, Balanced or Bold.
- ![The compact player-only pill with a progress track](screenshots/changelog/mini-player.png)
  — **Player only** — For a still desktop: the pill carries the track and its
  progress, and nothing else.

## [2026.08.06] - 2026-08-06

**Two languages, synced lyrics, and replying without leaving**

The whole interface relabels itself between English and Turkish with no reload,
notifications can be answered in place, and lyrics arrive in time with the
track.

### Added

- English and Turkish, switched live — every string is an ordinary property,
  so changing the language re-evaluates every binding that reads one.
- Inline reply on notifications that support it.
- Synced lyrics from LRCLIB, cached locally.

### Shots

- ![The lyrics panel with the current line highlighted](screenshots/lyrics.png)
  — **The line being sung** — The highlight is the whole point of synced
  lyrics, so it is what the panel leads with.
- ![A notification with an inline reply field](screenshots/reply.png) —
  **Answer without leaving** — For the notifications that support it — the
  rest keep their actions.

## [2026.08.05] - 2026-08-05

**Initial release**

One always-on-top surface pinned to the top edge: a compact pill that grows
under the pointer into media controls, live meters and a pixel-art clock.

### Added

- The island itself — hover to expand, 90ms grace on leave, or click-to-open
  for a still desktop.
- Media controls, volume, brightness and microphone meters, and device
  indicators for microphone and camera.
- A pixel-art clock drawn from a 5×7 matrix, in pixel, segment and plain
  styles.

### Shots

- ![The collapsed pill](screenshots/pill.png) — **Collapsed** — What sits on
  the screen when nothing needs saying.
- ![The pixel-art clock](screenshots/clock.png) — **The clock** — A 5×7
  matrix, with an optional dormant grid behind the lit cells.