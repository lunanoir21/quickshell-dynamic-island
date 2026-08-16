# Working on this project

A Quickshell overlay for Hyprland: one layer-shell surface pinned to the top of
the screen. The QML is the product; `backend.sh` is a thin shell layer that
reports state and performs actions. There is no build step — Quickshell watches
the files and reloads on save.

This file is the contract for anyone (human or agent) making changes here.

---

## Before every commit

Three things, in order. None are optional.

### 1. Write the changelog entry

`docs/changelog.json` is the single source of truth for what shipped. Both the
site's front page and its archive page read it, so an entry written once
appears in both.

Add a new object at the **top** of `releases[]`:

```json
{
  "version": "2026.08.17",
  "date": "2026-08-17",
  "title": "A short sentence, not a version bump",
  "summary": "Two or three sentences: what changed and why it was worth doing.",
  "changes": [
    { "type": "added",   "text": "..." },
    { "type": "changed", "text": "..." },
    { "type": "fixed",   "text": "..." },
    { "type": "removed", "text": "..." }
  ],
  "shots": [
    { "src": "screenshots/changelog/name.png", "alt": "...", "caption": "...", "text": "...", "wide": true }
  ]
}
```

- **Versions are dates** (`YYYY.MM.DD`), because releases here are "the day the
  work landed", not semver.
- If a release lands on a date that already has an entry, **edit that entry**
  rather than adding a second one for the same day.
- `type` is one of `added` / `changed` / `fixed` / `removed`.
- Write what the change *does for the person using it*, not which function was
  edited. "The chime picker ran past the right edge of the window — four of the
  eleven sounds could not be reached" beats "fixed ChimePicker layout".
- `alt` is for screen readers and describes the image. `caption` is a short
  bold label. `text` is the sentence under it. `wide` makes the card span the
  full grid.

Validate before committing:

```sh
jq -e '.releases | length' docs/changelog.json
```

### 2. Take the screenshots

**Always `tools/capture.sh`. Never a raw `grim`, never a hand-written
rectangle, never a full-screen capture as a fallback.**

```sh
tools/capture.sh media                        # the island → docs/screenshots/media.png
tools/capture.sh --target settings themes     # the settings window
tools/capture.sh --dir docs/screenshots/changelog --target settings my-change
```

Why this matters: both surfaces are **full-screen** layer-shell windows with
their content centred inside. `hyprctl layers` reports the screen, not the
pill — so a hand-picked crop is wrong the moment the island resizes, and a
wrong crop on a full-screen surface **captures whatever the user has open
behind it**. The script asks the running shell where its content actually is
(the `islandWidth` / `islandHeight` / `islandTopMargin` IPC properties on
`dynamicIsland`) and crops to exactly that.

Set the widget up over IPC first, then capture:

```sh
qs -p ~/.config/hypr/scripts/quickshell/Shell.qml ipc call dynamicIsland settingsSection appearance
tools/capture.sh --target settings --delay 1.5 themes
```

`make <target>-ss` does the same for the Makefile's widget shortcuts.

The `full` target exists for deliberate whole-desktop shots only. It will
capture every window on screen. Do not reach for it because a crop failed —
fix the crop.

### 3. Re-record the tour if the visuals changed

`docs/demo.mp4` is the video on the front page: every feature in order, on an
empty desktop.

```sh
tools/demo.sh --dry-run   # play the scenes, record nothing — check the script first
tools/demo.sh             # record → docs/demo.mp4
```

Only the newest video is committed; it replaces the previous one. Re-record
when the island's appearance changes in a way the current video no longer
shows. A copy edit or a backend fix does not need a new recording.

The scene list lives in `run_scenes()` in that script and is the video's
script — edit it there when a feature is added or removed.

---

## Verifying a change

Quickshell reloads on save and writes to a log. **A QML error does not surface
in the UI — it silently refuses to load the whole config, and the shell keeps
running the last good version.** If a change appears to do nothing, read the
log before assuming anything about the code:

```sh
tail -20 "$(ls -t /run/user/$UID/quickshell/by-id/*/log.log | head -1)"
```

`Configuration Loaded` means it took. `Failed to load configuration` names the
file and line.

`qmllint <file>.qml` catches syntax errors but **not** type errors like the two
below, so it is a first pass, not a verdict.

### Traps that have actually cost time here

- **`font.pixelSize` is an int.** `12.5` fails the whole config to load with
  `Invalid property assignment: int expected`.
- **`Behavior` cannot drive a `readonly property`.** It needs to take the
  property over mid-transition; the engine refuses. Drop `readonly` and keep
  the binding as the only writer.
- **A `NumberAnimation` that targets a property destroys any binding on it.**
  If a property needs both an entrance animation and a live binding (hover
  scale, say), animate a wrapper element and leave the bound property alone.
- **Under a comma-decimal locale (`tr_TR`), `printf '%.1f'` and `sleep 2.5`
  both reject a decimal point.** Shell scripts here set `LC_NUMERIC=C`.

---

## Do not do these

- **Do not change the user's settings as a side effect.** `theme`, `language`,
  `hover` and friends call `saveSettings()` — they write to
  `~/.config/quickshell/dynamic-island/settings.json` permanently. If a script
  or a test cycles through themes, it must record the original and put it back
  (`tools/demo.sh` does this). Filming a demo should not repaint someone's
  desktop.
- **Do not capture the full screen** unless that is the explicit goal.
- **Do not add an accent colour.** The interface is greyscale everywhere except
  the green and red on a call's answer/decline buttons, and the site follows
  the same rule. Change types in the changelog are told apart by their label
  and weight, never by hue.
- **Do not add a weather feature back.** It was removed deliberately: two
  network calls and a geolocation lookup per refresh, for data nothing on the
  island displayed.
- **Do not hand-write release markup into `index.html` or `changelog.html`.**
  Both build themselves from `changelog.json`. Editing the markup creates a
  second copy that will drift.

---

## Layout

| Path | What it is |
| --- | --- |
| `DynamicIsland.qml` | The island itself — state, IPC handler, every surface it shows |
| `SettingsMenu.qml` | The settings window, a separate layer-shell surface |
| `Strings.qml` | Every user-visible string, in English and Turkish |
| `PixelClock.qml`, `PixelText.qml`, `pixelfont.js` | The 5×7 matrix type |
| `backend.sh` | State snapshot (`snapshot`) and actions, as one JSON object |
| `tools/capture.sh` | The only way screenshots are taken |
| `tools/demo.sh` | Records the tour video |
| `docs/changelog.json` | Every release — the source both pages read |
| `docs/index.html` | The front page; shows the newest release |
| `docs/changelog.html` | The archive; shows all of them |
| `Makefile` | IPC shortcuts for exercising widgets by hand |

Both READMEs (`README.md`, `README.tr.md`) document the same thing in two
languages. A change to one that is user-visible belongs in the other.

### Adding a string

Add it to `Strings.qml` with both languages, never inline in a QML file. They
are ordinary properties, so switching language re-evaluates every binding that
reads one and the interface relabels itself with no reload.

### Adding a theme

Add the palette to `themePalettes` in `DynamicIsland.qml`, append its name to
`themeOrder`, and add its display name to `Strings.qml` and to
`themeDisplayName()` in `SettingsMenu.qml`. The settings picker reads
`themeOrder`, so it needs no further edit.
