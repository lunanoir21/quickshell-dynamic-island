import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: window

    // Resolved against this file rather than a fixed path, so the project runs
    // from wherever it was cloned.
    readonly property string backend: String(Qt.resolvedUrl("backend.sh")).replace("file://", "")

    // Every glyph in the UI comes from one Nerd Font. Point this at whichever
    // patched font is installed.
    property string iconFont: "Iosevka Nerd Font"

    // ---------------------------------------------------------------- state
    // Open/close has exactly two deliberate inputs: optional pointer hover, or
    // a latched open state (keyboard/pin/click mode). Alerts still open on their
    // own and close on a timer.
    property bool hovering: false
    property bool lockedOpen: false
    property bool notificationVisible: false
    property bool deviceEventVisible: false
    readonly property bool alertVisible: notificationVisible || deviceEventVisible || callVisible || timeAlertVisible
    // The big settings window covers the whole screen while open, so the
    // island underneath has no business popping open just because the
    // pointer happens to pass over its (now inert) spot on the way there.
    readonly property bool expanded: !settingsOpen
        && ((hoverToOpen && hovering) || lockedOpen || alertVisible)

    // Set while a slider is being dragged so the pointer straying a few pixels
    // outside the island mid-drag can't collapse it. Guarded by a dead-man timer
    // because a lost release event used to leave this stuck on forever, which
    // silently disabled every close path.
    property bool interacting: false

    property var islandState: ({media:{status:"Stopped",title:"",artist:"",art:"",player:"",shuffle:"Off",loop:"None",length:0,position:0},volume:0,muted:false,micVolume:0,micMuted:false,micActive:false,brightness:0,battery:100,batteryStatus:"",batteryTime:"",bluetooth:"",bluetoothPowered:false,cameraActive:false,call:{active:false,app:"",duration:0},system:{wifi:"",wifiPowered:true,activeWindow:"",fullscreen:0}})

    property int previousVolume: -1
    property int previousBrightness: -1
    property int previousBattery: -1
    property bool previousBatteryCharging: false

    // Lets `battery <level> <status>` (see the IPC handler / Makefile) stand
    // in for the real reading for a few seconds, so the level-based colour and
    // the charging animation can be exercised without actually draining or
    // plugging in the machine. Expires on its own rather than needing a
    // separate "stop testing" call.
    property var batteryOverride: null
    readonly property int displayBattery: batteryOverride ? batteryOverride.level : islandState.battery
    readonly property string displayBatteryStatus: batteryOverride ? batteryOverride.status : islandState.batteryStatus
    readonly property bool batteryCharging: displayBatteryStatus === "Charging"
    readonly property int batteryWarnThreshold: 50
    readonly property int batteryCriticalThreshold: 20
    readonly property color batteryColor: displayBattery <= batteryCriticalThreshold
        ? themeStatusAlert
        : (displayBattery < batteryWarnThreshold ? themeStatusWarn : themeStatusLive)
    property bool previousMicMuted: false
    property bool previousMicActive: false
    property bool previousCameraActive: false
    property bool previousCallActive: false
    property bool startupRead: false

    property string hudKind: ""
    property int hudValue: 0
    property string activityText: ""

    property string notificationApp: ""
    property string notificationIcon: ""
    property string notificationTitle: ""
    property string notificationBody: ""
    property string notificationUid: ""
    // Brief checkmark swap after a successful copy — not persisted past the
    // next notification, so it can't lie about a click that happened on a
    // completely different card.
    property bool notificationCopied: false
    // Set only when the sender attached a KDE-style "inline-reply" action —
    // Quickshell strips that action out of n.actions itself and surfaces it
    // as these two fields instead, so their presence already means the
    // sender opted in; no guessing needed on our end.
    property bool notificationHasReply: false
    property string notificationReplyPlaceholder: ""
    property string notificationReplyText: ""

    // ------------------------------------------------------------ call ring
    // Two independent signals feed this: a real incoming-call notification
    // (from the app's own D-Bus actions, so Answer/Reject are genuine) opens
    // the ring state; the PipeWire heuristic in backend.sh confirms/ends the
    // live state once audio actually starts flowing. Either can drive the
    // card alone — a call answered on the phone/another device still shows
    // up here once the audio streams appear, even with no ring beforehand.
    property bool callRinging: false
    property bool callAnswering: false
    property string callApp: ""
    property string callTitle: ""
    property string callUid: ""
    property string callAcceptId: ""
    property string callDeclineId: ""
    // Manual close: the PipeWire heuristic has no notion of "the user closed
    // this," so without a flag of its own a call the user dismissed while
    // still live (or one the heuristic never lets go of) would just reappear
    // on the next poll. Cleared whenever a genuinely new call starts, so a
    // later, unrelated call still rings/shows normally.
    property bool callDismissed: false
    // Mirror of callDismissed for callAutoPopup === false: there the card
    // starts closed and the user opts in, rather than starting open and
    // opting out, so it needs its own flag rather than reusing callDismissed
    // inverted (a call that starts, gets opened, and ends must not leave the
    // *next* call already open).
    property bool callManualOpen: false
    // Whether a call is actually happening, ignoring open/closed state — this
    // is what the status-strip call chip watches, so the chip stays put (and
    // can still open/reopen the card) even while the card itself is closed.
    readonly property bool callOngoing: callRinging || !!islandState.call.active
    readonly property bool callCardOpen: window.callAutoPopup ? !callDismissed : callManualOpen
    readonly property bool callVisible: callCardOpen && callOngoing
    readonly property string callDisplayApp: callApp !== "" ? callApp
        : (islandState.call.app !== "" ? islandState.call.app.charAt(0).toUpperCase() + islandState.call.app.slice(1) : i18n.callFallbackApp)
    readonly property string callDisplayTitle: callTitle !== "" ? callTitle : i18n.voiceCall

    function classifyCallActions(actions) {
        let accept = "", decline = ""
        for (let i = 0; i < actions.length; i++) {
            let hay = (String(actions[i].id || "") + " " + String(actions[i].text || "")).toLowerCase()
            if (!accept && /accept|answer|kabul|cevapla/.test(hay)) accept = actions[i].id
            else if (!decline && /decline|reject|hangup|reddet|kapat/.test(hay)) decline = actions[i].id
        }
        if (!accept && !decline) {
            if (actions.length >= 2) { accept = actions[0].id; decline = actions[1].id }
            else if (actions.length === 1) decline = actions[0].id
        }
        return {accept: accept, decline: decline}
    }

    // Restricted to known VoIP apps with an incoming-call action attached —
    // matching on stray words like "call" in an ordinary chat message would
    // pop the ring card for things that were never a call.
    function isIncomingCall(app, title, body, actions) {
        if (!/signal|telegram|whatsapp/i.test(app)) return false
        if (actions.length === 0) return false
        if (/accept|answer|decline|reject|kabul|reddet|cevapla/i.test(JSON.stringify(actions))) return true
        return /arama|call|calling|ringing|ar[ıi]yor/i.test(title + " " + body)
    }

    function showIncomingCall(app, title, actions, uid) {
        // Guards on callOngoing rather than callVisible: with auto-popup off
        // the card can be ongoing-but-closed, and a second ring notification
        // for that same call must not reset it back to "just started ringing".
        if (window.callOngoing) return
        let mapped = classifyCallActions(actions)
        window.notificationVisible = false
        window.deviceEventVisible = false
        window.deviceEventQueue = []
        window.callDismissed = false
        window.callManualOpen = false
        window.callApp = app
        window.callTitle = title
        window.callUid = uid
        window.callAcceptId = mapped.accept
        window.callDeclineId = mapped.decline
        window.callAnswering = false
        window.callRinging = true
        callRingTimeout.restart()
    }

    function invokeCallAction(actionId) {
        if (window.callUid === "" || actionId === "") return
        // Targets Main.qml, not Shell.qml: whichever quickshell instance owns
        // org.freedesktop.Notifications is the one holding the live,
        // invokable Notification object, and on this setup that is the
        // standalone Main.qml process, not the copy of Main{} embedded in
        // Shell.qml (its NotificationServer loses the D-Bus name and never
        // receives anything).
        Quickshell.execDetached(["quickshell", "-p", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/Main.qml",
            "ipc", "call", "notificationBridge", "invokeAction", window.callUid, actionId])
    }

    function answerCall() {
        window.invokeCallAction(window.callAcceptId)
        window.callAnswering = true
        window.callRinging = false
        callRingTimeout.stop()
        // Stopping the ring timeout above removed the only thing that would
        // ever clear this state again — without a timeout of its own here,
        // a call that answers locally but never actually connects (heuristic
        // never sees a matching stream, far end never picks up, etc.) leaves
        // "Bağlanıyor…" stuck on screen forever.
        callConnectTimeout.restart()
    }

    function rejectCall() {
        window.invokeCallAction(window.callDeclineId)
        window.callRinging = false
        window.callAnswering = false
        callRingTimeout.stop()
        callConnectTimeout.stop()
    }

    function giveUpOnCall() {
        window.callRinging = false
        window.callAnswering = false
        callRingTimeout.stop()
        callConnectTimeout.stop()
    }

    // The explicit close button on the call card itself. Unlike giveUpOnCall()
    // (a timeout giving up on a call that never connected), this must hide a
    // call that IS still live per the PipeWire heuristic — otherwise the very
    // thing being closed reopens on the next snapshot poll.
    function dismissCallCard() {
        window.giveUpOnCall()
        window.callDismissed = true
        window.callManualOpen = false
    }

    Timer {
        id: callRingTimeout
        interval: window.callRingSeconds * 1000
        onTriggered: if (!window.islandState.call.active) window.giveUpOnCall()
    }

    Timer {
        id: callConnectTimeout
        interval: 15000
        onTriggered: if (!window.islandState.call.active) window.giveUpOnCall()
    }

    property string deviceEventType: ""
    property string deviceEventTitle: ""
    property string deviceEventSubtitle: ""
    property string deviceEventIcon: ""

    property string uiFont: bricolage.status === FontLoader.Ready ? bricolage.name : "Bricolage Grotesque"

    // ------------------------------------------------------------ language
    // Three sources, most specific first: what the user picked in the UI (saved
    // to disk so it survives a reload), then QS_ISLAND_LANG for people who set
    // their shell up declaratively, then the session locale so a fresh install
    // just speaks whatever the rest of the desktop does.
    property string langChoice: ""
    // Every monitor owns its own DynamicIsland instance. File watchers keep
    // preferences changed on one screen synchronized with the others.
    property bool settingsReady: false
    readonly property string lang: {
        if (langChoice === "tr" || langChoice === "en") return langChoice
        let forced = String(Quickshell.env("QS_ISLAND_LANG") || "").toLowerCase()
        if (forced.indexOf("tr") === 0) return "tr"
        if (forced.indexOf("en") === 0) return "en"
        let sys = String(Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES")
                         || Quickshell.env("LANG") || "").toLowerCase()
        return sys.indexOf("tr") === 0 ? "tr" : "en"
    }
    Strings { id: i18n; lang: window.lang }
    // Exposed so SettingsMenu.qml — a separate file/window — can reach the
    // same strings rather than duplicating Strings.qml's lookups.
    property alias i18n: i18n

    FileView {
        id: langFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
              + "/quickshell/dynamic-island/language"
        // Read synchronously during startup: an async read would paint the
        // whole island in the fallback language first and visibly relabel
        // itself a frame later.
        blockLoading: true
        // Missing on first run by definition — that is not worth a warning.
        printErrors: false
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onTextChanged: if (window.settingsReady) window.loadLanguage()
    }

    function setLanguage(code) {
        code = String(code || "").toLowerCase()
        if (code === "toggle") code = window.lang === "tr" ? "en" : "tr"
        if (code !== "tr" && code !== "en") return
        window.langChoice = code
        langFile.setText(code + "\n")
    }

    // ------------------------------------------------------------ settings
    // A gear chip in the status strip opens a small settings card of its own,
    // separate from the always-visible chips, holding the handful of toggles
    // that don't need to be one click away at all times.
    property bool settingsOpen: false
    // Set by the settingsSection IPC call just before opening; the menu picks it
    // up and clears it, so reopening later stays where the user last was.
    property string settingsSectionRequest: ""

    // ---------------------------------------------------------------- theme
    // Four palettes behind one token set. The white theme is why these are
    // tokens rather than a couple of if-checks: on a light ground every
    // hairline has to flip from white-alpha to black-alpha and the on/off
    // pill has to invert, so no colour outside the media panel can stay a
    // literal.
    //
    // themeName is a string, not an index — it is what lands in settings.json,
    // and a name survives reordering the list where a number would silently
    // repaint the whole shell.
    property string themeName: "umbra"
    readonly property var themePalettes: ({
        "black": {
            islandFill: "#f20b0c0f", surface: "#15161a", surfaceAlt: "#22242a",
            text: "#fafafa", subtext: "#c6c8cd", muted: "#9498a2",
            line: "#1fffffff", lineStrong: "#36ffffff",
            chip: "#14ffffff", chipHover: "#28ffffff",
            on: "#f2f3f5", onText: "#0b0c0f",
            track: "#303239", scrim: "#ad000000", grid: "#1d1f24"
        },
        "umbra": {
            islandFill: "#f7000000", surface: "#070707", surfaceAlt: "#171717",
            text: "#f5f2ec", subtext: "#c1bdb5", muted: "#918d86",
            line: "#1cffffff", lineStrong: "#32ffffff",
            chip: "#14ffffff", chipHover: "#29ffffff",
            on: "#eeeae2", onText: "#050505",
            track: "#242424", scrim: "#bd000000", grid: "#171717"
        },
        "gray": {
            islandFill: "#f4383a40", surface: "#44474f", surfaceAlt: "#52555e",
            text: "#ffffff", subtext: "#d4d6dc", muted: "#adb0b9",
            line: "#28ffffff", lineStrong: "#42ffffff",
            chip: "#1cffffff", chipHover: "#32ffffff",
            on: "#f4f5f7", onText: "#24262b",
            track: "#63666f", scrim: "#9e0a0b0e", grid: "#4d5058"
        },
        "white": {
            islandFill: "#faf9faf7", surface: "#ffffff", surfaceAlt: "#ebedf0",
            text: "#111318", subtext: "#3f434b", muted: "#676c76",
            line: "#26000000", lineStrong: "#42000000",
            chip: "#10000000", chipHover: "#22000000",
            on: "#181a1f", onText: "#ffffff",
            track: "#d3d6dc", scrim: "#70111418", grid: "#dfe2e7"
        },
        // A deep bronze-black rather than another near-black neutral, so the
        // theme reads as "gold" from the surface colour alone before the
        // accent ever shows up. The mustard-gold `on` is muted and metallic
        // on purpose — amber (below) is the louder, more saturated sibling.
        "gold": {
            islandFill: "#f5140f09", surface: "#120d08", surfaceAlt: "#221a10",
            text: "#f8ecd8", subtext: "#cdb896", muted: "#96836a",
            line: "#20f0d9b0", lineStrong: "#38f0d9b0",
            chip: "#16f3dcae", chipHover: "#2af3dcae",
            on: "#f0b93c", onText: "#241a08",
            track: "#2c2013", scrim: "#b3140f09", grid: "#1e170f"
        },
        "amber": {
            islandFill: "#f5121110", surface: "#141110", surfaceAlt: "#241c15",
            text: "#f7ede0", subtext: "#cdbba5", muted: "#978672",
            line: "#20ffb066", lineStrong: "#38ffb066",
            chip: "#16ffb055", chipHover: "#2affb055",
            on: "#ff9f1c", onText: "#241202",
            track: "#2e2116", scrim: "#b3141110", grid: "#1f1815"
        },
        // Wine-dark rather than neutral-black, the same way gold and amber
        // lean bronze and charcoal — the surface itself should hint at the
        // colour before the crimson accent confirms it. The accent sits low
        // enough in luminance to need light text on top, unlike gold/amber's
        // dark-on-bright pairing.
        "red": {
            islandFill: "#f5170a0c", surface: "#130a0b", surfaceAlt: "#241214",
            text: "#f8e9ea", subtext: "#d0b3b6", muted: "#9c7c7f",
            line: "#20f2a3a8", lineStrong: "#3af2a3a8",
            chip: "#16f0a0a5", chipHover: "#2cf0a0a5",
            on: "#e5484d", onText: "#fdf3f2",
            track: "#331a1c", scrim: "#b3170a0c", grid: "#1f1315"
        }
    })
    readonly property var themeOrder: ["black", "umbra", "gray", "white", "gold", "amber", "red"]
    // Falls back rather than resolving to undefined: a settings.json edited by
    // hand to a name that no longer exists must not leave every colour unset.
    readonly property var palette: themePalettes[themeName] || themePalettes["umbra"]

    readonly property color themeIslandFill: palette.islandFill
    readonly property color themeSurface: palette.surface
    readonly property color themeSurfaceAlt: palette.surfaceAlt
    readonly property color themeText: palette.text
    readonly property color themeSubtext: palette.subtext
    readonly property color themeMuted: palette.muted
    readonly property color themeLine: showBorders ? palette.line : "transparent"
    readonly property color themeLineStrong: showBorders ? palette.lineStrong : "transparent"
    readonly property color themeChip: palette.chip
    readonly property color themeChipHover: palette.chipHover
    readonly property color themeOn: palette.on
    readonly property color themeOnText: palette.onText
    readonly property color themeTrack: palette.track
    readonly property color themeScrim: palette.scrim
    readonly property color themeGrid: palette.grid
    readonly property color themeHudFill: palette.islandFill

    // Deliberately outside the palette, same as the call ring: these mark a
    // live/dangerous state (mic or camera in use, something muted) rather than
    // decorate the UI, so they stay the same hue in all four themes instead of
    // being tinted by whichever one is active.
    readonly property color themeStatusLive: "#3aa863"
    readonly property color themeStatusAlert: "#c24a4e"
    readonly property color themeStatusWarn: "#d1a53c"
    readonly property bool mediaUsesDarkSurface: mediaSurfaceMode === "dark"
    readonly property color mediaPanelText: mediaUsesDarkSurface ? "#f5f5f5" : themeText
    readonly property color mediaPanelSubtext: mediaUsesDarkSurface ? "#a8a8a8" : themeSubtext
    readonly property color mediaPanelMuted: mediaUsesDarkSurface ? "#7f7f7f" : themeMuted
    readonly property color mediaPanelTrack: mediaUsesDarkSurface ? "#2b2b2b" : themeTrack
    readonly property color mediaPanelOn: mediaUsesDarkSurface ? "#ededed" : themeOn

    function setTheme(name) {
        if (!themePalettes[name]) return
        window.themeName = name
        window.saveSettings()
    }

    // --------------------------------------------------------- preferences
    property bool showBorders: true
    // How the island's top edge relates to the screen edge:
    //  - capsule:    floats with a gap, fully rounded (the original look)
    //  - soft-fused: flush against the edge, gently rounded top corners
    //  - notch:      flush, square-cornered joint carved with concave "ear"
    //                pieces the same colour as the screen - the actual
    //                technique real hardware notches use
    //  - halo:       capsule geometry, unchanged, plus a soft glow tinted
    //                with the active theme's accent (palette.on) behind it
    property string islandMountStyle: "capsule"
    readonly property var islandMountStyles: ["capsule", "soft-fused", "notch", "halo"]
    property bool hoverToOpen: true
    // "theme" follows the selected palette; "dark" is an explicit opt-in for
    // people who want the player to stay black while the rest of the island
    // changes. Older installs default to theme instead of inheriting the old,
    // accidentally locked mediaAlwaysDark flag.
    property string mediaSurfaceMode: "theme"
    property string clockStyle: "pixel"
    property bool clock24Hour: true
    property bool clockSeconds: true
    property bool clockDate: true
    property bool clockGrid: true

    property bool callAutoPopup: true
    property int callRingSeconds: 35
    property bool callPulseRing: true

    property int notificationSeconds: 5
    property bool notificationInlineReply: true
    property bool notificationAppIcon: true

    property bool mediaLyricsEnabled: true
    property bool mediaSpectrumEnabled: true
    property bool mediaAlbumArtEnabled: true
    property bool compactMediaControls: true
    property string mediaAnimationStyle: "wave"
    property int mediaAnimationIntensity: 100
    property bool mediaAutoExpandTrack: true
    property bool mediaColorGlow: true
    property bool mediaProgressBar: true

    property int timerDefaultMinutes: 5
    property int focusDefaultMinutes: 25
    property int breakDefaultMinutes: 5
    property bool autoStartBreak: false
    property string timeChimeVolume: "normal"

    property bool appVolumeEnabled: true
    // "chips" names the players, "logos" shows their icons only, "segment" puts
    // one segmented pill in the status strip. Which reads best depends on how
    // many players the user actually runs, so it stays a preference.
    property string playerSwitcherStyle: "chips"
    // "list" is title/artist only and always works; "covers" and "timeline"
    // need artwork and track lengths, which a TrackList may simply not carry.
    property string queueStyle: "list"
    // Off by default, and labelled experimental in both the settings row and the
    // panel itself: MPRIS has no general queue concept, so this only ever works
    // on the few players implementing the optional TrackList interface.
    property bool queueEnabled: false

    FileView {
        id: settingsFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
              + "/quickshell/dynamic-island/settings.json"
        blockLoading: true
        printErrors: false
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onTextChanged: if (window.settingsReady) window.loadSettings()
    }

    function saveSettings() {
        settingsFile.setText(JSON.stringify({
            themeName: window.themeName,
            showBorders: window.showBorders,
            islandMountStyle: window.islandMountStyle,
            hoverToOpen: window.hoverToOpen,
            mediaSurfaceMode: window.mediaSurfaceMode,
            clockStyle: window.clockStyle,
            clock24Hour: window.clock24Hour,
            clockSeconds: window.clockSeconds,
            clockDate: window.clockDate,
            clockGrid: window.clockGrid,
            callAutoPopup: window.callAutoPopup,
            callRingSeconds: window.callRingSeconds,
            callPulseRing: window.callPulseRing,
            notificationSeconds: window.notificationSeconds,
            notificationInlineReply: window.notificationInlineReply,
            notificationAppIcon: window.notificationAppIcon,
            mediaLyricsEnabled: window.mediaLyricsEnabled,
            mediaSpectrumEnabled: window.mediaSpectrumEnabled,
            mediaAlbumArtEnabled: window.mediaAlbumArtEnabled,
            compactMediaControls: window.compactMediaControls,
            mediaAnimationStyle: window.mediaAnimationStyle,
            mediaAnimationIntensity: window.mediaAnimationIntensity,
            mediaAutoExpandTrack: window.mediaAutoExpandTrack,
            mediaColorGlow: window.mediaColorGlow,
            mediaProgressBar: window.mediaProgressBar,
            timerDefaultMinutes: window.timerDefaultMinutes,
            focusDefaultMinutes: window.focusDefaultMinutes,
            breakDefaultMinutes: window.breakDefaultMinutes,
            autoStartBreak: window.autoStartBreak,
            timeChimeVolume: window.timeChimeVolume,
            appVolumeEnabled: window.appVolumeEnabled,
            queueEnabled: window.queueEnabled,
            playerSwitcherStyle: window.playerSwitcherStyle,
            queueStyle: window.queueStyle,
            timeChimeEnabled: window.timeChimeEnabled,
            chimeSound: window.chimeSound
        }, null, 2) + "\n")
    }

    // Every key is read through one of these two helpers so a settings.json
    // carrying a half-written or wrong-typed value falls back to the default
    // rather than assigning undefined into a typed property.
    function readBool(parsed, key, fallback) {
        return typeof parsed[key] === "boolean" ? parsed[key] : fallback
    }
    function readChoice(parsed, key, allowed, fallback) {
        return allowed.indexOf(parsed[key]) !== -1 ? parsed[key] : fallback
    }

    function loadLanguage() {
        let saved = String(langFile.text() || "").trim().toLowerCase()
        if (saved === "tr" || saved === "en") window.langChoice = saved
    }

    function loadSettings() {
        try {
            let raw = String(settingsFile.text() || "").trim()
            if (!raw) return
            let p = JSON.parse(raw)

            window.themeName = readChoice(p, "themeName", window.themeOrder, window.themeName)
            window.showBorders = readBool(p, "showBorders", window.showBorders)
            // Migrates the old boolean (pre-mount-style-picker) setting:
            // islandHaloEnabled: true became the "halo" choice rather than
            // silently reverting everyone who had it on back to "capsule".
            let mountFallback = p.islandHaloEnabled === true ? "halo" : window.islandMountStyle
            window.islandMountStyle = readChoice(p, "islandMountStyle", window.islandMountStyles, mountFallback)
            window.hoverToOpen = readBool(p, "hoverToOpen", window.hoverToOpen)
            window.mediaSurfaceMode = readChoice(p, "mediaSurfaceMode", ["theme", "dark"], window.mediaSurfaceMode)

            window.clockStyle = readChoice(p, "clockStyle", ["pixel", "segment", "plain"], window.clockStyle)
            window.clock24Hour = readBool(p, "clock24Hour", window.clock24Hour)
            window.clockSeconds = readBool(p, "clockSeconds", window.clockSeconds)
            window.clockDate = readBool(p, "clockDate", window.clockDate)
            window.clockGrid = readBool(p, "clockGrid", window.clockGrid)

            window.callAutoPopup = readBool(p, "callAutoPopup", window.callAutoPopup)
            window.callRingSeconds = readChoice(p, "callRingSeconds", [15, 35, 60], window.callRingSeconds)
            window.callPulseRing = readBool(p, "callPulseRing", window.callPulseRing)

            window.notificationSeconds = readChoice(p, "notificationSeconds", [3, 5, 8], window.notificationSeconds)
            window.notificationInlineReply = readBool(p, "notificationInlineReply", window.notificationInlineReply)
            window.notificationAppIcon = readBool(p, "notificationAppIcon", window.notificationAppIcon)

            window.mediaLyricsEnabled = readBool(p, "mediaLyricsEnabled", window.mediaLyricsEnabled)
            window.mediaSpectrumEnabled = readBool(p, "mediaSpectrumEnabled", window.mediaSpectrumEnabled)
            window.mediaAlbumArtEnabled = readBool(p, "mediaAlbumArtEnabled", window.mediaAlbumArtEnabled)
            window.compactMediaControls = readBool(p, "compactMediaControls", window.compactMediaControls)
            let savedAnimation = p.mediaAnimationStyle === "pulse" ? "live" : p.mediaAnimationStyle
            window.mediaAnimationStyle = ["wave", "live", "calm"].indexOf(savedAnimation) !== -1
                                       ? savedAnimation : window.mediaAnimationStyle
            window.mediaAnimationIntensity = readChoice(p, "mediaAnimationIntensity", [45, 70, 100], window.mediaAnimationIntensity)
            window.mediaAutoExpandTrack = readBool(p, "mediaAutoExpandTrack", window.mediaAutoExpandTrack)
            window.mediaColorGlow = readBool(p, "mediaColorGlow", window.mediaColorGlow)
            window.mediaProgressBar = readBool(p, "mediaProgressBar", window.mediaProgressBar)

            window.timerDefaultMinutes = readChoice(p, "timerDefaultMinutes", [1, 3, 5, 10, 15, 25, 30], window.timerDefaultMinutes)
            window.focusDefaultMinutes = readChoice(p, "focusDefaultMinutes", [15, 20, 25, 30, 45, 60], window.focusDefaultMinutes)
            window.breakDefaultMinutes = readChoice(p, "breakDefaultMinutes", [3, 5, 10, 15], window.breakDefaultMinutes)
            window.autoStartBreak = readBool(p, "autoStartBreak", window.autoStartBreak)
            window.timeChimeVolume = readChoice(p, "timeChimeVolume", ["soft", "normal", "loud"], window.timeChimeVolume)

            window.appVolumeEnabled = readBool(p, "appVolumeEnabled", window.appVolumeEnabled)
            window.queueEnabled = readBool(p, "queueEnabled", window.queueEnabled)
            window.playerSwitcherStyle = readChoice(p, "playerSwitcherStyle",
                ["chips", "logos", "segment"], window.playerSwitcherStyle)
            window.queueStyle = readChoice(p, "queueStyle",
                ["list", "covers", "timeline"], window.queueStyle)
            window.timeChimeEnabled = readBool(p, "timeChimeEnabled", window.timeChimeEnabled)
            window.chimeSound = readChoice(p, "chimeSound",
                ["timesup", "chime1", "chime2", "chime3", "chime4", "chime5", "chime6", "chime7", "chime8", "chime9", "chime10"], window.chimeSound)
        } catch (error) { /* missing or corrupt on first run — defaults stand */ }
    }

    Component.onCompleted: {
        window.loadLanguage()
        window.loadSettings()
        window.settingsReady = true
    }

    readonly property bool previewMode: Quickshell.env("QS_ISLAND_PREVIEW") === "1"
    property bool fullscreenActive: !previewMode && Number(islandState.system.fullscreen || 0) > 0
    property date currentTime: new Date()

    // Lets the pixel clock be pulled up while something is still playing.
    property bool showClock: false
    readonly property bool idleView: showClock || mediaStatus === "Stopped"
    readonly property bool compactPlayerMode: !hoverToOpen && compactMediaControls
        && mediaStatus !== "Stopped"

    // ------------------------------------------------------- animation drivers
    // Every looping animation drives one of these plain numbers and resets it on
    // stop. Running `SequentialAnimation on <visual property>` directly leaves
    // the property frozen wherever the loop happened to be when the condition
    // went false, which is what left half-faded rings and stalled bars on screen.
    property real playGlow: 0
    property real ringPulse: 1
    property real visualPhase: 0
    property var visualLevels: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
    readonly property bool cavaLive: cavaProcess.running

    SequentialAnimation on playGlow {
        running: window.mediaStatus === "Playing" && !window.fullscreenActive
        loops: Animation.Infinite
        onRunningChanged: if (!running) window.playGlow = 0
        NumberAnimation { from: 0; to: 1; duration: 1300; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 1300; easing.type: Easing.InOutSine }
    }

    // Rests at 1, where the ring it drives is fully faded out and invisible.
    NumberAnimation on ringPulse {
        running: window.mediaStatus === "Playing" && !window.expanded && !window.fullscreenActive
        loops: Animation.Infinite
        from: 0; to: 1
        duration: 1100
        easing.type: Easing.OutCubic
        onRunningChanged: if (!running) window.ringPulse = 1
    }

    NumberAnimation on visualPhase {
        // The mic card's own waveform and breathing ring used to wait on
        // islandState.micActive specifically — a value that only updates on
        // the next backend poll (up to ~2s away), so the card could appear
        // with its bars frozen for a moment even during real mic use, and
        // stay frozen the whole time under the `deviceEvent microphone`
        // test IPC (which doesn't touch islandState at all). Driving it off
        // "the mic card is on screen" instead means the animation always
        // matches what the card is claiming, with no separate poll to wait on.
        running: window.mediaStatus === "Playing" || window.islandState.micActive || window.callRinging || window.callAnswering
            || (window.deviceEventVisible && (window.deviceEventType === "battery" || window.deviceEventType === "microphone"))
            // The completion card breathes for as long as it is up, and the
            // final ten seconds of a countdown pulse on the same shared sine.
            || window.timeAlertVisible || window.timeUrgent || window.timeCapsuleUrgent
        loops: Animation.Infinite
        from: 0; to: Math.PI * 2
        duration: 1100
        onRunningChanged: if (!running) window.visualPhase = 0
    }

    // Slow breathing glow for the battery glyph while charging — rests at 0
    // (fully lit, no glow) so stopping it never leaves the icon mid-fade.
    property real batteryPulse: 0
    SequentialAnimation on batteryPulse {
        running: window.batteryCharging && !window.fullscreenActive
        loops: Animation.Infinite
        onRunningChanged: if (!running) window.batteryPulse = 0
        NumberAnimation { from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 900; easing.type: Easing.InOutSine }
    }

    // ----------------------------------------------------------------- media
    // Transport controls apply locally first so the UI reacts on click instead
    // of waiting for the next backend poll. Overrides expire once a snapshot
    // has had time to catch up.
    property string mediaStatusOverride: ""
    property string mediaShuffleOverride: ""
    property string mediaLoopOverride: ""
    // Same idea for the player switcher: the pick is persisted by backend.sh, so
    // without this the pressed chip would stay unlit for up to a full poll.
    property string selectedPlayerOverride: ""
    readonly property string mediaStatus: mediaStatusOverride !== "" ? mediaStatusOverride : islandState.media.status
    readonly property string mediaShuffle: mediaShuffleOverride !== "" ? mediaShuffleOverride : islandState.media.shuffle
    readonly property string mediaLoop: mediaLoopOverride !== "" ? mediaLoopOverride : islandState.media.loop

    readonly property var mediaPlayers: islandState.players || []

    function isPlayerSelected(entry) {
        if (!entry) return false
        return window.selectedPlayerOverride !== ""
            ? entry.name === window.selectedPlayerOverride
            : entry.selected === true
    }

    // The chip row sits in the 142px-wide gap under the cover, which fits three.
    // The selected player is always kept among them, so the lit chip can never
    // be the one that got folded away; the remainder collapses into a +N chip.
    readonly property var visiblePlayers: {
        let all = window.mediaPlayers
        if (all.length <= 3) return all
        let picked = []
        let rest = []
        for (let i = 0; i < all.length; i++) {
            if (window.isPlayerSelected(all[i])) picked.push(all[i])
            else rest.push(all[i])
        }
        return picked.concat(rest).slice(0, 3)
    }

    // playerctl reports instance names like "chromium.instance1"; the desktop
    // lookup wants the bare application, so the suffix goes before asking.
    function resolvePlayerIcon(entry) {
        if (!entry) return ""
        return window.resolveAppIcon(entry.label) || window.resolveAppIcon(entry.name)
    }

    // Advances to the first player the row had no room to show.
    function cyclePlayer() {
        let shown = window.visiblePlayers.map(entry => entry.name)
        for (let i = 0; i < window.mediaPlayers.length; i++) {
            let name = window.mediaPlayers[i].name
            if (shown.indexOf(name) === -1) { window.selectPlayer(name); return }
        }
    }

    Timer {
        id: mediaOverrideTimer
        interval: 1000
        onTriggered: {
            window.mediaStatusOverride = ""
            window.mediaShuffleOverride = ""
            window.mediaLoopOverride = ""
            window.selectedPlayerOverride = ""
        }
    }

    // Playback position only arrives with each backend poll, which makes the
    // progress bar step in visible jumps. Advance it locally between polls and
    // resync whenever the reported value drifts (seek, track change).
    property real mediaPosition: 0
    readonly property bool mediaLengthKnown: (islandState.media.length || 0) > 0
    Timer { id: positionSettleTimer; interval: 900 }

    Timer {
        interval: 250
        repeat: true
        running: window.mediaStatus === "Playing" && !window.interacting
        onTriggered: {
            let limit = window.islandState.media.length || 0
            let next = window.mediaPosition + 0.25
            window.mediaPosition = limit > 0 ? Math.min(limit, next) : next
        }
    }

    function syncPosition(reported) {
        if (window.interacting || positionSettleTimer.running) return
        let value = Number(reported) || 0
        if (Math.abs(value - window.mediaPosition) > 1.4) window.mediaPosition = value
    }

    // ------------------------------------------------------------- app mixer
    // Chip-toggled panels, so they follow the lyrics rule rather than the alert
    // cards': they take over the media slot at the panel's existing size and
    // never resize it, because resizing under a pointer that is mid-reach moves
    // the very control the user is going for.
    property bool showAppVolumes: false
    property bool showQueue: false
    // Kept as an internal compatibility flag for old settings/runtime state.
    // There is deliberately no UI or navigation path to quick settings now.
    property bool showQuickSettings: false
    property bool showCalendarPage: false
    property bool showTimePage: false
    property int calendarMonthOffset: 0

    // ------------------------------------------------------------ time tools
    // One instrument that changes what it is, rather than four widgets sharing
    // the stage: at 780px wide, three columns gave every tool ~230px and none
    // of them enough. The rail underneath keeps the other three visible with
    // their live values, so promoting one to the stage hides nothing.
    property string timeMode: "timer"
    readonly property var timeModes: ["timer", "stopwatch", "focus", "alarm"]

    property int countdownDuration: 300
    property int countdownSeconds: countdownDuration
    property bool countdownRunning: false

    // Elapsed-time based rather than an accumulating counter: the stopwatch is
    // the one tool here that shows hundredths, where the drift of a repeating
    // timer would be visible within a minute. The countdowns keep their simple
    // per-second decrement — a second of drift over 25 minutes is not legible,
    // and the deadline maths is not worth the extra pause/resume states.
    property bool stopwatchRunning: false
    property double stopwatchBase: 0
    property double stopwatchStart: 0
    property int stopwatchMs: 0
    property var stopwatchLaps: []

    property bool pomodoroWorkPhase: true
    property int pomodoroSeconds: 1500
    property bool pomodoroRunning: false
    property int pomodoroCycles: 0

    property int alarmHour: (new Date()).getHours()
    property int alarmMinute: ((new Date()).getMinutes() + 5) % 60
    property bool alarmEnabled: false
    property string lastAlarmKey: ""

    // The completion card. Kept separate from notificationVisible so a finished
    // timer is never swallowed by Do Not Disturb — the user started this one
    // themselves, which is exactly the thing DND is not meant to hide.
    // Persisted, unlike the rest of the time state: a sound that plays when
    // nobody asked for one is the kind of thing that has to stay off once it
    // has been turned off.
    property bool timeChimeEnabled: true
    property string chimeSound: "timesup"
    property bool timeAlertVisible: false
    property bool timeAlertArmed: false
    property bool timeAlertPulse: false
    property string timeAlertKind: ""
    property string timeAlertTitle: ""
    property string timeAlertDetail: ""
    property string timeAlertIcon: ""
    // Runtime-only: suppresses new notification cards while on, the same
    // way Android's Do Not Disturb does. Calls and device-privacy cards
    // still get through — those are not "notifications" to silence, they
    // are the two things DND is least meant to hide.
    property bool dndActive: false
    readonly property var appStreams: islandState.apps || []
    readonly property var mediaQueue: islandState.queue || ({ supported: false, tracks: [] })

    // How far off a queued track is: whatever is left of the current one, plus
    // every track before it. A player that reports no lengths gets a bare
    // position marker instead of a fabricated time.
    function queueOffsetLabel(index) {
        let tracks = window.mediaQueue.tracks || []
        let total = Math.max(0, (window.islandState.media.length || 0) - window.mediaPosition)
        let known = (window.islandState.media.length || 0) > 0
        for (let i = 0; i < index && i < tracks.length; i++) {
            let len = Number(tracks[i].length) || 0
            if (len > 0) total += len
            else known = false
        }
        if (!known) return "#" + (index + 1)
        return "+" + window.formatTime(total)
    }

    // Which optional sections backend.sh should build this poll. Both are shell
    // work nobody should pay for while the panels are closed.
    readonly property string snapshotMode: showAppVolumes ? "apps" : (showQueue ? "queue" : "")

    onShowQueueChanged: if (showQueue) {
        showAppVolumes = false
        showCalendarPage = false
        showTimePage = false
        delayedRefresh.restart()
    }

    onShowAppVolumesChanged: if (showAppVolumes) {
        showQueue = false
        showCalendarPage = false
        showTimePage = false
        // The list is only collected while a panel is open, so the first frame
        // would otherwise be empty for up to a full poll interval.
        delayedRefresh.restart()
    }

    onShowCalendarPageChanged: if (showCalendarPage) {
        showAppVolumes = false
        showQueue = false
        showTimePage = false
        showQuickSettings = false
    }

    onShowTimePageChanged: if (showTimePage) {
        showAppVolumes = false
        showQueue = false
        showCalendarPage = false
        showQuickSettings = false
    }

    function pageNext() {
        window.lockedOpen = true
        if (window.showCalendarPage) window.showCalendarPage = false
        else window.showTimePage = true
    }
    function pagePrev() {
        window.lockedOpen = true
        if (window.showTimePage) window.showTimePage = false
        else window.showCalendarPage = true
    }

    function twoDigits(value) { return String(Math.max(0, value)).padStart(2, "0") }
    function clockDuration(seconds) {
        const safe = Math.max(0, Number(seconds) || 0)
        return window.twoDigits(Math.floor(safe / 60)) + ":" + window.twoDigits(Math.floor(safe % 60))
    }
    // Hundredths rather than milliseconds: three digits of subsecond change too
    // fast to read, and the pixel matrix would just look like noise.
    function stopwatchLabel(ms) {
        const safe = Math.max(0, Number(ms) || 0)
        const totalSeconds = Math.floor(safe / 1000)
        return window.twoDigits(Math.floor(totalSeconds / 60)) + ":"
             + window.twoDigits(totalSeconds % 60) + "."
             + window.twoDigits(Math.floor((safe % 1000) / 10))
    }

    // --- what the hero shows, per mode -------------------------------------
    readonly property string timeReadout: {
        if (timeMode === "stopwatch") return stopwatchLabel(stopwatchMs)
        if (timeMode === "focus") return clockDuration(pomodoroSeconds)
        if (timeMode === "alarm") return twoDigits(alarmHour) + ":" + twoDigits(alarmMinute)
        return clockDuration(countdownSeconds)
    }
    readonly property bool timeModeRunning: {
        if (timeMode === "stopwatch") return stopwatchRunning
        if (timeMode === "focus") return pomodoroRunning
        if (timeMode === "alarm") return alarmEnabled
        return countdownRunning
    }
    // 0..1 of the way through. The stopwatch counts up with no end, so it fills
    // across its current minute rather than faking a total it does not have,
    // and the alarm fills across the hours still to wait.
    readonly property real timeProgress: {
        if (timeMode === "stopwatch") return (stopwatchMs % 60000) / 60000
        if (timeMode === "focus") {
            const total = pomodoroWorkPhase ? 1500 : 300
            return 1 - Math.max(0, Math.min(1, pomodoroSeconds / total))
        }
        if (timeMode === "alarm") {
            const now = currentTime.getHours() * 60 + currentTime.getMinutes()
            const target = alarmHour * 60 + alarmMinute
            const away = (target - now + 1440) % 1440
            return 1 - (away / 1440)
        }
        if (countdownDuration <= 0) return 0
        return 1 - Math.max(0, Math.min(1, countdownSeconds / countdownDuration))
    }
    // The last ten seconds are a real state change — about to fire — so they
    // get the warn hue. Nothing else on this page is allowed colour.
    readonly property bool timeUrgent: {
        if (timeMode === "timer") return countdownRunning && countdownSeconds <= 10 && countdownSeconds > 0
        if (timeMode === "focus") return pomodoroRunning && pomodoroSeconds <= 10 && pomodoroSeconds > 0
        return false
    }
    readonly property color timeAccent: timeAlertVisible
        ? (timeAlertPulse ? Qt.rgba(themeStatusAlert.r, themeStatusAlert.g, themeStatusAlert.b, 0.5 + Math.abs(Math.sin(visualPhase * 3)) * 0.5) : themeStatusAlert)
        : (timeUrgent ? themeStatusWarn : (timeModeRunning ? themeStatusLive : themeMuted))

    function timeModeLabel(mode) {
        if (mode === "stopwatch") return i18n.tmStopwatch
        if (mode === "focus") return i18n.tmFocus
        if (mode === "alarm") return i18n.tmAlarm
        return i18n.tmTimer
    }
    function timeModeIcon(mode) {
        if (mode === "stopwatch") return "󰔛"
        if (mode === "focus") return "󰔟"
        if (mode === "alarm") return "󰀠"
        return "󰥔"
    }
    // The value each rail chip reports while another mode owns the stage. This
    // is the whole reason the rail exists, so it shows the live number, not the
    // mode's configured one.
    function timeModeValue(mode) {
        if (mode === "stopwatch") return stopwatchLabel(stopwatchMs)
        if (mode === "focus") return clockDuration(pomodoroSeconds)
        if (mode === "alarm") return twoDigits(alarmHour) + ":" + twoDigits(alarmMinute)
        return clockDuration(countdownSeconds)
    }
    function timeModeIsRunning(mode) {
        if (mode === "stopwatch") return stopwatchRunning
        if (mode === "focus") return pomodoroRunning
        if (mode === "alarm") return alarmEnabled
        return countdownRunning
    }

    // --- collapsed-pill capsule --------------------------------------------
    // A tool left counting is invisible the moment the island closes, which is
    // most of the time. The capsule is the only thing on the pill that reports
    // state the user set up themselves rather than state the machine happens to
    // be in, so it earns the space whenever something is actually running.
    readonly property int alarmSecondsAway: {
        const now = currentTime.getHours() * 3600 + currentTime.getMinutes() * 60 + currentTime.getSeconds()
        let away = (alarmHour * 3600 + alarmMinute * 60) - now
        if (away < 0) away += 86400
        return away
    }
    // Ten minutes out is where an alarm stops being a setting and starts being
    // something you plan the next few minutes around.
    readonly property bool alarmImminent: alarmEnabled && alarmSecondsAway <= 600

    readonly property string timeCapsuleMode: {
        // Whatever is about to fire outranks whatever merely started first.
        if (countdownRunning && countdownSeconds <= 10) return "timer"
        if (pomodoroRunning && pomodoroSeconds <= 10) return "focus"
        if (alarmEnabled && alarmSecondsAway <= 60) return "alarm"
        if (countdownRunning) return "timer"
        if (pomodoroRunning) return "focus"
        if (stopwatchRunning) return "stopwatch"
        if (alarmImminent) return "alarm"
        return ""
    }
    readonly property bool timeCapsuleVisible: timeCapsuleMode !== ""
    readonly property bool timeCapsuleUrgent: {
        if (timeCapsuleMode === "timer") return countdownSeconds <= 10
        if (timeCapsuleMode === "focus") return pomodoroSeconds <= 10
        if (timeCapsuleMode === "alarm") return alarmSecondsAway <= 60
        return false
    }
    // Hundredths are unreadable at pill scale and would rewrite the pill width
    // every 10ms, so the stopwatch shows plain mm:ss here.
    readonly property string timeCapsuleValue: {
        if (timeCapsuleMode === "stopwatch") return clockDuration(Math.floor(stopwatchMs / 1000))
        if (timeCapsuleMode === "focus") return clockDuration(pomodoroSeconds)
        if (timeCapsuleMode === "alarm") return clockDuration(alarmSecondsAway)
        return clockDuration(countdownSeconds)
    }
    readonly property real timeCapsuleProgress: {
        if (timeCapsuleMode === "stopwatch") return (stopwatchMs % 60000) / 60000
        if (timeCapsuleMode === "focus") {
            const total = pomodoroWorkPhase ? 1500 : 300
            return 1 - Math.max(0, Math.min(1, pomodoroSeconds / total))
        }
        if (timeCapsuleMode === "alarm") return 1 - Math.max(0, Math.min(1, alarmSecondsAway / 600))
        if (countdownDuration <= 0) return 0
        return 1 - Math.max(0, Math.min(1, countdownSeconds / countdownDuration))
    }
    readonly property color timeCapsuleColor: timeCapsuleUrgent ? themeStatusWarn : themeStatusLive

    // --- controls ----------------------------------------------------------
    function resetCountdown(minutes) {
        window.countdownRunning = false
        window.countdownDuration = Math.max(60, minutes * 60)
        window.countdownSeconds = window.countdownDuration
    }

    function resetPomodoro() {
        window.pomodoroRunning = false
        window.pomodoroSeconds = window.pomodoroWorkPhase ? 1500 : 300
    }

    function toggleStopwatch() {
        if (window.stopwatchRunning) {
            window.stopwatchBase = window.stopwatchMs
            window.stopwatchRunning = false
        } else {
            window.stopwatchStart = Date.now()
            window.stopwatchRunning = true
        }
    }
    function resetStopwatch() {
        window.stopwatchRunning = false
        window.stopwatchBase = 0
        window.stopwatchMs = 0
        window.stopwatchLaps = []
    }
    function recordLap() {
        if (window.stopwatchMs <= 0) return
        // Newest first, and only the last four are kept: the strip has room for
        // four and a scrolling lap list on a 324px surface would be unreadable.
        let laps = [window.stopwatchMs].concat(window.stopwatchLaps)
        window.stopwatchLaps = laps.slice(0, 4)
    }

    // Advancing the focus phase is the same operation whether the timer ran out
    // or the user skipped, so both paths go through here and the cycle counter
    // can never disagree with the phase.
    function advanceFocusPhase(completed) {
        if (window.pomodoroWorkPhase && completed) window.pomodoroCycles++
        window.pomodoroWorkPhase = !window.pomodoroWorkPhase
        window.pomodoroSeconds = window.pomodoroWorkPhase ? 1500 : 300
    }

    // One primary button across all four modes, so the control the hand goes to
    // never moves when the stage changes what it is.
    function timePrimaryAction() {
        if (window.timeMode === "stopwatch") { window.toggleStopwatch(); return }
        if (window.timeMode === "focus") { window.pomodoroRunning = !window.pomodoroRunning; return }
        if (window.timeMode === "alarm") {
            window.alarmEnabled = !window.alarmEnabled
            // Clearing the fired-key on every arm means re-arming for a time
            // that already passed today still fires, instead of being silently
            // swallowed as "already done".
            window.lastAlarmKey = ""
            return
        }
        if (window.countdownSeconds <= 0) window.countdownSeconds = window.countdownDuration
        window.countdownRunning = !window.countdownRunning
    }

    function timeResetAction() {
        if (window.timeMode === "stopwatch") { window.resetStopwatch(); return }
        if (window.timeMode === "focus") { window.resetPomodoro(); return }
        if (window.timeMode === "alarm") {
            window.alarmEnabled = false
            return
        }
        window.resetCountdown(window.countdownDuration / 60)
    }

    // "Start" only when there is nothing to come back to; a part-spent timer
    // says "Resume", because that is the promise the button is making.
    readonly property bool timeModeMidRun: {
        if (timeMode === "stopwatch") return !stopwatchRunning && stopwatchMs > 0
        if (timeMode === "focus") return !pomodoroRunning && pomodoroSeconds < (pomodoroWorkPhase ? 1500 : 300)
        if (timeMode === "alarm") return false
        return !countdownRunning && countdownSeconds > 0 && countdownSeconds < countdownDuration
    }
    readonly property string timePrimaryLabel: {
        if (timeMode === "alarm") return alarmEnabled ? i18n.tmDisarm : i18n.tmArm
        if (timeModeRunning) return i18n.tmPause
        return timeModeMidRun ? i18n.tmResume : i18n.tmStart
    }
    readonly property string timeStatusLabel: {
        if (timeMode === "alarm") return alarmEnabled ? i18n.tmAlarmArmed : i18n.tmAlarmOff
        if (timeModeRunning) return i18n.tmRunning
        return timeModeMidRun ? i18n.tmPaused : i18n.tmReady
    }

    // --- completion card ---------------------------------------------------
    // The island is hidden outright under a fullscreen window, so a card raised
    // there would fire into nothing. That is the one case that still falls back
    // to the notification daemon, which can draw over fullscreen.
    function raiseTimeAlert(kind, icon, title, detail) {
        // The chime plays either way. Under a fullscreen window the card can't
        // be drawn at all, which is exactly when being audible matters most.
        if (window.timeChimeEnabled) window.run(["chime", window.chimeSound])
        if (window.fullscreenActive) {
            window.runDirect(["notify-send", "-u", "critical", title, detail])
            return
        }
        window.timeAlertKind = kind
        window.timeAlertIcon = icon
        window.timeAlertTitle = title
        window.timeAlertDetail = detail
        window.notificationVisible = false
        window.deviceEventVisible = false
        window.timeAlertVisible = true
        window.timeAlertPulse = true
        timeAlertPulseTimer.restart()
        // If the island is collapsed, briefly expand it to show the alert
        if (!window.expanded && !window.lockedOpen) {
            window.lockedOpen = true
            alertExpandTimer.restart()
        }
        // The card arrives under wherever the pointer already is, and the
        // island shrinking to alert size hands that pointer straight to the
        // card's own dismiss target — which used to swallow the alert within a
        // frame of it appearing, before it could be read. Pointer dismissal is
        // held off until the entrance has actually played.
        window.timeAlertArmed = false
        timeAlertArming.restart()
        timeAlertTimeout.restart()
        timeAlertPop.restart()
    }

    // Keyboard dismissal deliberately ignores this: a keypress cannot arrive by
    // accident of where the pointer was resting.
    function dismissTimeAlertByPointer() {
        if (!window.timeAlertArmed) return
        window.dismissTimeAlert()
    }

    function dismissTimeAlert() {
        window.timeAlertVisible = false
        window.timeAlertArmed = false
        window.timeAlertPulse = false
        timeAlertArming.stop()
        timeAlertTimeout.stop()
        timeAlertPulseTimer.stop()
        alertExpandTimer.stop()
        window.run(["chime-stop"])
    }

    function calendarMonthName(month) {
        const tr = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
        const en = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return (window.lang === "tr" ? tr : en)[month]
    }

    function calendarWeekdayName(day) {
        const tr = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]
        const en = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return (window.lang === "tr" ? tr : en)[day]
    }

    readonly property var calendarMonthDate: new Date(currentTime.getFullYear(), currentTime.getMonth() + calendarMonthOffset, 1)

    function calendarCellDate(index) {
        const first = window.calendarMonthDate
        const mondayOffset = (first.getDay() + 6) % 7
        return new Date(first.getFullYear(), first.getMonth(), index - mondayOffset + 1)
    }

    function calendarIsToday(value) {
        return value.getFullYear() === currentTime.getFullYear()
            && value.getMonth() === currentTime.getMonth()
            && value.getDate() === currentTime.getDate()
    }

    function calendarIsCurrentMonth(value) {
        return value.getFullYear() === calendarMonthDate.getFullYear()
            && value.getMonth() === calendarMonthDate.getMonth()
    }

    function setAppVolume(entry, value) {
        if (!entry) return
        window.run(["app-volume", entry.indexes, String(Math.round(value))])
    }

    function toggleAppMute(entry) {
        if (!entry) return
        window.run(["app-mute", entry.indexes, entry.muted ? "0" : "1"])
    }

    // PulseAudio's application.name ("Firefox") and the actual binary ("floorp")
    // disagree often enough — forks, wrappers, Electron apps — that both are
    // worth trying before giving up and leaving the slot empty.
    function resolveStreamIcon(entry) {
        if (!entry) return ""
        return window.resolveAppIcon(entry.name) || window.resolveAppIcon(entry.binary)
    }

    // ----------------------------------------------------------------- lyrics
    // MPRIS has a lyrics field (xesam:asText) but essentially nothing populates
    // it — Spotify reports it as an empty string — so lines are fetched from
    // LRCLIB by backend.sh and cached there. See the note above lyrics_for().
    property bool showLyrics: false
    // [{ t: seconds, text: "..." }], ascending by t. Empty t on every entry
    // means the source had no timestamps (plain lyrics).
    property var lyricLines: []
    property bool lyricsSynced: false
    property bool lyricsLoading: false
    property string lyricsKey: ""

    // Identifies the track, not the playback state: this is what decides when
    // to go looking for a different set of lyrics.
    readonly property string trackKey: (islandState.media.artist || "") + "::track::" + (islandState.media.title || "")

    onTrackKeyChanged: window.reloadLyrics()

    // Switching lyrics off has to close the view as well as hide its chip,
    // otherwise a panel left on the lyrics slot keeps showing the last track's
    // lines with no control left to get back to the visualiser.
    onMediaLyricsEnabledChanged: {
        if (!mediaLyricsEnabled) showLyrics = false
        reloadLyrics()
    }

    function reloadLyrics() {
        let artist = String(window.islandState.media.artist || "").trim()
        let title = String(window.islandState.media.title || "").trim()
        window.lyricLines = []
        window.lyricsSynced = false
        window.lyricsKey = window.trackKey
        // No network round-trip at all while the feature is off.
        if (!window.mediaLyricsEnabled || artist === "" || title === "" || window.mediaStatus === "Stopped") {
            window.lyricsLoading = false
            lyricsProcess.running = false
            return
        }
        window.lyricsLoading = true
        lyricsProcess.running = false
        lyricsProcess.command = [window.backend, "lyrics", artist, title,
                                 String(Math.round(window.islandState.media.length || 0))]
        lyricsProcess.running = true
    }

    // LRC is "[mm:ss.cc] text" per line. Anything without a leading timestamp
    // is kept too — plain lyrics still beat showing nothing — but marks the
    // set as unsynced so the UI stops pretending to follow along.
    function parseLyrics(raw) {
        let out = []
        let synced = false
        let lines = String(raw).split("\n")
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i]
            if (line.trim() === "") continue
            // A single line can carry several timestamps for repeated choruses.
            let stamps = line.match(/\[\d+:\d+(?:[.:]\d+)?\]/g)
            let text = line.replace(/\[\d+:\d+(?:[.:]\d+)?\]/g, "").trim()
            if (stamps && stamps.length > 0) {
                synced = true
                for (let s = 0; s < stamps.length; s++) {
                    let parts = stamps[s].slice(1, -1).split(/[:.]/)
                    let seconds = Number(parts[0]) * 60 + Number(parts[1])
                    if (parts.length > 2) seconds += Number(parts[2]) / (parts[2].length === 3 ? 1000 : 100)
                    // Instrumental gaps come through as empty text; they still
                    // need an entry so the previous line stops being current.
                    out.push({ t: seconds, text: text })
                }
            } else {
                out.push({ t: -1, text: text })
            }
        }
        out.sort((a, b) => a.t - b.t)
        window.lyricsSynced = synced
        window.lyricLines = out
    }

    // Index of the line that should be highlighted right now, or -1.
    readonly property int currentLyricIndex: {
        if (!lyricsSynced || lyricLines.length === 0) return -1
        let pos = mediaPosition + 0.25
        let found = -1
        for (let i = 0; i < lyricLines.length; i++) {
            if (lyricLines[i].t <= pos) found = i
            else break
        }
        return found
    }

    function lyricAt(offset) {
        let i = window.currentLyricIndex + offset
        if (i < 0 || i >= window.lyricLines.length) return ""
        return window.lyricLines[i].text
    }

    // The three visible slots, resolved for every state the pane can be in so
    // the UI itself stays free of state juggling.
    readonly property string lyricPrev: {
        if (lyricsLoading || lyricLines.length === 0) return ""
        // Explains why the lines below are sitting still, instead of leaving
        // the impression that syncing is simply broken.
        if (!lyricsSynced) return i18n.lyricsUnsynced
        return lyricAt(-1)
    }
    readonly property string lyricCurrent: {
        if (lyricsLoading) return i18n.lyricsSearching
        if (lyricLines.length === 0) return i18n.lyricsNotFound
        if (!lyricsSynced) return lyricLines[0].text
        return lyricAt(0)
    }
    readonly property string lyricNext: {
        if (lyricsLoading || lyricLines.length === 0) return ""
        if (!lyricsSynced) return lyricLines.length > 1 ? lyricLines[1].text : ""
        return lyricAt(1)
    }
    // Dim the current line for the placeholder states — it is a status
    // message then, not a lyric, and shouldn't shout.
    readonly property bool lyricIsPlaceholder: lyricsLoading || lyricLines.length === 0

    Process {
        id: lyricsProcess
        stdout: StdioCollector {
            onStreamFinished: {
                window.lyricsLoading = false
                let raw = text
                if (!raw || raw.trim() === "") { window.lyricLines = []; window.lyricsSynced = false; return }
                try { window.parseLyrics(raw) }
                catch (error) { console.warn("Dynamic Island lyrics:", error); window.lyricLines = [] }
            }
        }
    }

    function mediaAction(command) {
        if (command === "play-pause") {
            mediaStatusOverride = mediaStatus === "Playing" ? "Paused" : "Playing"
            Quickshell.execDetached(["playerctl", "play-pause"])
        } else if (command === "next" || command === "previous") {
            Quickshell.execDetached(["playerctl", command])
        } else if (command === "shuffle") {
            mediaShuffleOverride = mediaShuffle === "On" ? "Off" : "On"
            Quickshell.execDetached(["playerctl", "shuffle", "Toggle"])
        } else if (command === "loop") {
            let next = mediaLoop === "None" ? "Playlist" : (mediaLoop === "Playlist" ? "Track" : "None")
            mediaLoopOverride = next
            Quickshell.execDetached(["playerctl", "loop", next])
        }
        mediaOverrideTimer.restart()
        delayedRefresh.restart()
    }

    // Goes through backend.sh rather than execDetached: the pick has to land in
    // the state file every later playerctl call reads, which is the script's job.
    function selectPlayer(name) {
        if (!name) return
        window.selectedPlayerOverride = name
        mediaOverrideTimer.restart()
        window.run(["select-player", name])
    }

    // ------------------------------------------------------------- open/close
    // A short grace period only exists to bridge the frame where the island
    // resizes under the pointer; it is not a "keep it around a while" delay.
    Timer {
        id: closeTimer
        interval: 90
        onTriggered: {
            if (window.interacting) { restart(); return }
            if (islandHover.hovered || hoverSensor.containsMouse) return
            window.hovering = false
        }
    }

    // Pointer-leave events can still be swallowed when the layer surface
    // resizes. Re-check the handler directly instead of trusting that the
    // hoveredChanged signal always arrives.
    Timer {
        id: hoverWatchdog
        interval: 400
        repeat: true
        running: window.hovering
        onTriggered: {
            if (window.interacting || islandHover.hovered || hoverSensor.containsMouse) return
            if (!closeTimer.running) closeTimer.restart()
        }
    }

    function setInteracting(value) {
        window.interacting = value
        if (value) interactionGuard.restart()
        else interactionGuard.stop()
    }

    // Hard ceiling on how long a drag may hold the island open. Restarted by
    // every drag update, so a real drag never trips it and a lost release does.
    Timer {
        id: interactionGuard
        interval: 4000
        onTriggered: window.interacting = false
    }

    onExpandedChanged: if (!expanded) {
        setInteracting(false)
        showClock = false
        showAppVolumes = false
        showQueue = false
        showQuickSettings = false
        showCalendarPage = false
        showTimePage = false
    }

    onHoverToOpenChanged: if (!hoverToOpen) {
        hovering = false
        closeTimer.stop()
    }

    onFullscreenActiveChanged: if (fullscreenActive) {
        lockedOpen = false
        hovering = false
        notificationVisible = false
        deviceEventVisible = false
        deviceEventQueue = []
    }

    function closeIsland() {
        lockedOpen = false
        hovering = false
        notificationVisible = false
        deviceEventVisible = false
        deviceEventQueue = []
        // Deliberately not dismissed here. Collapsing the island is a
        // statement about the island, not an acknowledgement of a timer that
        // finished while nobody was watching — and this path also runs on an
        // incidental click-away, which used to swallow the card seconds after
        // it appeared. It stays up until it is actually answered, or until its
        // own timeout runs out.
        setInteracting(false)
    }

    // ------------------------------------------------------------------ misc
    FontLoader {
        id: bricolage
        source: "assets/BricolageGrotesque.ttf"
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            window.currentTime = new Date()
            const alarmKey = window.currentTime.getFullYear() + "-" + window.currentTime.getMonth()
                + "-" + window.currentTime.getDate() + "-" + window.alarmHour + "-" + window.alarmMinute
            if (window.alarmEnabled && window.currentTime.getSeconds() === 0
                    && window.currentTime.getHours() === window.alarmHour
                    && window.currentTime.getMinutes() === window.alarmMinute
                    && window.lastAlarmKey !== alarmKey) {
                window.lastAlarmKey = alarmKey
                window.raiseTimeAlert("alarm", "󰀠", i18n.tmAlarmFired,
                    i18n.tmAlarmFiredDetail(window.twoDigits(window.alarmHour) + ":" + window.twoDigits(window.alarmMinute)))
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: window.countdownRunning
        onTriggered: {
            if (window.countdownSeconds > 1) window.countdownSeconds--
            else {
                window.countdownSeconds = 0
                window.countdownRunning = false
                window.raiseTimeAlert("timer", "󰥔", i18n.tmTimerDone,
                    i18n.tmTimerDoneDetail(Math.round(window.countdownDuration / 60)))
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: window.pomodoroRunning
        onTriggered: {
            if (window.pomodoroSeconds > 1) window.pomodoroSeconds--
            else {
                // Read the phase that just ended before advancing, or the card
                // would announce the phase the user is about to start.
                const finishedWork = window.pomodoroWorkPhase
                window.advanceFocusPhase(true)
                window.raiseTimeAlert("focus", "󰔟",
                    finishedWork ? i18n.tmFocusDone : i18n.tmBreakDone,
                    finishedWork ? i18n.tmFocusDoneDetail : i18n.tmBreakDoneDetail)
            }
        }
    }

    // 50ms: fast enough that the hundredths column never visibly skips a value,
    // slow enough to stay off the per-frame path.
    Timer {
        interval: 50
        repeat: true
        running: window.stopwatchRunning
        onTriggered: window.stopwatchMs = window.stopwatchBase + (Date.now() - window.stopwatchStart)
    }

    // Long by alert standards, because the whole point of a timer is that it
    // finishes while you are looking somewhere else. Still bounded, so a card
    // nobody came back for cannot wedge the island open indefinitely.
    Timer {
        id: timeAlertTimeout
        interval: 60000
        onTriggered: window.dismissTimeAlert()
    }

    // Just longer than the entrance animation, so the card is fully formed
    // before it will answer to a click.
    Timer {
        id: timeAlertArming
        interval: 620
        onTriggered: window.timeAlertArmed = true
    }

    Timer {
        id: timeAlertPulseTimer
        interval: 2000
        onTriggered: window.timeAlertPulse = false
    }

    Timer {
        id: alertExpandTimer
        interval: 5000
        onTriggered: if (!window.hovering && !window.lockedOpen) window.lockedOpen = false
    }

    function run(args) {
        Quickshell.execDetached([backend].concat(args))
        delayedRefresh.restart()
    }

    function runDirect(args) {
        Quickshell.execDetached(args)
        delayedRefresh.restart()
    }

    function formatTime(seconds) {
        seconds = Math.max(0, Number(seconds) || 0)
        let m = Math.floor(seconds / 60)
        let s = Math.floor(seconds % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function resolveAppIcon(app, hint) {
        try {
            // The notification's own icon wins: it may be an absolute path, a
            // file:// URI, or a freedesktop icon name.
            if (hint) {
                let value = String(hint)
                if (value.indexOf("file://") === 0) return value
                if (value.indexOf("/") === 0) return "file://" + value
                let named = Quickshell.iconPath(value, true)
                if (named) return named
            }
            if (!app) return ""
            let entry = DesktopEntries.heuristicLookup(String(app))
            if (entry && entry.icon) {
                let path = Quickshell.iconPath(entry.icon, true)
                if (path) return path
            }
            let direct = Quickshell.iconPath(String(app).toLowerCase(), true)
            if (direct) return direct
        } catch (error) { console.warn("Dynamic Island icon lookup:", error) }
        return ""
    }

    function showNotification(app, title, body, icon, uid, hasReply, replyPlaceholder) {
        if (window.callVisible) return
        if (window.dndActive) return
        notificationApp = app
        notificationIcon = resolveAppIcon(app, icon)
        notificationTitle = title
        notificationBody = body
        notificationUid = uid || ""
        notificationHasReply = !!hasReply
        notificationReplyPlaceholder = replyPlaceholder || ""
        notificationReplyText = ""
        // The field's own `text` stops tracking notificationReplyText the
        // instant it's typed into — QML severs a property binding as soon as
        // anything assigns to it imperatively, which is exactly what typing
        // does. Without this, a draft abandoned on one notification would
        // still be sitting in the field, visible, on a completely unrelated
        // later one.
        replyField.text = ""
        notificationCopied = false
        deviceEventVisible = false
        deviceEventQueue = []
        notificationVisible = true
        notificationTimer.restart()
        notificationProgress.restart()
    }

    // wl-copy takes the text straight as an argument (no shell, no pipe
    // needed), which sidesteps any quoting/escaping question entirely — the
    // body reaches the clipboard byte for byte, including quotes and
    // newlines a shell-string version would have to fight with.
    function copyNotificationContent() {
        let text = window.notificationBody || window.notificationTitle
        if (text === "") return
        Quickshell.execDetached(["wl-copy", "--", text])
        window.notificationCopied = true
        notificationCopiedTimer.restart()
    }

    function sendNotificationReply() {
        let text = window.notificationReplyText.trim()
        if (text === "" || window.notificationUid === "") return
        Quickshell.execDetached(["quickshell", "-p", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/Main.qml",
            "ipc", "call", "notificationBridge", "sendInlineReply", window.notificationUid, text])
        window.notificationVisible = false
        window.notificationReplyText = ""
        replyField.text = ""
    }

    function showHud(kind, value) {
        hudKind = kind
        hudValue = value
        hudTimer.restart()
    }

    // Mic and camera can both change in the same poll tick (any video-call app
    // grabs both at once), which used to call this twice synchronously: the
    // second call clobbered the first mid-animation, restarting the pulse and
    // the dismiss timer before either had a chance to actually play. Queuing
    // instead means the mic card gets to run its full course before the
    // camera one takes over, so the two never visually collide.
    property var deviceEventQueue: []
    // Brief true pulse driving devicePulseRing's border colour on camera-off
    // (see the ring's Behavior on border.color) — not an animation target
    // itself, so the ring's own state binding never gets severed.
    property bool cameraClosing: false

    function showDeviceEvent(type, enabled, value) {
        if (window.callVisible) return
        if (window.deviceEventVisible) {
            deviceEventQueue.push({type: type, enabled: enabled, value: value})
            return
        }
        notificationVisible = false
        presentDeviceEvent(type, enabled, value)
    }

    function presentDeviceEvent(type, enabled, value) {
        deviceEventType = type
        if (type === "camera") {
            deviceEventIcon = enabled ? "󰄀" : "󰄁"
            deviceEventTitle = enabled ? i18n.cameraOn : i18n.cameraOff
            deviceEventSubtitle = enabled ? i18n.cameraOnDetail : i18n.cameraOffDetail
        } else if (type === "battery") {
            deviceEventIcon = "󰂃"
            deviceEventTitle = i18n.batteryLow
            deviceEventSubtitle = i18n.batteryLowDetail(value)
        } else {
            deviceEventIcon = enabled ? "󰍬" : "󰍭"
            deviceEventTitle = enabled ? i18n.micOn : i18n.micOff
            deviceEventSubtitle = enabled ? i18n.micOnDetail(value) : i18n.micOffDetail
        }
        deviceEventVisible = true
        deviceEventTimer.restart()
        devicePulse.restart()
        // Camera on and off used to play the exact same continuous spin, which
        // made the card read the same regardless of which one had happened —
        // the only cue was the glyph and colour. On gets a single decisive
        // turn, like a lens engaging; off gets a quick shutter-blink instead
        // of any rotation, so the two are unmistakable at a glance.
        if (type === "camera") {
            if (enabled) {
                cameraSpinOn.restart()
                cameraFlashPop.restart()
            } else {
                cameraShutterBlink.restart()
                window.cameraClosing = true
                cameraCloseTintTimer.restart()
            }
        }
    }

    // Only fires on the real 0%→critical crossing (or a manual `batteryAlert`
    // IPC call for testing) — not on every poll while already critical, or it
    // would re-show itself every ~1s for as long as the battery stays low.
    function showBatteryAlert(level) {
        window.showDeviceEvent("battery", false, level)
    }

    IpcHandler {
        target: "dynamicIsland"
        readonly property bool calendarOpen: window.showCalendarPage
        // The island is centred inside a full-width layer surface, so its
        // layer geometry says nothing about where the pill actually is. These
        // are what tools/capture.sh crops to — without them a screenshot is
        // either the whole top strip or a hand-guessed rectangle that drifts
        // the moment the island changes size.
        readonly property int islandWidth: Math.round(window.targetWidth)
        readonly property int islandHeight: Math.round(window.targetHeight)
        readonly property int islandTopMargin: 8
        function toggle(): void { window.lockedOpen = !window.lockedOpen; if (!window.lockedOpen) window.closeIsland() }
        function open(): void { window.lockedOpen = true }
        function close(): void { window.closeIsland() }
        function activity(text: string): void { window.activityText = text; activityTimer.restart() }
        // "tr", "en", or "toggle". The choice is persisted, so this is also how
        // a keybind or a script can set the language once and have it stick.
        function language(code: string): void { window.setLanguage(code) }
        function hover(enabled: bool): void {
            window.hoverToOpen = enabled
            window.saveSettings()
        }
        function compactControls(enabled: bool): void {
            window.compactMediaControls = enabled
            window.saveSettings()
        }
        function lyrics(): void { window.showLyrics = !window.showLyrics }
        function clock(): void { window.showClock = !window.showClock }
        function appVolumes(): void { window.showAppVolumes = !window.showAppVolumes }
        function queue(): void { window.showQueue = !window.showQueue }

        function calendar(): void {
            window.lockedOpen = true
            window.showCalendarPage = !window.showCalendarPage
        }
        function timeTools(): void {
            window.lockedOpen = true
            window.showTimePage = !window.showTimePage
        }
        function pageNext(): void { window.pageNext() }
        function pagePrev(): void { window.pagePrev() }

        function dnd(): void { window.dndActive = !window.dndActive }

        // Time tools. `timeMode` jumps straight to one instrument so a keybind
        // can land on the stopwatch rather than wherever the page was left.
        function timeMode(name: string): void {
            if (window.timeModes.indexOf(name) === -1) return
            window.lockedOpen = true
            window.showTimePage = true
            window.timeMode = name
        }
        // Fires the completion card without waiting out a real countdown, so
        // the arrival animation and every dismissal path stay testable.
        function timerTest(): void {
            window.raiseTimeAlert("timer", "󰥔", i18n.tmTimerDone, i18n.tmTimerDoneDetail(5))
        }
        function timerDismiss(): void { window.dismissTimeAlert() }
        // Start/pause and reset the mode currently on the stage, so a keybind
        // can drive the timer without opening the island at all.
        function timeToggle(): void { window.timePrimaryAction() }
        function timeReset(): void { window.timeResetAction() }
        function bluetoothToggle(): void { window.run(["bluetooth-toggle"]) }
        function wifiToggle(): void { window.run(["wifi-toggle"]) }
        function lockScreen(): void { window.runDirect(["bash", "-c", "~/.config/hypr/scripts/lock.sh"]) }
        function logout(): void { window.runDirect(["hyprctl", "dispatch", "exit"]) }

        // Stands in for the real battery reading for a few seconds — lets the
        // level colour (green/yellow/red) and the charging pulse be exercised
        // on demand instead of waiting for the hardware to actually be there.
        // status is "Charging" or anything else (mirrors backend.sh's field).
        function battery(level: int, status: string): void {
            window.batteryOverride = {level: level, status: status}
            batteryOverrideTimer.restart()
        }
        // Drops the override early instead of waiting out its ~8s expiry.
        function batteryReset(): void {
            window.batteryOverride = null
            batteryOverrideTimer.stop()
        }
        // Fires the critical-battery card directly, independent of the real
        // or overridden level — for testing the alert animation itself.
        function batteryAlert(level: int): void {
            window.showBatteryAlert(level)
        }

        // Opens the settings window straight onto one section, so a keybind can
        // land on the thing it is about instead of wherever it was left last.
        function settingsSection(name: string): void {
            window.settingsSectionRequest = name
            window.settingsOpen = true
            window.closeIsland()
        }
        function settings(): void {
            window.settingsOpen = !window.settingsOpen
            if (window.settingsOpen) window.closeIsland()
        }
        // "black", "umbra", "gray", "white", "custom", or "cycle" — so a keybind can
        // step through the palettes without opening the settings window.
        function theme(name: string): void {
            if (name === "cycle") {
                let at = window.themeOrder.indexOf(window.themeName)
                window.setTheme(window.themeOrder[(at + 1) % window.themeOrder.length])
            } else {
                window.setTheme(name)
            }
        }
        // A call rings for up to 35s (or until answered/declined) on its own
        // timer, independent of the sending notification's own expire-timeout
        // — so there is otherwise no way to back out of a call screen that
        // was raised by mistake, or by a test, without waiting it out. Also
        // covers a call the PipeWire heuristic still reports as live.
        function dismissCall(): void { window.dismissCallCard() }
        function deviceEvent(type: string, enabled: bool, value: int): void { window.showDeviceEvent(type, enabled, value) }
        function notification(app: string, title: string, body: string): void {
            window.showNotification(app, title, body, "")
        }
        // The notification server already knows the sending app's icon, which is
        // more accurate than looking it up from the name.
        function notify(app: string, title: string, body: string, icon: string): void {
            window.showNotification(app, title, body, icon)
        }

        // Same as notify(), but carries the notification's D-Bus actions, its
        // uid, and its inline-reply fields — needed to answer/reject a call
        // or send a reply through the app's own D-Bus hooks instead of
        // faking input. actionsJson is base64(JSON string); see the matching
        // comment in Main.qml for why it can't be raw JSON.
        function notifyWithActions(app: string, title: string, body: string, icon: string, actionsJson: string, uid: string, hasInlineReply: bool, inlineReplyPlaceholder: string): void {
            let actions = []
            try { actions = actionsJson ? JSON.parse(Qt.atob(actionsJson)) : [] } catch (error) { actions = [] }
            if (window.isIncomingCall(app, title, body, actions)) {
                window.showIncomingCall(app, title, actions, uid)
            } else {
                window.showNotification(app, title, body, icon, uid, hasInlineReply, inlineReplyPlaceholder)
            }
        }
    }

    Process {
        id: snapshot
        command: [window.backend, "snapshot", window.snapshotMode]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = text.trim()
                if (!raw) return
                try {
                    let next = JSON.parse(raw)
                    if (window.startupRead) {
                        if (!window.expanded && window.previousVolume >= 0 && next.volume !== window.previousVolume) window.showHud(next.muted ? "󰝟" : "󰕾", next.volume)
                        if (!window.expanded && window.previousBrightness >= 0 && next.brightness !== window.previousBrightness) window.showHud("󰃠", next.brightness)
                        if (next.micMuted !== window.previousMicMuted) window.showDeviceEvent("microphone", !next.micMuted, next.micVolume)
                        else if (next.micActive !== window.previousMicActive) window.showDeviceEvent("microphone", next.micActive, next.micVolume)
                        if (next.cameraActive !== window.previousCameraActive) window.showDeviceEvent("camera", next.cameraActive, 0)
                        if (window.previousBattery >= 0 && next.batteryStatus === "Charging" && next.battery !== window.previousBattery) {
                            window.activityText = i18n.charging(next.battery)
                            activityTimer.restart()
                        }
                        // Only on the crossing into critical (just dropped below
                        // the threshold, or the charger was just pulled while
                        // already low) — never on every poll while it stays low,
                        // or the card would re-show itself once a second.
                        const wasCritical = window.previousBattery >= 0
                            && window.previousBattery <= window.batteryCriticalThreshold
                            && window.previousBatteryCharging === false
                        const nowCritical = next.battery <= window.batteryCriticalThreshold
                            && next.batteryStatus !== "Charging"
                        if (nowCritical && !wasCritical) window.showBatteryAlert(next.battery)
                    }
                    let callNow = !!(next.call && next.call.active)
                    if (callNow) {
                        // Audio confirms the call connected — the ring (if any)
                        // has done its job.
                        window.callRinging = false
                        window.callAnswering = false
                        callConnectTimeout.stop()
                        // A call that starts fresh (heuristic alone, no ring —
                        // e.g. answered on another device) must show up even
                        // if a previous, unrelated call was closed earlier.
                        if (!window.previousCallActive) {
                            window.callDismissed = false
                            window.callManualOpen = false
                        }
                    } else if (window.previousCallActive && !window.callRinging) {
                        // Call ended: drop the caller name so a later, unrelated
                        // call started via the audio heuristic alone doesn't
                        // show a stale title, and close the card so the next
                        // call (auto-popup off) doesn't inherit this one being
                        // left open.
                        window.callApp = ""
                        window.callTitle = ""
                        window.callManualOpen = false
                    }
                    window.previousCallActive = callNow

                    window.previousVolume = next.volume
                    window.previousBrightness = next.brightness
                    window.previousBattery = next.battery
                    window.previousBatteryCharging = next.batteryStatus === "Charging"
                    window.previousMicMuted = next.micMuted
                    window.previousMicActive = next.micActive
                    window.previousCameraActive = next.cameraActive
                    window.islandState = next
                    window.syncPosition(next.media ? next.media.position : 0)
                    window.startupRead = true
                } catch (error) { console.warn("Dynamic Island snapshot:", error) }
            }
        }
    }

    Process {
        id: cavaProcess
        command: [window.backend, "visualizer"]
        // The compact pill now carries a full-width, real audio field, so cava
        // stays alive for the duration of playback instead of starting only
        // after expansion. This is the source of truth for the Live variant.
        running: window.mediaSpectrumEnabled && window.mediaStatus === "Playing"
                 && !window.fullscreenActive
        onRunningChanged: if (!running) {
            window.visualLevels = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                let values = String(line).trim().split(";").filter(v => v !== "").map(v => Number(v))
                if (values.length >= 8) window.visualLevels = values
            }
        }
    }

    Timer {
        // Each snapshot costs real work, and playback position is interpolated
        // locally, so only poll quickly while the panel is actually on screen.
        // Kept reasonably short even when collapsed: the microphone capsule is a
        // privacy indicator and should not lag noticeably behind the hardware.
        //
        // The fully-idle case (nothing playing, mic/camera off) is the one that
        // matters most here: it's the interval a *newly started* mic or camera
        // use has to wait through before the poll that finally notices it, so
        // it drives how long "mic turned on" takes to show up, not just how
        // fresh the indicator looks once already lit.
        interval: window.expanded
            ? 800
            : (window.mediaStatus === "Playing" || window.islandState.micActive || window.islandState.cameraActive ? 1200 : 900)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!snapshot.running) snapshot.running = true
    }
    Timer { id: delayedRefresh; interval: 180; onTriggered: if (!snapshot.running) snapshot.running = true }
    Timer { id: hudTimer; interval: 1700 }
    Timer { id: batteryOverrideTimer; interval: 8000; onTriggered: window.batteryOverride = null }
    Timer { id: cameraCloseTintTimer; interval: 180; onTriggered: window.cameraClosing = false }
    Timer { id: notificationCopiedTimer; interval: 1400; onTriggered: window.notificationCopied = false }
    Timer { id: activityTimer; interval: 5000; onTriggered: window.activityText = "" }
    Timer {
        id: deviceEventTimer
        interval: 2800
        onTriggered: {
            window.deviceEventVisible = false
            if (window.deviceEventQueue.length > 0) deviceEventDrain.restart()
        }
    }
    // Waits out the outgoing card's fade (see deviceEventCard's opacity
    // Behavior, 180ms) before presenting the next queued event, so the two
    // cards never cross-fade into each other.
    Timer {
        id: deviceEventDrain
        interval: 220
        onTriggered: {
            if (window.deviceEventQueue.length === 0) return
            const next = window.deviceEventQueue.shift()
            window.presentDeviceEvent(next.type, next.enabled, next.value)
        }
    }
    Timer {
        id: notificationTimer
        interval: window.notificationSeconds * 1000
        onTriggered: {
            window.notificationVisible = false
            window.notificationApp = ""
            window.notificationIcon = ""
            window.notificationTitle = ""
            window.notificationBody = ""
            window.notificationUid = ""
            window.notificationHasReply = false
            window.notificationReplyPlaceholder = ""
            window.notificationReplyText = ""
        }
    }

    // --------------------------------------------------------------- surface
    WlrLayershell.namespace: "qs-dynamic-island"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    // Keyboard focus is taken only while the island is deliberately pinned open
    // — the keybind or the pin chip. Two reasons it must never follow hover:
    // an exclusive grab swallows every keystroke aimed at whatever the user is
    // actually typing in, and grabbing focus on hover is what let the island
    // get stuck open before. Pinned is the one state where staying open is the
    // point, so a focus grab there cannot be a bug.
    WlrLayershell.keyboardFocus: window.lockedOpen ? WlrKeyboardFocus.Exclusive
                                                   : WlrKeyboardFocus.None
    color: "transparent"
    anchors { top: true; left: true; right: true }
    implicitHeight: 344

    // Rounded and slightly padded so the input region changes value less often
    // while the island is animating, and so the pointer keeps hover a pixel or
    // two past the visual edge.
    mask: Region {
        x: Math.round(island.x) - 2
        y: Math.round(island.y) - 2
        width: Math.round(island.width) + 4
        height: Math.round(island.height) + 4
    }

    // Snapped to an 8px grid: the compact row's implicit width shifts by a pixel
    // or two whenever a digit changes, and without snapping that retriggered the
    // island's width animation once a second.
    readonly property real compactWidth: Math.max(320, Math.ceil((compactContent.implicitWidth + 52) / 8) * 8)
    // While a call rings, the island grows into a proper call screen (big
    // avatar, centered name, big buttons) instead of the flat notification-
    // card shape everything else uses — it should read as the island
    // switching modes, not another alert sliding past. It collapses back to
    // a compact bar the moment the user answers, not when the PipeWire
    // heuristic gets around to confirming it — waiting on that would leave
    // the big screen sitting there through the whole "Bağlanıyor…" gap.
    readonly property bool callBigView: callRinging && !callAnswering
    // The completion card is checked before every other alert: it is the only
    // one the user explicitly asked for by starting a timer, so nothing else
    // arriving in the same tick gets to size the island out from under it.
    readonly property real targetWidth: expanded
        ? Math.min(timeAlertVisible ? 470
            : (notificationVisible ? 500 : (deviceEventVisible ? 420 : (callVisible ? (callBigView ? 360 : 500) : 780))), window.width - 40)
        : compactWidth
    // Mirrors replyRow's own visibility rather than notificationHasReply alone:
    // with inline reply switched off the field is gone, and the card must not
    // keep reserving the 42px it used to occupy.
    readonly property bool notificationReplyShown: notificationHasReply && notificationInlineReply
    readonly property real targetHeight: expanded
        ? (timeAlertVisible ? 128
            : (notificationVisible ? (notificationReplyShown ? 168 : 124)
                : (deviceEventVisible ? 98
                    : (callVisible ? (callBigView ? 270 : 124) : 324))))
        : 54

    // Four selectable top-edge mounts (Settings > Appearance > Mount style):
    //  - capsule/halo share the original floating geometry
    //  - soft-fused/notch sit flush against the screen edge instead
    readonly property bool mountFlush: window.islandMountStyle === "soft-fused" || window.islandMountStyle === "notch"
    readonly property real islandCornerRadius: window.expanded ? (window.alertVisible ? 24 : 30) : 20
    readonly property real islandTopRadius: {
        if (window.islandMountStyle === "soft-fused") return 7
        if (window.islandMountStyle === "notch") return 0
        return islandCornerRadius
    }

    // Two layered blurs rather than one flat blob: a wide, faint outer wash
    // for ambient falloff plus a tighter, brighter core sized to the island
    // itself, so the glow reads as coming from the pill instead of floating
    // as a separate shape behind it. Tinted with the active theme's accent
    // (palette.on) so it never clashes across theme switches.
    Item {
        id: islandHalo
        visible: window.islandMountStyle === "halo" && !window.fullscreenActive
        anchors.top: parent.top
        // "halo" only ever pairs with the capsule's 8px gap, never the flush
        // mounts - centered on where the island actually floats.
        anchors.topMargin: -12
        anchors.horizontalCenter: parent.horizontalCenter
        width: island.width + 90
        height: island.height + 50
        z: -1

        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }

        Rectangle {
            id: haloWash
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: height / 2
            color: window.themeOn
            visible: false
        }
        MultiEffect {
            anchors.fill: haloWash
            source: haloWash
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            brightness: 0
            opacity: 0.16
        }

        Rectangle {
            id: haloCore
            anchors.centerIn: parent
            width: island.width + 22
            height: island.height + 8
            radius: height / 2
            color: window.themeOn
            visible: false
        }
        MultiEffect {
            anchors.fill: haloCore
            source: haloCore
            blurEnabled: true
            blur: 0.5
            blurMax: 26
            brightness: 0.05
            opacity: 0.32
        }
    }

    // The notch's two "ears": the technique real hardware notches use is a
    // solid-colour patch the exact shade of what's behind it, carved with a
    // reversed radius. That only works against a known solid background
    // (a status bar) - the desktop behind this window is an arbitrary
    // wallpaper, so a solid patch would show up as a mismatched square
    // instead of blending in. Using the theme's translucent scrim instead:
    // it darkens/carves the corner consistently against any wallpaper
    // rather than trying (and failing) to colour-match it exactly.
    Item {
        id: islandNotchEars
        visible: window.islandMountStyle === "notch" && !window.fullscreenActive
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: island.width + 2 * islandCornerRadius
        height: islandCornerRadius
        z: 2

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            width: islandCornerRadius
            height: islandCornerRadius
            color: window.themeScrim
            bottomRightRadius: islandCornerRadius
        }
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: islandCornerRadius
            height: islandCornerRadius
            color: window.themeScrim
            bottomLeftRadius: islandCornerRadius
        }
    }

    Rectangle {
        id: island

        anchors.top: parent.top
        anchors.topMargin: window.mountFlush ? 0 : 8
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !window.fullscreenActive

        width: window.targetWidth
        height: window.targetHeight
        topLeftRadius: window.islandTopRadius
        topRightRadius: window.islandTopRadius
        bottomLeftRadius: window.islandCornerRadius
        bottomRightRadius: window.islandCornerRadius
        clip: true

        // Only ever reachable while pinned, since that is the only state where
        // the surface holds the keyboard.
        focus: true
        Keys.onPressed: event => {
            // A finished timer owns the keyboard while its card is up: any of
            // the three keys a person actually reaches for to make an alert go
            // away dismisses it, instead of pausing whatever music happened to
            // be playing behind it.
            if (window.timeAlertVisible
                    && (event.key === Qt.Key_Escape || event.key === Qt.Key_Space || event.key === Qt.Key_Return)) {
                window.dismissTimeAlert()
                event.accepted = true
                return
            }
            switch (event.key) {
            case Qt.Key_Space:
            case Qt.Key_MediaTogglePlayPause:
                if (window.mediaStatus !== "Stopped") window.mediaAction("play-pause")
                event.accepted = true
                break
            case Qt.Key_Left:
                if (window.mediaStatus !== "Stopped") window.mediaAction("previous")
                event.accepted = true
                break
            case Qt.Key_Right:
                if (window.mediaStatus !== "Stopped") window.mediaAction("next")
                event.accepted = true
                break
            case Qt.Key_Escape:
                window.closeIsland()
                event.accepted = true
                break
            }
        }

        // Flat capsule, no outline — the ring pulse during a call is the one
        // exception, since that border is a status signal rather than chrome.
        // Its green is deliberately outside the palette: it means "ringing" in
        // all four themes, so tying it to themeText would erase the signal.
        readonly property bool ringPulseActive: window.callPulseRing
            && (window.callRinging || window.callAnswering)
        readonly property bool alertPulseActive: window.timeAlertPulse
        border.width: ringPulseActive || alertPulseActive ? 2 : 0
        border.color: alertPulseActive
            ? Qt.rgba(themeStatusAlert.r, themeStatusAlert.g, themeStatusAlert.b, 0.5 + Math.abs(Math.sin(window.visualPhase * 4)) * 0.5)
            : (ringPulseActive ? Qt.rgba(0.35, 0.86, 0.55, 0.4 + Math.abs(Math.sin(window.visualPhase)) * 0.35) : "transparent")

        color: window.themeIslandFill

        PanelChip {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            z: 20
            visible: window.expanded && !window.alertVisible && !window.showCalendarPage
            icon: "󰅁"
            onTriggered: window.pagePrev()
        }

        PanelChip {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            z: 20
            visible: window.expanded && !window.alertVisible && !window.showTimePage
            icon: "󰅂"
            onTriggered: window.pageNext()
        }

        // Same curve character both ways — only the duration differs, opening
        // a little slower than it closes — so the two directions read as one
        // physical motion rather than two different animations stitched
        // together. No overshoot: a bounce on either edge reads as a glitch
        // more than it reads as physical.
        Behavior on width {
            NumberAnimation {
                duration: window.expanded ? 380 : 260
                easing.type: Easing.OutQuint
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: window.expanded ? 380 : 260
                easing.type: Easing.OutQuint
            }
        }
        Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 200 } }

        // Top highlight, brighter when open so the expanded panel reads as glass.
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.7
            height: 1
            color: window.themeLineStrong
            opacity: window.expanded ? 0.8 : 0.4
            Behavior on opacity { NumberAnimation { duration: 260 } }
        }

        // Two independent hover sources. The handler keeps reporting while the
        // pointer is over a child control, which a full-size sensor cannot do
        // without swallowing every button's own hover state; the sensor sits
        // underneath everything and covers the case where the handler misses an
        // enter. Either one is enough to open — both have to agree the pointer
        // is gone before it closes.
        HoverHandler {
            id: islandHover
            onHoveredChanged: {
                if (hovered && window.hoverToOpen) {
                    closeTimer.stop()
                    window.hovering = true
                } else if (window.hoverToOpen) {
                    closeTimer.restart()
                }
            }
        }

        MouseArea {
            id: hoverSensor
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                if (!window.hoverToOpen) return
                closeTimer.stop()
                window.hovering = true
            }
            onExited: if (window.hoverToOpen) closeTimer.restart()
        }

        // Hover mode keeps left click inert. Click mode deliberately uses the
        // empty capsule surface as its open/close affordance; controls declared
        // later stay above this area and consume their own clicks.
        MouseArea {
            id: clickArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) window.closeIsland()
                else if (!window.hoverToOpen && !window.alertVisible)
                    window.lockedOpen = !window.lockedOpen
            }
        }

        // ------------------------------------------------------ collapsed pill
        Item {
            id: compactLayer
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: (window.expanded || hudCapsule.showing) ? 0 : 1
            scale: window.expanded ? 0.95 : 1
            Behavior on opacity { NumberAnimation { duration: window.expanded ? 110 : 240; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

            // A low-contrast sound field across the entire capsule. It is
            // intentionally drawn before compactContent so information stays
            // crisp while the island itself feels alive from edge to edge.
            Spectrum {
                visible: window.mediaSpectrumEnabled
                anchors.fill: parent
                anchors.margins: 5
                z: 0
                bars: 48
                barSpacing: 2
                fillWidth: true
                peak: Math.max(8, height - 12)
                floorHeight: 2
                mirrored: true
                baseAlpha: 0.03
                gainAlpha: 0.27
            }

            RowLayout {
                id: compactContent
                z: 1
                anchors.centerIn: parent
                anchors.verticalCenterOffset: window.mediaStatus === "Playing" ? 4 : 0
                spacing: 14

                PixelClock {
                    visible: window.mediaStatus === "Stopped"
                    time: window.currentTime
                    lang: window.lang
                    hour24: window.clock24Hour
                    style: window.clockStyle
                    textFont: window.uiFont
                    // The pill is 54px tall — seconds and a date strip do not
                    // survive at this scale, so the compact clock shows neither
                    // regardless of the setting.
                    showSeconds: false
                    showDate: window.clockDate
                    cell: 2
                    gap: 1
                    compact: true
                    color: window.themeText
                    mutedColor: window.themeMuted
                    gridColor: "transparent"
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                }

                Item {
                    visible: window.mediaStatus !== "Stopped"
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28

                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        color: window.themeSurface
                        clip: true
                        border.width: 1
                        border.color: window.themeLineStrong
                        Image {
                            id: artThumbImage
                            anchors.fill: parent
                            visible: window.mediaAlbumArtEnabled
                            source: window.mediaAlbumArtEnabled
                                    ? String(window.islandState.media.art || "").replace("file://", "")
                                    : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: artThumbImage.status !== Image.Ready
                            text: "󰎈"
                            color: window.themeMuted
                            font.family: window.iconFont
                            font.pixelSize: 15
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 8
                        height: parent.height + 8
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: window.themeText
                        visible: window.mediaStatus === "Playing"
                        opacity: (1 - window.ringPulse) * 0.45
                        scale: 0.86 + window.ringPulse * 0.4
                    }
                }

                Text {
                    visible: window.mediaStatus !== "Stopped"
                    Layout.maximumWidth: 210
                    text: window.islandState.media.title || i18n.media
                    elide: Text.ElideRight
                    color: window.themeText
                    font.family: window.uiFont
                    font.weight: Font.DemiBold
                    font.pixelSize: 14
                }

                Row {
                    visible: window.compactPlayerMode
                    spacing: 2

                    CompactTransportButton {
                        icon: "󰒮"
                        onTriggered: window.mediaAction("previous")
                    }
                    CompactTransportButton {
                        icon: window.mediaStatus === "Playing" ? "󰏤" : "󰐊"
                        primary: true
                        onTriggered: window.mediaAction("play-pause")
                    }
                    CompactTransportButton {
                        icon: "󰒭"
                        onTriggered: window.mediaAction("next")
                    }
                }

                Rectangle {
                    visible: window.mediaStatus !== "Stopped" && !window.compactPlayerMode
                    Layout.preferredWidth: 1; Layout.preferredHeight: 24; color: window.themeLineStrong
                }

                PixelClock {
                    visible: window.mediaStatus !== "Stopped" && !window.compactPlayerMode
                    time: window.currentTime
                    lang: window.lang
                    hour24: window.clock24Hour
                    style: window.clockStyle
                    textFont: window.uiFont
                    showSeconds: false
                    showDate: false
                    cell: 2
                    gap: 1
                    color: window.themeText
                    mutedColor: window.themeMuted
                    gridColor: "transparent"
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                }

                // ------------------------------------------- time capsule
                Rectangle {
                    id: timeCapsule
                    visible: window.timeCapsuleVisible && !window.compactPlayerMode
                    Layout.preferredWidth: visible ? capsuleRow.implicitWidth + 20 : 0
                    Layout.preferredHeight: 28
                    radius: 10
                    clip: true

                    color: Qt.rgba(window.timeCapsuleColor.r, window.timeCapsuleColor.g,
                                   window.timeCapsuleColor.b, window.timeCapsuleUrgent ? 0.18 : 0.11)
                    border.width: 1
                    border.color: Qt.rgba(window.timeCapsuleColor.r, window.timeCapsuleColor.g,
                                          window.timeCapsuleColor.b,
                                          window.timeCapsuleUrgent
                                            ? 0.45 + Math.abs(Math.sin(window.visualPhase)) * 0.55
                                            : 0.35)
                    Behavior on color { ColorAnimation { duration: 300 } }
                    Behavior on Layout.preferredWidth {
                        NumberAnimation { duration: 320; easing.type: Easing.OutQuint }
                    }

                    // The capsule's own light, travelling left to right. Slow
                    // and faint while merely running; quick and bright once the
                    // thing is about to fire, so the pill escalates on its own
                    // without ever growing or moving.
                    Rectangle {
                        id: capsuleSweep
                        y: 0
                        width: 26
                        height: parent.height
                        rotation: 16
                        color: window.timeCapsuleColor
                        opacity: window.timeCapsuleUrgent ? 0.30 : 0.16
                        x: -60
                        NumberAnimation on x {
                            running: timeCapsule.visible
                            from: -60
                            to: timeCapsule.width + 60
                            duration: window.timeCapsuleUrgent ? 900 : 2100
                            loops: Animation.Infinite
                            easing.type: Easing.InOutCubic
                            onRunningChanged: if (!running) capsuleSweep.x = -60
                        }
                    }

                    Row {
                        id: capsuleRow
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -1
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: window.timeModeIcon(window.timeCapsuleMode)
                            color: window.timeCapsuleColor
                            font.family: window.iconFont
                            font.pixelSize: 12
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }

                        // Same matrix as the compact clock beside it, so the
                        // capsule reads as another readout on the same display
                        // rather than a badge stuck onto the pill.
                        PixelText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: window.timeCapsuleValue
                            cell: 2
                            gap: 1
                            color: window.timeCapsuleUrgent ? window.timeCapsuleColor : window.themeText
                            offColor: Qt.rgba(window.themeText.r, window.themeText.g, window.themeText.b, 0.09)
                            animated: true
                            rollDuration: 260
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }
                    }

                    // Drain line along the bottom edge: the one part of the
                    // capsule carrying a quantity rather than a state.
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.bottomMargin: 3
                        anchors.leftMargin: 6
                        width: Math.max(0, (parent.width - 12) * window.timeCapsuleProgress)
                        height: 2
                        radius: 1
                        color: window.timeCapsuleColor
                        opacity: 0.85
                        Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                    }
                }

                Rectangle {
                    visible: !window.compactPlayerMode
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 24
                    color: window.themeLineStrong
                }

                Text {
                    visible: !window.compactPlayerMode
                    text: (window.batteryCharging ? "󰂄  " : "󰁹  ") + window.displayBattery + "%"
                    color: window.batteryColor
                    // Breathes between the level colour and a lighter tint
                    // while charging; holds steady otherwise.
                    opacity: window.batteryCharging ? (0.6 + window.batteryPulse * 0.4) : 1
                    font.family: window.iconFont
                    font.pixelSize: 14
                    Behavior on color { ColorAnimation { duration: 250 } }
                }

                Row {
                    visible: !window.compactPlayerMode
                    spacing: 9
                    StatusDot {
                        icon: window.islandState.micMuted ? "󰍭" : "󰍬"
                        lit: window.islandState.micActive && !window.islandState.micMuted
                        statusColored: true
                    }
                    StatusDot {
                        icon: window.islandState.cameraActive ? "󰄀" : "󰄁"
                        lit: window.islandState.cameraActive
                        statusColored: true
                    }
                }
            }

            // A quiet elapsed/remaining readout for the player-only pill. The
            // unfilled track is what is left; the lit section is what has
            // already played. Streams with no reported duration omit it rather
            // than showing a permanently empty, misleading bar.
            Rectangle {
                visible: window.compactPlayerMode && window.mediaLengthKnown
                z: 2
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.bottomMargin: 4
                height: 2
                radius: 1
                color: window.themeTrack

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1,
                        window.mediaPosition / Math.max(1, window.islandState.media.length || 1)))
                    height: parent.height
                    radius: parent.radius
                    color: window.themeText
                    Behavior on width {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                }
            }

        }

        // ------------------------------------------------------ expanded panel
        Item {
            id: expandedLayer
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: (window.expanded && !window.alertVisible) ? 1 : 0

            // Held back briefly on the way in so the shell finishes most of its
            // growth before the contents arrive, and dropped immediately on the
            // way out so nothing is left drifting inside a shrinking box.
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: window.expanded ? 120 : 0 }
                    NumberAnimation { duration: window.expanded ? 260 : 110; easing.type: Easing.OutCubic }
                }
            }

            transform: Translate { y: (1 - expandedLayer.opacity) * 14 }

            // ------------------------------------------------- status strip
            RowLayout {
                id: statusStrip
                anchors { top: parent.top; left: parent.left; right: parent.right }
                anchors.topMargin: 12
                anchors.leftMargin: 22
                anchors.rightMargin: 20
                spacing: 14
                height: 26

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 3
                        color: window.mediaStatus === "Playing" && !window.idleView
                               ? "#65d58a" : window.themeMuted
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.idleView ? i18n.secClock : i18n.media
                        color: window.themeSubtext
                        font.family: window.uiFont
                        font.weight: Font.DemiBold
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                // B3 — one pill divided into a segment per player. Costs room in
                // an already busy strip, which is why it isn't the default.
                Rectangle {
                    visible: window.playerSwitcherStyle === "segment"
                             && window.mediaPlayers.length > 1
                    implicitWidth: segmentRow.implicitWidth + 4
                    implicitHeight: 24
                    radius: 9
                    color: window.themeChip

                    Row {
                        id: segmentRow
                        anchors.centerIn: parent
                        spacing: 2

                        Repeater {
                            model: window.mediaPlayers

                            Rectangle {
                                id: playerSegment
                                required property var modelData
                                readonly property bool picked: window.isPlayerSelected(modelData)

                                implicitWidth: Math.min(66, segmentLabel.implicitWidth + 14)
                                implicitHeight: 20
                                radius: 7
                                color: picked ? window.themeOn : "transparent"
                                Behavior on color { ColorAnimation { duration: 160 } }

                                Text {
                                    id: segmentLabel
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, playerSegment.width - 10)
                                    text: playerSegment.modelData.label
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    color: playerSegment.picked ? window.themeOnText : window.themeSubtext
                                    font.family: window.uiFont
                                    font.weight: Font.Bold
                                    font.pixelSize: 9
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 0.5
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: window.selectPlayer(playerSegment.modelData.name)
                                }
                            }
                        }
                    }
                }

                PanelChip {
                    label: window.lang.toUpperCase()
                    onTriggered: window.setLanguage("toggle")
                }

                // Only present while a call is actually happening — same
                // appear/disappear pattern as the lyrics and clock chips
                // below, which only show up while media is playing. Toggles
                // the call card open/closed (independent of the card's own
                // 󰅖 close button), so a call dismissed mid-conversation can
                // still be reopened to check how long it's been running.
                PanelChip {
                    visible: window.callOngoing
                    icon: "󰏶"
                    lit: window.callVisible
                    onTriggered: {
                        if (window.callAutoPopup) window.callDismissed = !window.callDismissed
                        else window.callManualOpen = !window.callManualOpen
                    }
                }

                PanelChip {
                    visible: window.mediaStatus !== "Stopped" && window.mediaLyricsEnabled
                    icon: "󰨖"
                    lit: window.showLyrics
                    onTriggered: window.showLyrics = !window.showLyrics
                }

                // Shown whenever the feature is on rather than gated on there
                // being streams to list: the stream list is only collected while
                // the panel is open, so gating on it would hide the only way to
                // open it. Same reasoning as the lyrics chip not pre-checking
                // whether the track actually has lyrics.
                PanelChip {
                    visible: window.appVolumeEnabled
                    icon: "󰕾"
                    lit: window.showAppVolumes
                    onTriggered: window.showAppVolumes = !window.showAppVolumes
                }

                PanelChip {
                    visible: window.queueEnabled && window.mediaStatus !== "Stopped"
                    icon: "󰐑"
                    lit: window.showQueue
                    onTriggered: window.showQueue = !window.showQueue
                }

                PanelChip {
                    visible: window.mediaStatus !== "Stopped"
                    icon: window.showClock ? "󰝚" : "󰥔"
                    lit: window.showClock
                    onTriggered: window.showClock = !window.showClock
                }

                PanelChip {
                    icon: window.lockedOpen ? "󰐃" : "󰤱"
                    lit: window.lockedOpen
                    onTriggered: window.lockedOpen = !window.lockedOpen
                }

                // Opens the big centered settings window, not another chip
                // inside the island — the island itself closes to make room
                // for it, same as clicking away from a fullscreen dialog.
                PanelChip {
                    icon: "󰒓"
                    onTriggered: {
                        window.settingsOpen = true
                        window.closeIsland()
                    }
                }

                PanelChip {
                    icon: "󰅖"
                    danger: true
                    onTriggered: window.closeIsland()
                }
            }

            // ------------------------------------------------------- content
            RowLayout {
                anchors { left: parent.left; right: parent.right; top: statusStrip.bottom; bottom: parent.bottom }
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 14
                anchors.bottomMargin: 18
                spacing: 18

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.fill: parent
                        radius: 20
                        color: window.mediaUsesDarkSurface ? "#000000" : "transparent"
                        opacity: window.idleView ? 0 : 1
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    }

                    // Media and clock share this slot and cross-fade, so pulling
                    // the clock up over a playing track never resizes the island.
                    RowLayout {
                        id: mediaView
                        anchors.fill: parent
                        spacing: 18
                        visible: opacity > 0.01
                        opacity: window.idleView ? 0 : 1
                        scale: window.idleView ? 0.97 : 1
                        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                        Rectangle {
                            Layout.preferredWidth: 168
                            Layout.fillHeight: true
                            radius: 18
                            // Fixed on purpose, and the one surface in the
                            // panel that must never follow themeSurface: real
                            // cover art needs a dark surround to keep its edge,
                            // and the caption sits on this box under a dark
                            // scrim. On the white theme both would fail.
                            color: "#000000"
                            clip: true
                            border.width: 1
                            border.color: "#16ffffff"

                            Image {
                                id: homeArt
                                anchors.fill: parent
                                visible: window.mediaAlbumArtEnabled
                                source: window.mediaAlbumArtEnabled
                                        ? String(window.islandState.media.art || "").replace("file://", "")
                                        : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                // The scrim below already guarantees the caption
                                // stays legible, so the cover itself can stay
                                // close to full strength.
                                opacity: 0.92
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: homeArt.status !== Image.Ready
                                text: "󰎈"
                                color: "#333333"
                                font.family: window.iconFont
                                font.pixelSize: 52
                            }
                            // Flat scrim (no gradient) so the caption stays
                            // legible over any cover, covering just the strip
                            // behind the text rather than the whole image.
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: parent.height * 0.4
                                color: "#cc000000"
                            }
                            Column {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 13 }
                                spacing: 3
                                Text {
                                    width: parent.width
                                    text: window.islandState.media.title || i18n.nothingPlaying
                                    elide: Text.ElideRight
                                    color: "#ffffff"
                                    font.family: window.uiFont
                                    font.bold: true
                                    font.pixelSize: 12
                                }
                                // Doubles as the player switcher, rather than
                                // sitting beside one: with a single player this
                                // is the plain caption it has always been, so
                                // the control only appears once there is
                                // actually something to switch between — and it
                                // costs no extra room in an already tight panel.
                                Item {
                                    width: parent.width
                                    height: 13

                                    Text {
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                        visible: window.mediaPlayers.length <= 1
                                        text: window.islandState.media.player || "MPRIS"
                                        elide: Text.ElideRight
                                        color: "#a8a8a8"
                                        font.family: window.uiFont
                                        font.capitalization: Font.AllUppercase
                                        font.letterSpacing: 1
                                        font.pixelSize: 8
                                    }

                                    // B1 — named chips. Three fit; the rest fold
                                    // into a +N that advances through them.
                                    Row {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        visible: window.mediaPlayers.length > 1
                                                 && window.playerSwitcherStyle === "chips"
                                        spacing: 3

                                        Repeater {
                                            model: window.visiblePlayers
                                            PlayerChip {
                                                required property var modelData
                                                text: modelData.label
                                                lit: window.isPlayerSelected(modelData)
                                                onTriggered: window.selectPlayer(modelData.name)
                                            }
                                        }

                                        PlayerChip {
                                            visible: window.mediaPlayers.length > 3
                                            text: "+" + (window.mediaPlayers.length - 3)
                                            onTriggered: window.cyclePlayer()
                                        }
                                    }

                                    // B2 — icons only. Six fit where three names
                                    // did, at the cost of telling two windows of
                                    // the same application apart.
                                    Row {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        visible: window.mediaPlayers.length > 1
                                                 && window.playerSwitcherStyle === "logos"
                                        spacing: 7

                                        Repeater {
                                            model: window.mediaPlayers

                                            Item {
                                                id: playerLogo
                                                required property var modelData
                                                readonly property bool picked: window.isPlayerSelected(modelData)
                                                readonly property string iconPath: window.resolvePlayerIcon(modelData)

                                                width: 18
                                                height: 18
                                                scale: logoHit.pressed ? 0.88 : 1
                                                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 9
                                                    color: "transparent"
                                                    border.width: playerLogo.picked ? 1 : 0
                                                    border.color: "#ffffff"
                                                }

                                                Image {
                                                    anchors.centerIn: parent
                                                    width: 14
                                                    height: 14
                                                    visible: playerLogo.iconPath !== ""
                                                    source: playerLogo.iconPath
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                    smooth: true
                                                    opacity: playerLogo.picked ? 1 : 0.4
                                                    Behavior on opacity { NumberAnimation { duration: 160 } }
                                                }

                                                // Not every player installs a
                                                // desktop icon; the initial keeps
                                                // the row from gapping.
                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: playerLogo.iconPath === ""
                                                    text: String(playerLogo.modelData.label || "?").charAt(0).toUpperCase()
                                                    color: playerLogo.picked ? "#ffffff" : "#8a8a8a"
                                                    font.family: window.uiFont
                                                    font.bold: true
                                                    font.pixelSize: 10
                                                }

                                                MouseArea {
                                                    id: logoHit
                                                    anchors.fill: parent
                                                    anchors.margins: -3
                                                    onClicked: window.selectPlayer(playerLogo.modelData.name)
                                                }
                                            }
                                        }
                                    }

                                    // B3 keeps this slot as the plain caption:
                                    // its control lives up in the status strip.
                                    Text {
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                        visible: window.mediaPlayers.length > 1
                                                 && window.playerSwitcherStyle === "segment"
                                        text: window.islandState.media.player || "MPRIS"
                                        elide: Text.ElideRight
                                        color: "#a8a8a8"
                                        font.family: window.uiFont
                                        font.capitalization: Font.AllUppercase
                                        font.letterSpacing: 1
                                        font.pixelSize: 8
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: window.islandState.media.title || "Dynamic Island"
                                elide: Text.ElideRight
                                color: window.mediaPanelText
                                font.family: window.uiFont
                                font.bold: true
                                font.pixelSize: 19
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                text: window.islandState.media.artist || i18n.unknownArtist
                                elide: Text.ElideRight
                                color: window.mediaPanelSubtext
                                font.family: window.uiFont
                                font.pixelSize: 11
                            }
                            // Visualiser and lyrics share this slot and
                            // cross-fade. Sharing it rather than stacking them
                            // means toggling lyrics never changes the panel's
                            // height, so nothing below shifts under the cursor.
                            //
                            // The collapsed pill's ribbon is hidden while the
                            // panel is open, so without the spectrum here the
                            // expanded view would have no visualiser at all.
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 34
                                clip: true

                                Spectrum {
                                    anchors.centerIn: parent
                                    height: Math.min(46, parent.height)
                                    bars: 32
                                    barWidth: 4
                                    barSpacing: 4
                                    peak: Math.max(6, height - 8)
                                    floorHeight: 3
                                    mirrored: true
                                    barColor: window.mediaPanelText
                                    opacity: (window.showLyrics || !window.mediaSpectrumEnabled) ? 0 : 1
                                    visible: opacity > 0.01
                                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                }

                                Column {
                                    id: lyricsPane
                                    anchors.centerIn: parent
                                    width: parent.width
                                    spacing: 3
                                    opacity: window.showLyrics ? 1 : 0
                                    visible: opacity > 0.01
                                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                    // Swapping three labels at once reads as a
                                    // flicker, because nothing tells the eye
                                    // that the block moved on by one line. The
                                    // whole column rises into place instead, so
                                    // a line change looks like the list
                                    // scrolling — which is what it actually is.
                                    //
                                    // Driven as a plain number that the
                                    // animation always returns to 0, so an
                                    // interrupted run (seeking, track change)
                                    // can never strand the column off-centre.
                                    property real slide: 0
                                    property real riseOpacity: 1
                                    transform: Translate { y: lyricsPane.slide }

                                    readonly property int lineIndex: window.currentLyricIndex
                                    onLineIndexChanged: if (window.lyricsSynced) lyricRise.restart()

                                    ParallelAnimation {
                                        id: lyricRise
                                        NumberAnimation {
                                            target: lyricsPane; property: "slide"
                                            from: 13; to: 0
                                            duration: 380; easing.type: Easing.OutCubic
                                        }
                                        NumberAnimation {
                                            target: lyricsPane; property: "riseOpacity"
                                            from: 0.25; to: 1
                                            duration: 320; easing.type: Easing.OutCubic
                                        }
                                        onRunningChanged: if (!running) {
                                            lyricsPane.slide = 0
                                            lyricsPane.riseOpacity = 1
                                        }
                                    }

                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: window.lyricPrev
                                        elide: Text.ElideRight
                                        color: window.mediaPanelMuted
                                        font.family: window.uiFont
                                        font.pixelSize: 9
                                        // Fades as it leaves rather than
                                        // blinking out at the top of the slide.
                                        opacity: 0.35 + lyricsPane.riseOpacity * 0.65
                                    }
                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: window.lyricCurrent
                                        elide: Text.ElideRight
                                        color: window.lyricIsPlaceholder ? window.mediaPanelMuted : window.mediaPanelText
                                        font.family: window.uiFont
                                        font.weight: window.lyricIsPlaceholder ? Font.Normal : Font.Bold
                                        font.italic: window.lyricIsPlaceholder
                                        font.pixelSize: window.lyricIsPlaceholder ? 10 : 13
                                        opacity: lyricsPane.riseOpacity
                                        // Grows into focus as it becomes the
                                        // current line, which is the cue that
                                        // it is the one being sung.
                                        scale: 0.94 + lyricsPane.riseOpacity * 0.06
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }
                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: window.lyricNext
                                        elide: Text.ElideRight
                                        color: window.mediaPanelMuted
                                        font.family: window.uiFont
                                        font.pixelSize: 9
                                        opacity: 0.35 + lyricsPane.riseOpacity * 0.65
                                    }
                                }
                            }

                            Slider {
                                id: seekSlider
                                Layout.fillWidth: true
                                Layout.preferredHeight: 18
                                // Keeps the arrow keys with the island instead
                                // of letting the slider claim them for seeking.
                                focusPolicy: Qt.NoFocus
                                from: 0
                                // Browser tabs (YouTube via Firefox/Chrome MPRIS
                                // included) routinely never report mpris:length
                                // at all. `to` has to be *something* for the
                                // Slider to compute visualPosition, but there is
                                // no real fraction to show without a real total
                                // — tying it to the position itself (an earlier
                                // attempt at this) made value/to permanently
                                // equal ~1, pinning the fill at the far end
                                // forever instead of fixing anything. The fill
                                // and handle are forced off below instead, so
                                // an arbitrary `to` here never actually renders.
                                to: window.mediaLengthKnown ? Math.max(1, window.islandState.media.length) : 1
                                enabled: window.mediaLengthKnown
                                opacity: enabled ? 1 : 0.45

                                // Follow playback only when the user isn't
                                // scrubbing, otherwise the poll fights the drag.
                                Binding on value {
                                    when: !seekSlider.pressed
                                    value: window.mediaPosition
                                }

                                background: Rectangle {
                                    x: seekSlider.leftPadding
                                    y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                                    width: seekSlider.availableWidth
                                    height: 4
                                    radius: 2
                                    color: window.mediaPanelTrack
                                    Rectangle {
                                        width: window.mediaLengthKnown ? seekSlider.visualPosition * parent.width : 0
                                        height: parent.height
                                        radius: 2
                                        color: window.mediaPanelOn
                                    }
                                }
                                handle: Rectangle {
                                    visible: window.mediaLengthKnown
                                    x: seekSlider.leftPadding + seekSlider.visualPosition * (seekSlider.availableWidth - width)
                                    y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                                    width: 11
                                    height: 11
                                    radius: 6
                                    color: window.mediaPanelText
                                    scale: seekSlider.pressed ? 1.25 : 1
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }

                                onMoved: {
                                    window.setInteracting(true)
                                    window.mediaPosition = value
                                    if (!seekThrottle.running) seekThrottle.start()
                                }
                                onPressedChanged: if (!pressed) {
                                    seekThrottle.stop()
                                    Quickshell.execDetached(["playerctl", "position", Math.round(value).toString()])
                                    window.setInteracting(false)
                                    positionSettleTimer.restart()
                                    delayedRefresh.restart()
                                }

                                Timer {
                                    id: seekThrottle
                                    interval: 70
                                    onTriggered: Quickshell.execDetached(["playerctl", "position", Math.round(seekSlider.value).toString()])
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: window.formatTime(window.mediaPosition); color: window.mediaPanelMuted; font.family: window.uiFont; font.pixelSize: 9 }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: window.mediaLengthKnown ? window.formatTime(window.islandState.media.length) : i18n.liveDuration
                                    color: window.mediaPanelMuted; font.family: window.uiFont; font.pixelSize: 9
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 10
                                spacing: 24
                                Repeater {
                                    model: [
                                        {i: window.mediaShuffle === "On" ? "󰒝" : "󰒞", c: "shuffle", lit: window.mediaShuffle === "On"},
                                        {i: "󰒮", c: "previous", lit: false},
                                        {i: window.mediaStatus === "Playing" ? "󰏤" : "󰐊", c: "play-pause", lit: false},
                                        {i: "󰒭", c: "next", lit: false},
                                        {i: window.mediaLoop === "Track" ? "󰑘" : "󰑖", c: "loop", lit: window.mediaLoop !== "None"}
                                    ]
                                    Text {
                                        required property var modelData
                                        required property int index
                                        text: modelData.i
                                        color: modelData.lit ? window.mediaPanelText
                                             : (transportHit.containsMouse ? window.mediaPanelText : window.mediaPanelSubtext)
                                        font.family: window.iconFont
                                        font.pixelSize: index === 2 ? 30 : 21
                                        scale: transportHit.pressed ? 0.84 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                        MouseArea {
                                            id: transportHit
                                            anchors.fill: parent
                                            anchors.margins: -9
                                            hoverEnabled: true
                                            onClicked: window.mediaAction(modelData.c)
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }

                    // ----------------------------------------------- clock view
                    Item {
                        id: clockView
                        anchors.fill: parent
                        visible: opacity > 0.01
                        opacity: window.idleView ? 1 : 0
                        scale: window.idleView ? 1 : 0.97
                        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                        // Nothing but the clock. The readout tiles that used to
                        // sit under it were the same weather/battery data again.
                        PixelClock {
                            anchors.centerIn: parent
                            time: window.currentTime
                            lang: window.lang
                            hour24: window.clock24Hour
                            style: window.clockStyle
                            textFont: window.uiFont
                            showSeconds: window.clockSeconds
                            showDate: window.clockDate
                            cell: 8
                            gap: 2
                            color: window.themeText
                            mutedColor: window.themeMuted
                            gridColor: window.clockGrid ? window.themeGrid : "transparent"
                        }
                    }
                }

                // ------------------------------------------------------ meters
                Rectangle {
                    Layout.preferredWidth: 164
                    Layout.fillHeight: true
                    radius: 20
                    color: (!window.idleView && window.mediaUsesDarkSurface) ? "#000000" : window.themeSurface
                    border.width: 1
                    border.color: window.themeLine

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 15

                        BarMeter {
                            label: i18n.volumeShort
                            fontFamily: window.uiFont
                            iconFont: window.iconFont
                            icon: window.islandState.muted ? "󰝟" : "󰕾"
                            value: window.islandState.muted ? 0 : window.islandState.volume
                            active: !window.islandState.muted
                            phase: window.visualPhase
                            labelColor: window.idleView ? window.themeMuted : window.mediaPanelMuted
                            filledColor: window.idleView ? window.themeOn : window.mediaPanelOn
                            emptyColor: window.idleView ? window.themeTrack : window.mediaPanelTrack
                            iconColor: window.idleView ? window.themeText : window.mediaPanelText
                            disabledColor: window.islandState.muted ? window.themeStatusAlert : (window.idleView ? window.themeMuted : window.mediaPanelMuted)
                            onDraggingChanged: window.setInteracting(dragging)
                            onMoved: v => window.runDirect(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", v + "%"])
                            onIconClicked: window.run(["mute"])
                        }
                        BarMeter {
                            label: i18n.brightnessShort
                            fontFamily: window.uiFont
                            iconFont: window.iconFont
                            icon: "󰃠"
                            value: window.islandState.brightness
                            phase: window.visualPhase
                            labelColor: window.idleView ? window.themeMuted : window.mediaPanelMuted
                            filledColor: window.idleView ? window.themeOn : window.mediaPanelOn
                            emptyColor: window.idleView ? window.themeTrack : window.mediaPanelTrack
                            iconColor: window.idleView ? window.themeText : window.mediaPanelText
                            disabledColor: window.idleView ? window.themeMuted : window.mediaPanelMuted
                            onDraggingChanged: window.setInteracting(dragging)
                            onMoved: v => window.runDirect(["brightnessctl", "set", v + "%"])
                        }
                        BarMeter {
                            label: i18n.micShort
                            fontFamily: window.uiFont
                            iconFont: window.iconFont
                            icon: window.islandState.micMuted ? "󰍭" : "󰍬"
                            value: window.islandState.micMuted ? 0 : window.islandState.micVolume
                            active: !window.islandState.micMuted
                            shimmer: window.islandState.micActive && !window.islandState.micMuted
                            phase: window.visualPhase
                            labelColor: window.idleView ? window.themeMuted : window.mediaPanelMuted
                            filledColor: window.idleView ? window.themeOn : window.mediaPanelOn
                            emptyColor: window.idleView ? window.themeTrack : window.mediaPanelTrack
                            iconColor: (window.islandState.micActive && !window.islandState.micMuted)
                                ? window.themeStatusLive
                                : (window.idleView ? window.themeText : window.mediaPanelText)
                            disabledColor: window.islandState.micMuted ? window.themeStatusAlert : (window.idleView ? window.themeMuted : window.mediaPanelMuted)
                            onDraggingChanged: window.setInteracting(dragging)
                            onMoved: v => window.runDirect(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SOURCE@", v + "%"])
                            onIconClicked: window.run(["mic-mute"])
                        }
                    }
                }
            }

            // ------------------------------------------- app mixer panel
            // Takes over the content area at the panel's existing size rather
            // than opening a card of its own: chip-toggled content must not
            // resize the island, or the control the pointer is reaching for
            // moves out from under it. Same rule the lyrics view follows.
            Item {
                id: appMixerPanel
                anchors { left: parent.left; right: parent.right; top: statusStrip.bottom; bottom: parent.bottom }
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 14
                anchors.bottomMargin: 18
                z: 5
                clip: true
                visible: opacity > 0.01
                opacity: window.showAppVolumes ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    color: (!window.idleView && window.mediaUsesDarkSurface) ? "#000000" : window.themeSurface
                    border.width: 1
                    border.color: window.themeLine
                }

                // Swallows clicks that would otherwise land on the transport
                // controls still sitting underneath this panel.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                Text {
                    id: mixerTitle
                    anchors { top: parent.top; left: parent.left; topMargin: 15; leftMargin: 20 }
                    text: i18n.appVolumeTitle
                    color: window.themeSubtext
                    font.family: window.uiFont
                    font.weight: Font.DemiBold
                    font.pixelSize: 11
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                }

                Text {
                    anchors.centerIn: parent
                    visible: window.appStreams.length === 0
                    text: i18n.appVolumeEmpty
                    color: window.themeMuted
                    font.family: window.uiFont
                    font.pixelSize: 11
                }

                // A row per application, full panel width. Vertical channel
                // strips matched the home meters more closely but ran out of
                // room past four apps, and a browser plus a music player plus a
                // chat client is an ordinary afternoon.
                Column {
                    anchors {
                        top: mixerTitle.bottom
                        left: parent.left
                        right: parent.right
                        topMargin: 10
                        leftMargin: 22
                        rightMargin: 22
                    }
                    spacing: 6

                    Repeater {
                        model: window.appStreams

                        AppVolumeRow {
                            required property var modelData
                            width: parent.width
                            appName: modelData.name
                            iconSource: window.resolveStreamIcon(modelData)
                            value: modelData.volume
                            muted: modelData.muted
                            active: modelData.active
                            phase: window.visualPhase
                            fontFamily: window.uiFont
                            iconFont: window.iconFont
                            textColor: window.idleView ? window.themeText : window.mediaPanelText
                            filledColor: window.idleView ? window.themeOn : window.mediaPanelOn
                            emptyColor: window.idleView ? window.themeTrack : window.mediaPanelTrack
                            disabledColor: window.idleView ? window.themeMuted : window.mediaPanelMuted
                            alertColor: window.themeStatusAlert
                            onDraggingChanged: window.setInteracting(dragging)
                            onMoved: v => window.setAppVolume(modelData, v)
                            onMuteToggled: window.toggleAppMute(modelData)
                        }
                    }
                }
            }

            // ----------------------------------------------- queue panel
            Item {
                id: queuePanel
                anchors { left: parent.left; right: parent.right; top: statusStrip.bottom; bottom: parent.bottom }
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 14
                anchors.bottomMargin: 18
                z: 5
                clip: true
                visible: opacity > 0.01
                opacity: window.showQueue ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    color: (!window.idleView && window.mediaUsesDarkSurface) ? "#000000" : window.themeSurface
                    border.width: 1
                    border.color: window.themeLine
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                Row {
                    id: queueHeader
                    anchors { top: parent.top; left: parent.left; topMargin: 15; leftMargin: 20 }
                    spacing: 8

                    Text {
                        text: i18n.queueTitle
                        color: window.themeSubtext
                        font.family: window.uiFont
                        font.weight: Font.DemiBold
                        font.pixelSize: 11
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1
                    }

                    // The limitation is named where the user meets it, not only
                    // in the settings row that switched this on.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: experimentalLabel.implicitWidth + 10
                        height: 14
                        radius: 4
                        color: window.themeChip

                        Text {
                            id: experimentalLabel
                            anchors.centerIn: parent
                            text: i18n.queueExperimental
                            color: window.themeMuted
                            font.family: window.uiFont
                            font.weight: Font.Bold
                            font.pixelSize: 8
                            font.letterSpacing: 1
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 60
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: !window.mediaQueue.supported || window.mediaQueue.tracks.length === 0
                    // Kept as two distinct messages: "your player never reports
                    // this" and "the queue happens to be empty" are different
                    // facts, and collapsing them would read as a bug either way.
                    text: window.mediaQueue.supported ? i18n.queueEmpty : i18n.queueUnsupported
                    color: window.themeMuted
                    font.family: window.uiFont
                    font.pixelSize: 11
                }

                // C1 — numbered list. The only variant that needs nothing but
                // title and artist, which is all a TrackList reliably carries.
                Column {
                    visible: window.queueStyle === "list"
                    anchors {
                        top: queueHeader.bottom
                        left: parent.left
                        right: parent.right
                        topMargin: 10
                        leftMargin: 20
                        rightMargin: 20
                    }
                    spacing: 4

                    Repeater {
                        model: window.queueStyle === "list" ? (window.mediaQueue.tracks || []) : []

                        Row {
                            required property var modelData
                            required property int index
                            width: parent.width
                            spacing: 12

                            // Numbered because in a queue the position is the
                            // content: it is what tells the user how far off a
                            // track is. Elsewhere in this island numbering would
                            // just be decoration.
                            Text {
                                width: 16
                                horizontalAlignment: Text.AlignRight
                                text: index + 1
                                color: window.themeMuted
                                font.family: window.uiFont
                                font.pixelSize: 10
                            }

                            Column {
                                width: parent.width - 28
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: modelData.title || "—"
                                    elide: Text.ElideRight
                                    color: window.idleView ? window.themeText : window.mediaPanelText
                                    font.family: window.uiFont
                                    font.pixelSize: 11
                                }
                                Text {
                                    width: parent.width
                                    visible: String(modelData.artist || "") !== ""
                                    text: modelData.artist
                                    elide: Text.ElideRight
                                    color: window.themeMuted
                                    font.family: window.uiFont
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }

                // C2 — cover strip. Closest to the media panel's own artwork
                // language, but TrackList often carries no art at all, so each
                // tile falls back to a note glyph rather than a blank hole.
                Flickable {
                    visible: window.queueStyle === "covers"
                    anchors {
                        top: queueHeader.bottom
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        topMargin: 12
                        leftMargin: 20
                        rightMargin: 20
                    }
                    contentWidth: coverStrip.width
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true

                    Row {
                        id: coverStrip
                        spacing: 10

                        Repeater {
                            model: window.queueStyle === "covers" ? (window.mediaQueue.tracks || []) : []

                            Column {
                                required property var modelData
                                width: 96
                                spacing: 6

                                Rectangle {
                                    width: 96
                                    height: 96
                                    radius: 12
                                    color: "#000000"
                                    border.width: 1
                                    border.color: window.themeLine
                                    clip: true

                                    Image {
                                        id: queueArt
                                        anchors.fill: parent
                                        source: String(modelData.art || "").replace("file://", "")
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: queueArt.status !== Image.Ready
                                        text: "󰎈"
                                        color: "#333333"
                                        font.family: window.iconFont
                                        font.pixelSize: 30
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.title || "—"
                                    elide: Text.ElideRight
                                    color: window.idleView ? window.themeText : window.mediaPanelText
                                    font.family: window.uiFont
                                    font.pixelSize: 10
                                }
                                Text {
                                    width: parent.width
                                    visible: String(modelData.artist || "") !== ""
                                    text: modelData.artist
                                    elide: Text.ElideRight
                                    color: window.themeMuted
                                    font.family: window.uiFont
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }

                // C3 — timeline. Answers "how long until my track", which needs
                // per-track lengths; when the player omits them the offset
                // column falls back to a plain position marker.
                Column {
                    visible: window.queueStyle === "timeline"
                    anchors {
                        top: queueHeader.bottom
                        left: parent.left
                        right: parent.right
                        topMargin: 10
                        leftMargin: 20
                        rightMargin: 20
                    }
                    spacing: 0

                    Repeater {
                        model: window.queueStyle === "timeline" ? (window.mediaQueue.tracks || []) : []

                        Row {
                            required property var modelData
                            required property int index
                            width: parent.width
                            spacing: 12

                            Text {
                                width: 48
                                horizontalAlignment: Text.AlignRight
                                text: window.queueOffsetLabel(index)
                                color: window.themeMuted
                                font.family: window.uiFont
                                font.pixelSize: 10
                            }

                            // The rail is drawn per row rather than as one line
                            // behind the column so it stops at the last knot
                            // instead of trailing into empty space.
                            Item {
                                width: 7
                                height: 30

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 11
                                    width: 1
                                    height: 19
                                    color: window.themeLine
                                    visible: index < (window.mediaQueue.tracks.length - 1)
                                }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 5
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: window.themeMuted
                                }
                            }

                            Column {
                                width: parent.width - 79
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: modelData.title || "—"
                                    elide: Text.ElideRight
                                    color: window.idleView ? window.themeText : window.mediaPanelText
                                    font.family: window.uiFont
                                    font.pixelSize: 11
                                }
                                Text {
                                    width: parent.width
                                    visible: String(modelData.artist || "") !== ""
                                    text: modelData.artist
                                    elide: Text.ElideRight
                                    color: window.themeMuted
                                    font.family: window.uiFont
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------ right: time instruments
            // One instrument, four modes. The readout never leaves the stage —
            // only the controls under it change — so switching modes reads as
            // the same display retuning rather than four separate screens.
            Item {
                id: timeToolsPage
                anchors.fill: parent
                z: 7
                visible: opacity > 0.01
                opacity: window.showTimePage ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }

                transform: Translate {
                    x: window.showTimePage ? 0 : 28
                    Behavior on x { NumberAnimation { duration: 330; easing.type: Easing.OutQuint } }
                }

                // Opaque, unlike the island's own glass fill: this page is a
                // sibling of the media panel rather than a layer above the
                // whole window, so any translucency here shows the album art
                // and meters straight through the readout.
                Rectangle {
                    id: collapsedBg
                    anchors.fill: parent
                    radius: 30
                    color: Qt.rgba(window.themeIslandFill.r,
                                   window.themeIslandFill.g,
                                   window.themeIslandFill.b, 1)
                    border.width: window.timeAlertPulse ? 2 : 0
                    border.color: window.timeAlertPulse
                        ? Qt.rgba(window.themeStatusAlert.r, window.themeStatusAlert.g, window.themeStatusAlert.b, 0.5 + Math.abs(Math.sin(window.visualPhase * 4)) * 0.5)
                        : "transparent"
                }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

                ColumnLayout {
                    anchors {
                        fill: parent
                        leftMargin: 40
                        rightMargin: 40
                        topMargin: 18
                        bottomMargin: 16
                    }
                    spacing: 10

                    // ---------------------------------------------- header
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: 20
                        Layout.maximumHeight: 20
                        spacing: 10

                        Text {
                            text: i18n.timeTitle
                            color: window.themeText
                            font.family: window.uiFont
                            font.weight: Font.Bold
                            font.pixelSize: 14
                        }

                        // Status reads as a pill only while something is live,
                        // so a resting page carries no colour at all.
                        Rectangle {
                            Layout.preferredWidth: statusLabel.implicitWidth + 20
                            Layout.preferredHeight: 18
                            radius: 9
                            color: window.timeModeRunning
                                ? Qt.rgba(window.timeAccent.r, window.timeAccent.g, window.timeAccent.b, 0.16)
                                : "transparent"
                            border.width: 1
                            border.color: window.timeModeRunning ? window.timeAccent : window.themeLine
                            Behavior on color { ColorAnimation { duration: 240 } }
                            Behavior on border.color { ColorAnimation { duration: 240 } }

                            Text {
                                id: statusLabel
                                anchors.centerIn: parent
                                text: window.timeStatusLabel
                                color: window.timeModeRunning ? window.timeAccent : window.themeMuted
                                font.family: window.uiFont
                                font.weight: Font.Bold
                                font.pixelSize: 8
                                font.letterSpacing: 0.9
                                Behavior on color { ColorAnimation { duration: 240 } }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: Qt.formatTime(window.currentTime, "HH:mm:ss")
                            color: window.themeMuted
                            font.family: window.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: 11
                            font.letterSpacing: 0.8
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: window.themeLineStrong
                    }

                    // ----------------------------------------------- stage
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: 11

                            // Mode name sits directly above its own readout,
                            // so the number is never ambiguous about which
                            // tool produced it.
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 8

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: window.timeModeIcon(window.timeMode)
                                    color: window.timeAccent
                                    font.family: window.iconFont
                                    font.pixelSize: 12
                                    Behavior on color { ColorAnimation { duration: 240 } }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: window.timeMode === "focus"
                                        ? (window.pomodoroWorkPhase ? i18n.tmPhaseFocus : i18n.tmPhaseBreak)
                                        : window.timeModeLabel(window.timeMode)
                                    color: window.themeMuted
                                    font.family: window.uiFont
                                    font.weight: Font.Bold
                                    font.pixelSize: 8
                                    font.letterSpacing: 1.6
                                }
                            }

                            // The hero. Drawn in the same 5x7 matrix as the
                            // island's clock, with the unlit cells left faintly
                            // visible: the dormant grid is what makes a digit
                            // changing read as a display, not a label.
                            PixelText {
                                id: heroReadout
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: window.timeReadout
                                // The stopwatch carries three more glyphs than
                                // the others, so it steps down a size rather
                                // than letting the row run under the margins.
                                cell: window.timeMode === "stopwatch" ? 6 : 8
                                gap: 2
                                color: window.timeAlertVisible || window.timeUrgent
                                    ? window.timeAccent
                                    : window.themeText
                                offColor: Qt.rgba(window.themeText.r, window.themeText.g, window.themeText.b, 0.07)
                                animated: true
                                rollDuration: 300
                                // Only the last ten seconds breathe. Everything
                                // before that is a display, not a warning.
                                opacity: window.timeUrgent
                                    ? 0.62 + Math.abs(Math.sin(window.visualPhase)) * 0.38
                                    : 1
                                Behavior on color { ColorAnimation { duration: 260 } }
                            }

                            // Progress built from the same square cells as the
                            // glyphs above it, so the readout and its progress
                            // are one instrument instead of a number with a bar
                            // parked underneath.
                            Row {
                                id: ledStrip
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                height: 12
                                spacing: 3

                                readonly property int cells: 44
                                readonly property real cellWidth:
                                    (width - spacing * (cells - 1)) / cells

                                Repeater {
                                    model: ledStrip.cells

                                    Rectangle {
                                        required property int index
                                        readonly property bool lit:
                                            (index + 1) / ledStrip.cells <= window.timeProgress

                                        anchors.verticalCenter: parent.verticalCenter
                                        width: ledStrip.cellWidth
                                        height: lit ? 12 : 5
                                        radius: 1.5
                                        color: lit ? window.timeAccent : window.themeTrack
                                        opacity: lit ? 1 : 0.5

                                        // Staggered by position so the strip
                                        // fills and drains as a travelling
                                        // ripple rather than snapping as a
                                        // block. Cheap: colour only settles on
                                        // the cells that actually crossed.
                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 240
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 260
                                                easing.type: Easing.OutBack
                                            }
                                        }
                                        Behavior on opacity {
                                            NumberAnimation { duration: 240 }
                                        }
                                    }
                                }
                            }

                            // ------------------------------------ controls
                            // Every mode lands its primary action in the same
                            // place; only the secondaries on the left change.
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                height: 34

                                // -- timer: duration presets
                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    visible: opacity > 0.01
                                    opacity: window.timeMode === "timer" ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }

                                    Repeater {
                                        model: [1, 5, 10, 25]

                                        TimeKey {
                                            required property int modelData
                                            width: 46
                                            label: modelData + (window.lang === "tr" ? " dk" : " m")
                                            active: window.countdownDuration === modelData * 60
                                            onTriggered: window.resetCountdown(modelData)
                                        }
                                    }
                                }

                                // -- stopwatch: the last four laps, newest first
                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    visible: opacity > 0.01
                                    opacity: window.timeMode === "stopwatch" ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: window.stopwatchLaps.length === 0
                                        text: i18n.tmLapsEmpty
                                        color: window.themeMuted
                                        font.family: window.uiFont
                                        font.pixelSize: 9
                                    }

                                    Repeater {
                                        model: window.stopwatchLaps

                                        Rectangle {
                                            required property var modelData
                                            required property int index
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 64
                                            height: 26
                                            radius: 8
                                            color: window.themeChip
                                            // Newest lap carries the full text
                                            // colour; older ones recede, so the
                                            // one just taken is findable without
                                            // reading all four.
                                            opacity: index === 0 ? 1 : 0.55

                                            Text {
                                                anchors.centerIn: parent
                                                text: window.stopwatchLabel(modelData)
                                                color: window.themeSubtext
                                                font.family: window.uiFont
                                                font.weight: Font.DemiBold
                                                font.pixelSize: 9
                                            }
                                        }
                                    }
                                }

                                // -- focus: completed cycles
                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 7
                                    visible: opacity > 0.01
                                    opacity: window.timeMode === "focus" ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: i18n.tmCycles
                                        color: window.themeMuted
                                        font.family: window.uiFont
                                        font.weight: Font.Bold
                                        font.pixelSize: 8
                                        font.letterSpacing: 1.1
                                    }

                                    // Four pips, one per pomodoro in the set.
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 5

                                        Repeater {
                                            model: 4

                                            Rectangle {
                                                required property int index
                                                width: 9
                                                height: 9
                                                radius: 4.5
                                                color: index < (window.pomodoroCycles % 4 === 0
                                                                && window.pomodoroCycles > 0
                                                                ? 4 : window.pomodoroCycles % 4)
                                                    ? window.themeStatusLive
                                                    : window.themeTrack
                                                Behavior on color { ColorAnimation { duration: 300 } }
                                            }
                                        }
                                    }
                                }

                                // -- alarm: hour and minute steppers
                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    visible: opacity > 0.01
                                    opacity: window.timeMode === "alarm" ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }

                                    Repeater {
                                        model: [
                                            { glyph: "󰁝", step: 60,  tag: "H" },
                                            { glyph: "󰁅", step: -60, tag: "H" },
                                            { glyph: "󰁝", step: 5,   tag: "M" },
                                            { glyph: "󰁅", step: -5,  tag: "M" }
                                        ]

                                        TimeKey {
                                            required property var modelData
                                            width: 46
                                            label: modelData.tag
                                            glyph: modelData.glyph
                                            onTriggered: {
                                                let total = (window.alarmHour * 60
                                                    + window.alarmMinute + modelData.step + 1440) % 1440
                                                window.alarmHour = Math.floor(total / 60)
                                                window.alarmMinute = total % 60
                                                window.lastAlarmKey = ""
                                            }
                                        }
                                    }
                                }

                                // -- primary + utilities, fixed on the right
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 7

                                    TimeKey {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: window.timeMode === "stopwatch"
                                        width: 34
                                        glyph: "󰈻"
                                        onTriggered: window.recordLap()
                                    }

                                    TimeKey {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: window.timeMode === "focus"
                                        width: 34
                                        glyph: "󰒭"
                                        onTriggered: window.advanceFocusPhase(false)
                                    }

                                    Rectangle {
                                        id: primaryAction
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 116
                                        height: 34
                                        radius: 12
                                        color: primaryHit.containsMouse
                                            ? Qt.lighter(window.themeOn, 1.08)
                                            : window.themeOn
                                        scale: primaryHit.pressed ? 0.96 : 1
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                        Behavior on scale {
                                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                        }

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 7

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: window.timeMode === "alarm"
                                                    ? (window.alarmEnabled ? "󰂛" : "󰀠")
                                                    : (window.timeModeRunning ? "󰏤" : "󰐊")
                                                color: window.themeOnText
                                                font.family: window.iconFont
                                                font.pixelSize: 13
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: window.timePrimaryLabel
                                                color: window.themeOnText
                                                font.family: window.uiFont
                                                font.weight: Font.Bold
                                                font.pixelSize: 10
                                            }
                                        }

                                        MouseArea {
                                            id: primaryHit
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.timePrimaryAction()
                                        }
                                    }

                                    TimeKey {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 34
                                        glyph: "󰑐"
                                        onTriggered: window.timeResetAction()
                                    }
                                }
                            }
                        }
                    }

                    // ------------------------------------------------ rail
                    // The other three tools stay on screen with their live
                    // values, so promoting one to the stage never hides what
                    // is still counting.
                    RowLayout {
                        Layout.fillWidth: true
                        // Pinned rather than merely preferred: a RowLayout in a
                        // ColumnLayout still stretches on preferredHeight alone,
                        // which let the rail eat the stage.
                        Layout.fillHeight: false
                        Layout.preferredHeight: 44
                        Layout.maximumHeight: 44
                        spacing: 7

                        Repeater {
                            model: window.timeModes

                            Rectangle {
                                required property var modelData
                                readonly property bool current: window.timeMode === modelData
                                readonly property bool live: window.timeModeIsRunning(modelData)

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 13
                                color: current ? window.themeOn
                                    : (railHit.containsMouse ? window.themeChipHover : window.themeChip)
                                border.width: 1
                                border.color: current ? window.themeOn : window.themeLine
                                Behavior on color { ColorAnimation { duration: 180 } }
                                Behavior on border.color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 11
                                    anchors.rightMargin: 11
                                    spacing: 8

                                    Text {
                                        text: window.timeModeIcon(modelData)
                                        color: current ? window.themeOnText : window.themeSubtext
                                        font.family: window.iconFont
                                        font.pixelSize: 14
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            text: window.timeModeLabel(modelData)
                                            elide: Text.ElideRight
                                            color: current ? window.themeOnText : window.themeMuted
                                            font.family: window.uiFont
                                            font.weight: Font.Bold
                                            font.pixelSize: 7
                                            font.letterSpacing: 1
                                            Behavior on color { ColorAnimation { duration: 180 } }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: window.timeModeValue(modelData)
                                            elide: Text.ElideRight
                                            color: current ? window.themeOnText : window.themeSubtext
                                            font.family: window.uiFont
                                            font.weight: Font.DemiBold
                                            font.pixelSize: 11
                                            Behavior on color { ColorAnimation { duration: 180 } }
                                        }
                                    }

                                    // Only drawn when that tool is actually
                                    // counting — an always-present dot would
                                    // stop meaning anything.
                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        width: 7
                                        height: 7
                                        radius: 3.5
                                        visible: live
                                        color: current ? window.themeOnText : window.themeStatusLive
                                        opacity: 0.45 + Math.abs(Math.sin(window.visualPhase)) * 0.55
                                    }
                                }

                                MouseArea {
                                    id: railHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: window.timeMode = modelData
                                }
                            }
                        }
                    }
                }
            }
            // Legacy quick-controls implementation is intentionally unreachable.
            // It remains inert here only to avoid destabilising unrelated shell
            // code while the calendar replaces it completely in the interface.
            // Built as a physical continuation under the 324px main island.
            // The parent deliberately does not clip: the island itself clips the
            // child against its animated height, producing a real downward
            // reveal instead of a page swap or side-drawer illusion.
            Item {
                id: quickSettingsPanel
                anchors {
                    top: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                    topMargin: 8
                }
                width: parent.width - 24
                height: 230
                z: 6
                visible: false
                opacity: 0
                scale: window.showQuickSettings ? 1 : 0.965
                transformOrigin: Item.Top

                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }

                Rectangle {
                    anchors.fill: parent
                    radius: 26
                    color: window.themeSurface
                    border.width: 1
                    border.color: window.themeLineStrong
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                // The small bridge makes the lower sheet read as belonging to
                // the island above, not as a second floating popup.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    width: 46
                    height: 4
                    radius: 2
                    color: window.themeLineStrong
                }

                ColumnLayout {
                    anchors {
                        fill: parent
                        topMargin: 16
                        leftMargin: 16
                        rightMargin: 16
                        bottomMargin: 15
                    }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 10
                            color: window.themeOn

                            Text {
                                anchors.centerIn: parent
                                text: "󰒔"
                                color: window.themeOnText
                                font.family: window.iconFont
                                font.pixelSize: 14
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: i18n.quickSettingsTitle
                            color: window.themeText
                            font.family: window.uiFont
                            font.weight: Font.Bold
                            font.pixelSize: 14
                        }

                        Rectangle {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: 11
                            color: quickCloseHit.containsMouse ? window.themeChipHover : window.themeChip
                            Behavior on color { ColorAnimation { duration: 140 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰅃"
                                color: window.themeSubtext
                                font.family: window.iconFont
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: quickCloseHit
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: window.showQuickSettings = false
                            }
                        }
                    }

                    component QuickControlSlider: Rectangle {
                        id: controlCard
                        property string controlIcon: ""
                        property string controlLabel: ""
                        property real sourceValue: 0
                        property real controlValue: sourceValue
                        property bool controlActive: true
                        signal moved(real value)
                        signal iconTriggered()

                        onSourceValueChanged: if (!quickSlider.pressed) controlValue = sourceValue

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 18
                        color: controlHover.hovered ? window.themeChipHover : window.themeChip
                        border.width: 1
                        border.color: controlHover.hovered ? window.themeLineStrong : window.themeLine
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        HoverHandler { id: controlHover }

                        Timer {
                            id: sliderThrottle
                            interval: 55
                            onTriggered: controlCard.moved(controlCard.controlValue)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: 12
                                color: controlCard.controlActive ? window.themeOn : window.themeSurfaceAlt

                                Text {
                                    anchors.centerIn: parent
                                    text: controlCard.controlIcon
                                    color: controlCard.controlActive ? window.themeOnText : window.themeMuted
                                    font.family: window.iconFont
                                    font.pixelSize: 17
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: controlCard.iconTriggered()
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: controlCard.controlLabel
                                        color: window.themeSubtext
                                        font.family: window.uiFont
                                        font.weight: Font.DemiBold
                                        font.pixelSize: 10
                                    }
                                    Text {
                                        text: Math.round(controlCard.controlValue) + "%"
                                        color: window.themeMuted
                                        font.family: window.uiFont
                                        font.pixelSize: 9
                                    }
                                }

                                Slider {
                                    id: quickSlider
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 18
                                    from: 0
                                    to: 100
                                    value: controlCard.controlValue
                                    onMoved: {
                                        controlCard.controlValue = value
                                        if (!sliderThrottle.running) sliderThrottle.start()
                                    }
                                    onPressedChanged: {
                                        window.setInteracting(pressed)
                                        if (!pressed) {
                                            sliderThrottle.stop()
                                            controlCard.moved(controlCard.controlValue)
                                        }
                                    }

                                    background: Rectangle {
                                        x: quickSlider.leftPadding
                                        y: quickSlider.topPadding + quickSlider.availableHeight / 2 - height / 2
                                        width: quickSlider.availableWidth
                                        height: 5
                                        radius: 2.5
                                        color: window.themeTrack
                                        Rectangle {
                                            width: quickSlider.visualPosition * parent.width
                                            height: parent.height
                                            radius: parent.radius
                                            color: controlCard.controlActive ? window.themeOn : window.themeMuted
                                        }
                                    }
                                    handle: Rectangle {
                                        x: quickSlider.leftPadding + quickSlider.visualPosition * (quickSlider.availableWidth - width)
                                        y: quickSlider.topPadding + quickSlider.availableHeight / 2 - height / 2
                                        implicitWidth: quickSlider.pressed ? 16 : 13
                                        implicitHeight: implicitWidth
                                        radius: width / 2
                                        color: window.themeText
                                        border.width: 3
                                        border.color: window.themeSurface
                                        Behavior on implicitWidth { NumberAnimation { duration: 120 } }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 62
                        Layout.minimumHeight: 62
                        Layout.maximumHeight: 62
                        spacing: 10

                        QuickControlSlider {
                            controlIcon: window.islandState.muted ? "󰝟" : "󰕾"
                            controlLabel: i18n.volumeShort
                            sourceValue: window.islandState.muted ? 0 : window.islandState.volume
                            controlActive: !window.islandState.muted
                            onMoved: value => window.runDirect(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", Math.round(value) + "%"])
                            onIconTriggered: window.run(["mute"])
                        }

                        QuickControlSlider {
                            controlIcon: "󰃠"
                            controlLabel: i18n.brightnessShort
                            sourceValue: window.islandState.brightness
                            onMoved: value => window.runDirect(["brightnessctl", "set", Math.round(value) + "%"])
                        }
                    }

                    component QuickActionTile: Rectangle {
                        id: tile
                        property string tileIcon: ""
                        property string tileLabel: ""
                        property bool active: false
                        property bool danger: false
                        signal triggered()

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 17
                        color: tile.active ? window.themeOn
                            : (tileHit.containsMouse ? window.themeChipHover : window.themeChip)
                        border.width: 1
                        border.color: tile.danger ? Qt.rgba(window.themeStatusAlert.r, window.themeStatusAlert.g, window.themeStatusAlert.b, 0.42)
                                                        : (tile.active ? window.themeOn : window.themeLine)
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Behavior on border.color { ColorAnimation { duration: 160 } }
                        scale: tileHit.pressed ? 0.96 : 1
                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: 11
                                color: tile.active ? Qt.rgba(window.themeOnText.r, window.themeOnText.g, window.themeOnText.b, 0.14)
                                                   : window.themeSurfaceAlt
                                Text {
                                    anchors.centerIn: parent
                                    text: tile.tileIcon
                                    font.family: window.iconFont
                                    font.pixelSize: 16
                                    color: tile.active ? window.themeOnText
                                        : (tile.danger ? window.themeStatusAlert : window.themeText)
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: tile.tileLabel
                                font.family: window.uiFont
                                font.weight: Font.DemiBold
                                font.pixelSize: 9
                                color: tile.active ? window.themeOnText : window.themeSubtext
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: tileHit
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: tile.triggered()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 78
                        Layout.minimumHeight: 78
                        Layout.maximumHeight: 78
                        spacing: 8

                        QuickActionTile {
                            tileIcon: window.dndActive ? "󰂛" : "󰂚"
                            tileLabel: i18n.qsDnd
                            active: window.dndActive
                            onTriggered: window.dndActive = !window.dndActive
                        }

                        QuickActionTile {
                            tileIcon: window.islandState.bluetoothPowered ? "󰂯" : "󰂲"
                            tileLabel: i18n.qsBluetooth
                            active: window.islandState.bluetoothPowered
                            onTriggered: window.run(["bluetooth-toggle"])
                        }

                        QuickActionTile {
                            tileIcon: window.islandState.system.wifiPowered ? "󰖩" : "󰖪"
                            tileLabel: i18n.qsWifi
                            active: window.islandState.system.wifiPowered
                            onTriggered: window.run(["wifi-toggle"])
                        }

                        QuickActionTile {
                            tileIcon: "󰌾"
                            tileLabel: i18n.qsLock
                            onTriggered: window.runDirect(["bash", "-c", "~/.config/hypr/scripts/lock.sh"])
                        }

                        QuickActionTile {
                            tileIcon: "󰍃"
                            tileLabel: i18n.qsLogout
                            danger: true
                            onTriggered: window.runDirect(["hyprctl", "dispatch", "exit"])
                        }
                    }
                }
            }

        }

        // ------------------------------------------------------ time completion
        // The island changing shape is the alert. Nothing else on this desktop
        // can do that, so a finished timer gets the one gesture that is unique
        // to this surface rather than another rectangle sliding past.
        Item {
            id: timeAlertCard
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: window.timeAlertVisible ? 1 : 0
            z: 21
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            // Anywhere on the card dismisses. A person reaching for an alarm
            // is not aiming carefully, and the explicit button below is for
            // when they want to be sure rather than the only way through.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: window.dismissTimeAlertByPointer()
            }

            Rectangle {
                id: timeAlertSweep
                y: 1
                width: 110
                height: parent.height - 2
                radius: 30
                color: window.themeStatusAlert
                opacity: 0.07
                rotation: 18
                x: -400
                NumberAnimation on x {
                    running: window.timeAlertVisible
                    from: -160
                    to: timeAlertCard.width + 140
                    duration: 1600
                    loops: Animation.Infinite
                    easing.type: Easing.InOutCubic
                    onRunningChanged: if (!running) timeAlertSweep.x = -400
                }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 24; topMargin: 16; bottomMargin: 16 }
                spacing: 16

                // Icon in a ring that beats on the shared sine, at the same
                // rate the battery card uses for "act now".
                Item {
                    Layout.preferredWidth: 62
                    Layout.preferredHeight: 62

                    Rectangle {
                        id: timeAlertRing
                        anchors.centerIn: parent
                        width: 58
                        height: 58
                        radius: 20
                        color: "transparent"
                        border.width: 1.5
                        border.color: window.themeStatusAlert
                        opacity: 0.35 + Math.abs(Math.sin(window.visualPhase * 2.2)) * 0.65
                    }

                    Rectangle {
                        id: timeAlertIconBox
                        anchors.centerIn: parent
                        width: 44
                        height: 44
                        radius: 15
                        color: window.themeStatusAlert

                        Text {
                            anchors.centerIn: parent
                            text: window.timeAlertIcon
                            color: "#ffffff"
                            font.family: window.iconFont
                            font.pixelSize: 22
                        }
                    }

                    // One decisive arrival, then the ring carries it. Restarted
                    // per alert from raiseTimeAlert rather than bound to the
                    // visible flag, so a second timer landing on the back of the
                    // first still gets its own entrance.
                    SequentialAnimation {
                        id: timeAlertPop
                        ParallelAnimation {
                            NumberAnimation {
                                target: timeAlertIconBox; property: "scale"
                                from: 0.6; to: 1.16; duration: 320; easing.type: Easing.OutBack
                            }
                            NumberAnimation {
                                target: timeAlertRing; property: "scale"
                                from: 0.7; to: 1.2; duration: 380; easing.type: Easing.OutBack
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: timeAlertIconBox; property: "scale"
                                to: 1.0; duration: 240; easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: timeAlertRing; property: "scale"
                                to: 1.0; duration: 240; easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        text: window.timeAlertTitle
                        elide: Text.ElideRight
                        color: window.themeText
                        font.family: window.uiFont
                        font.weight: Font.Bold
                        font.pixelSize: 16
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.timeAlertDetail
                        elide: Text.ElideRight
                        color: window.themeSubtext
                        font.family: window.uiFont
                        font.pixelSize: 11
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        // Says which keys work, because the card is reachable
                        // without the pointer and there is no other signpost.
                        text: window.lang === "tr"
                            ? "Esc · Boşluk · tıkla"
                            : "Esc · Space · click"
                        color: window.themeMuted
                        font.family: window.uiFont
                        font.weight: Font.DemiBold
                        font.pixelSize: 8
                        font.letterSpacing: 0.8
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 104
                    Layout.preferredHeight: 40
                    radius: 14
                    color: dismissHit.containsMouse
                        ? window.themeStatusAlert
                        : Qt.rgba(window.themeStatusAlert.r, window.themeStatusAlert.g, window.themeStatusAlert.b, 0.16)
                    border.width: 1
                    border.color: window.themeStatusAlert
                    scale: dismissHit.pressed ? 0.95 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: i18n.tmDismiss
                        color: dismissHit.containsMouse ? "#ffffff" : window.themeText
                        font.family: window.uiFont
                        font.weight: Font.Bold
                        font.pixelSize: 11
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        id: dismissHit
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.dismissTimeAlertByPointer()
                    }
                }
            }
        }

        // ---------------------------------------------------------- device card
        Item {
            id: deviceEventCard
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: window.deviceEventVisible ? 1 : 0
            z: 19
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Rectangle {
                id: eventSweep
                y: 1
                width: 90
                height: parent.height - 2
                radius: 30
                color: window.themeText
                opacity: 0.04
                rotation: 18
                x: -400
                NumberAnimation on x {
                    running: window.deviceEventVisible
                    from: -140
                    to: deviceEventCard.width + 120
                    duration: 1400
                    easing.type: Easing.InOutCubic
                    // Parked well off-screen on stop instead of freezing wherever
                    // it happened to be when the card was dismissed.
                    onRunningChanged: if (!running) eventSweep.x = -400
                }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 22; topMargin: 12; bottomMargin: 12 }
                spacing: 16

                Item {
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 60

                    Rectangle {
                        id: devicePulseRing
                        anchors.centerIn: parent
                        width: 56
                        height: 56
                        radius: 19
                        color: "transparent"
                        border.width: window.deviceEventType === "battery" ? 1.5 : 1
                        // cameraClosing is a brief pulse (see presentDeviceEvent),
                        // not an animation targeting this property directly —
                        // driving it through the binding plus a Behavior keeps
                        // the binding itself alive, unlike an imperative
                        // ColorAnimation here would (which snaps it dead the
                        // first time it runs, per the project's own animation
                        // convention above).
                        border.color: window.deviceEventType === "battery" || window.cameraClosing
                            ? window.themeStatusAlert
                            : window.themeLineStrong
                        Behavior on border.color { ColorAnimation { duration: 260 } }
                        // Battery gets an urgent, fast blink instead of the calm
                        // sine breathing the other two use — it is the one card
                        // that means "do something now", not "here's a status".
                        opacity: window.deviceEventType === "microphone"
                            ? 0.35 + Math.abs(Math.sin(window.visualPhase)) * 0.6
                            : (window.deviceEventType === "battery"
                                ? 0.4 + Math.abs(Math.sin(window.visualPhase * 2.6)) * 0.6
                                : 0.7)
                        // One decisive turn when the camera comes on — snappy
                        // and slightly overshooting, like a mechanical iris
                        // engaging — not a continuous spin, which used to run
                        // identically whether the card meant "on" or "off".
                        RotationAnimation {
                            id: cameraSpinOn
                            target: devicePulseRing
                            property: "rotation"
                            from: 0
                            to: 380
                            duration: 560
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.1
                            onRunningChanged: if (!running) devicePulseRing.rotation = 0
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 62; height: 62; radius: 21
                        color: "transparent"
                        border.width: 1
                        border.color: window.deviceEventType === "battery" ? Qt.rgba(0.76, 0.29, 0.29, 0.4) : window.themeLine
                    }
                    Rectangle {
                        id: deviceIconBox
                        anchors.centerIn: parent
                        width: 42; height: 42; radius: 14
                        color: window.deviceEventType === "battery" ? window.themeStatusAlert : window.themeOn
                        Text {
                            anchors.centerIn: parent
                            text: window.deviceEventIcon
                            color: window.deviceEventType === "battery" ? "#ffffff" : window.themeOnText
                            font.family: window.iconFont
                            font.pixelSize: 23
                        }

                        // Camera off: a shutter blade sweeps across the icon
                        // and fades, in sync with the icon's own scale-dip —
                        // together they read as the lens physically shutting,
                        // not just a dimmer version of the "on" pop.
                        Rectangle {
                            id: cameraCloseBlade
                            anchors.centerIn: parent
                            width: 0
                            height: 5
                            radius: 2.5
                            color: window.themeStatusAlert
                            opacity: 0
                        }
                    }

                    // The camera-on "flash": a quick burst of light behind the
                    // icon, like a shutter actually firing open. This is the
                    // one-time cue that made "on" feel decisive rather than
                    // just a spin nobody has time to notice.
                    Rectangle {
                        id: cameraFlash
                        anchors.centerIn: parent
                        width: 46; height: 46; radius: 23
                        color: "#ffffff"
                        opacity: 0
                        scale: 0.5
                    }

                    SequentialAnimation {
                        id: devicePulse
                        NumberAnimation { target: devicePulseRing; property: "scale"; from: 0.74; to: 1.14; duration: 340; easing.type: Easing.OutBack }
                        NumberAnimation { target: devicePulseRing; property: "scale"; to: 1.0; duration: 240; easing.type: Easing.OutCubic }
                    }

                    ParallelAnimation {
                        id: cameraFlashPop
                        NumberAnimation { target: cameraFlash; property: "scale"; from: 0.5; to: 1.6; duration: 420; easing.type: Easing.OutCubic }
                        SequentialAnimation {
                            NumberAnimation { target: cameraFlash; property: "opacity"; from: 0; to: 0.6; duration: 80 }
                            NumberAnimation { target: cameraFlash; property: "opacity"; to: 0; duration: 320; easing.type: Easing.OutCubic }
                        }
                    }

                    SequentialAnimation {
                        id: cameraShutterBlink
                        ParallelAnimation {
                            NumberAnimation { target: deviceIconBox; property: "scale"; to: 0.82; duration: 110; easing.type: Easing.InCubic }
                            SequentialAnimation {
                                NumberAnimation { target: cameraCloseBlade; property: "width"; from: 0; to: 34; duration: 110; easing.type: Easing.OutCubic }
                            }
                            NumberAnimation { target: cameraCloseBlade; property: "opacity"; from: 0; to: 0.95; duration: 70 }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: deviceIconBox; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                            NumberAnimation { target: cameraCloseBlade; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
                        }
                        PropertyAction { target: cameraCloseBlade; property: "width"; value: 0 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: window.deviceEventTitle
                        color: window.themeText
                        font.family: window.uiFont
                        font.weight: Font.Bold
                        font.pixelSize: 16
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.deviceEventSubtitle
                        color: window.themeMuted
                        font.family: window.uiFont
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Row {
                    visible: window.deviceEventType === "microphone" && !window.islandState.micMuted
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 3
                    Repeater {
                        model: 6
                        Rectangle {
                            required property int index
                            width: 3
                            radius: 1.5
                            color: window.themeStatusLive
                            // No Behavior: the driving sine is already smooth, and
                            // animating toward a target that moves every frame
                            // only damps it back down to a flat line.
                            height: 6 + Math.abs(Math.sin(window.visualPhase * 1.4 + index)) * 18
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Rectangle {
                    visible: window.deviceEventType === "camera"
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 9
                    Layout.preferredHeight: 9
                    radius: 4.5
                    color: window.islandState.cameraActive ? window.themeStatusLive : window.themeTrack
                    // Bound to the shared phase rather than a private infinite
                    // loop, so it can never be left mid-blink.
                    opacity: window.islandState.cameraActive
                        ? 0.35 + Math.abs(Math.sin(window.visualPhase * 0.7)) * 0.65
                        : 1
                }
            }
        }

        // ---------------------------------------------------- notification card
        Item {
            id: notificationCard
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: window.notificationVisible ? 1 : 0
            z: 18
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            ColumnLayout {
                anchors { fill: parent; leftMargin: 18; rightMargin: 22; topMargin: 14; bottomMargin: 18 }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        Layout.alignment: Qt.AlignVCenter
                        radius: 16
                        // Tracks whether the logo is really being drawn, not
                        // just whether one was supplied — with app icons off
                        // the tile has to become the light initial-badge plate.
                        readonly property bool showsLogo: window.notificationAppIcon
                                                          && window.notificationIcon !== ""
                        color: showsLogo ? window.themeSurfaceAlt : window.themeOn
                        border.width: 1
                        border.color: showsLogo ? window.themeLineStrong : window.themeOn

                        Image {
                            id: notificationLogo
                            anchors.centerIn: parent
                            width: 30; height: 30
                            source: window.notificationAppIcon ? window.notificationIcon : ""
                            visible: window.notificationAppIcon
                                     && window.notificationIcon !== "" && status === Image.Ready
                            sourceSize.width: 64
                            sourceSize.height: 64
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !notificationLogo.visible
                            text: window.notificationApp.length > 0 ? window.notificationApp.charAt(0).toUpperCase() : "󰂚"
                            color: window.themeOnText
                            font.family: window.notificationApp.length > 0 ? window.uiFont : "Iosevka Nerd Font"
                            font.weight: Font.Black
                            font.pixelSize: 22
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        Text {
                            text: window.notificationApp || i18n.notification
                            color: window.themeMuted
                            font.family: window.uiFont
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.2
                            font.pixelSize: 9
                        }
                        Text {
                            Layout.fillWidth: true
                            text: window.notificationTitle || i18n.newNotification
                            color: window.themeText
                            font.family: window.uiFont
                            font.weight: Font.Bold
                            font.pixelSize: 16
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: window.notificationBody || i18n.emptyNotification
                            color: window.themeSubtext
                            font.family: window.uiFont
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    // Copies the message body to the clipboard — the thing
                    // worth grabbing from a notification (a code, a link, an
                    // address) is almost always in the body, not the title,
                    // which is usually just the sender's name.
                    PanelChip {
                        Layout.alignment: Qt.AlignTop
                        visible: window.notificationBody !== ""
                        icon: window.notificationCopied ? "󰄬" : "󰆏"
                        lit: window.notificationCopied
                        onTriggered: window.copyNotificationContent()
                    }
                }

                // Only appears when the sender actually attached a KDE-style
                // "inline-reply" action — Quickshell strips that action out
                // of the visible list itself and surfaces it as
                // hasInlineReply/inlineReplyPlaceholder, so there is no
                // guessing here about whether the app wants this.
                RowLayout {
                    id: replyRow
                    Layout.fillWidth: true
                    visible: window.notificationHasReply && window.notificationInlineReply
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: 10
                        color: window.themeSurface
                        border.width: 1
                        border.color: replyField.activeFocus ? window.themeText : window.themeLineStrong
                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        TextField {
                            id: replyField
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            text: window.notificationReplyText
                            placeholderText: window.notificationReplyPlaceholder !== ""
                                ? window.notificationReplyPlaceholder : i18n.replyPlaceholder
                            color: window.themeText
                            placeholderTextColor: window.themeMuted
                            font.family: window.uiFont
                            font.pixelSize: 12
                            background: Item {}
                            leftPadding: 0
                            rightPadding: 0
                            topPadding: 0
                            bottomPadding: 0
                            selectByMouse: true

                            onTextChanged: window.notificationReplyText = text
                            onAccepted: window.sendNotificationReply()

                            // A drafted reply must never vanish out from under
                            // the person typing it — pause the auto-dismiss
                            // countdown while focused, and only resume it if
                            // they back out without sending.
                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    notificationTimer.stop()
                                    notificationProgress.pause()
                                } else if (text === "") {
                                    notificationTimer.restart()
                                    notificationProgress.resume()
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 10
                        opacity: window.notificationReplyText.trim() !== "" ? 1 : 0.35
                        color: sendHit.containsMouse ? window.themeChipHover : window.themeSurfaceAlt
                        Behavior on color { ColorAnimation { duration: 140 } }
                        scale: sendHit.pressed ? 0.88 : 1
                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰒊"
                            color: window.themeText
                            font.family: window.iconFont
                            font.pixelSize: 15
                        }

                        MouseArea {
                            id: sendHit
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: window.notificationReplyText.trim() !== ""
                            onClicked: window.sendNotificationReply()
                        }
                    }
                }
            }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.bottomMargin: 10
                height: 2
                radius: 1
                color: window.themeTrack

                Rectangle {
                    id: notificationBar
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: window.themeOn
                    transformOrigin: Item.Left
                    // Scaled rather than resized so the countdown never triggers
                    // a relayout on every frame.
                    scale: 1
                }
            }

            NumberAnimation {
                id: notificationProgress
                target: notificationBar
                property: "scale"
                from: 1
                to: 0
                // Tracks the dismiss timer, so the bar always empties exactly
                // as the card goes rather than drifting from the real timeout.
                duration: window.notificationSeconds * 1000
                easing.type: Easing.Linear
            }
        }

        // ---------------------------------------------------------- call card
        // Two distinct layouts, not one card with bits toggled: a ringing call
        // is a different mode, not another alert, so the island should read
        // as switching into an actual call screen — big centered avatar with
        // radar rings, then collapsing to a compact bar once audio confirms
        // the call actually connected.
        Item {
            id: callCard
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: window.callVisible ? 1 : 0
            scale: window.callVisible ? 1 : 0.92
            z: 21
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 0.7 } }

            readonly property bool live: !!window.islandState.call.active
            readonly property bool ringing: !live && !window.callAnswering
            readonly property real radarPhase: window.visualPhase / (Math.PI * 2)

            property real durationPop: 1
            onLiveChanged: if (live) durationPulse.restart()
            SequentialAnimation {
                id: durationPulse
                NumberAnimation { target: callCard; property: "durationPop"; from: 0.55; to: 1.16; duration: 190; easing.type: Easing.OutBack; easing.overshoot: 2 }
                NumberAnimation { target: callCard; property: "durationPop"; to: 1; duration: 150; easing.type: Easing.OutCubic }
            }

            // -------------------------------------------------- ringing / connecting
            Item {
                id: bigView
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: window.callBigView ? 1 : 0
                scale: window.callBigView ? 1 : 0.9
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 6

                    Item { Layout.preferredHeight: 2 }

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 78
                        Layout.preferredHeight: 78

                        Repeater {
                            model: callCard.ringing ? 3 : 0
                            Rectangle {
                                required property int index
                                readonly property real p: (callCard.radarPhase + index / 3) % 1
                                anchors.centerIn: parent
                                width: 60 + p * 46
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.width: 1.4
                                border.color: Qt.rgba(0.4, 0.88, 0.58, (1 - p) * 0.5)
                            }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 62; height: 62; radius: 31
                            color: window.themeSurface
                            border.width: 1
                            border.color: callCard.live ? window.themeLineStrong : "#4a5ce97e"
                            Behavior on border.color { ColorAnimation { duration: 220 } }
                            Text {
                                anchors.centerIn: parent
                                text: window.callAnswering ? "󰏶" : "󰏷"
                                rotation: callCard.ringing ? Math.sin(window.visualPhase * 3) * 9 : 0
                                color: window.themeText
                                font.family: window.iconFont
                                font.pixelSize: 24
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        horizontalAlignment: Text.AlignHCenter
                        text: window.callDisplayTitle
                        color: window.themeText
                        font.family: window.uiFont
                        font.weight: Font.Bold
                        font.pixelSize: 18
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: window.callAnswering ? i18n.callConnecting : (window.callDisplayApp + " · " + i18n.incomingCall)
                        color: window.themeMuted
                        font.family: window.uiFont
                        font.pixelSize: 11
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 4
                        spacing: 30
                        opacity: callCard.ringing ? 1 : 0
                        scale: callCard.ringing ? 1 : 0.6
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                        CallButton {
                            accept: true
                            size: 46
                            label: i18n.accept
                            entranceDelay: 40
                            entranceActive: callCard.ringing
                            callEnabled: window.callAcceptId !== ""
                            onTriggered: window.answerCall()
                        }
                        CallButton {
                            accept: false
                            size: 46
                            label: i18n.decline
                            entranceDelay: 120
                            entranceActive: callCard.ringing
                            callEnabled: window.callDeclineId !== ""
                            onTriggered: window.rejectCall()
                        }
                    }
                }
            }

            // ---------------------------------------------------------- live / talking
            Item {
                id: compactView
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: window.callBigView ? 0 : 1
                scale: window.callBigView ? 0.92 : 1
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }

                RowLayout {
                    anchors { fill: parent; leftMargin: 18; rightMargin: 22; topMargin: 14; bottomMargin: 18 }
                    spacing: 14

                    Item {
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            anchors.centerIn: parent
                            width: 50; height: 50; radius: 25
                            color: window.themeSurface
                            border.width: 1
                            border.color: window.themeLineStrong
                            Text {
                                anchors.centerIn: parent
                                text: "󰏶"
                                color: window.themeText
                                font.family: window.iconFont
                                font.pixelSize: 20
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        Text {
                            text: window.callDisplayApp
                            color: window.themeMuted
                            font.family: window.uiFont
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.2
                            font.pixelSize: 9
                        }
                        Text {
                            Layout.fillWidth: true
                            text: window.callDisplayTitle
                            color: window.themeText
                            font.family: window.uiFont
                            font.weight: Font.Bold
                            font.pixelSize: 16
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            scale: callCard.durationPop
                            transformOrigin: Item.Left
                            text: callCard.live ? window.formatTime(window.islandState.call.duration) : i18n.callConnecting
                            color: window.themeSubtext
                            font.family: window.uiFont
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // Manual close — the live view has no timeout of its own (an
            // ongoing call is meant to stay up), so without this the card is
            // stuck on screen for as long as the PipeWire heuristic keeps
            // reporting the call active, same idea as the panel's own 󰅖 chip.
            PanelChip {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 12
                icon: "󰅖"
                danger: true
                z: 5
                onTriggered: window.dismissCallCard()
            }
        }

        // ------------------------------------------------------------ HUD pill
        Rectangle {
            id: hudCapsule
            readonly property bool showing: !window.alertVisible && (hudTimer.running || window.activityText !== "")
            visible: opacity > 0.01
            opacity: showing ? 1 : 0
            scale: showing ? 1 : 0.9
            Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: window.expanded ? parent.top : undefined
            anchors.topMargin: window.expanded ? 50 : 0
            anchors.verticalCenter: window.expanded ? undefined : parent.verticalCenter
            width: Math.min(parent.width - 24, hudRow.implicitWidth + 30)
            height: 34
            radius: 16
            color: window.themeHudFill
            border.width: 0
            z: 20

            RowLayout {
                id: hudRow
                anchors.centerIn: parent
                spacing: 10
                Text {
                    text: window.activityText !== "" ? window.activityText : window.hudKind
                    color: window.themeText
                    font.family: window.iconFont
                    font.pixelSize: 13
                }
                Rectangle {
                    visible: window.activityText === ""
                    Layout.preferredWidth: 104
                    Layout.preferredHeight: 4
                    radius: 2
                    color: window.themeTrack
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(100, window.hudValue)) / 100
                        height: parent.height
                        radius: 2
                        color: window.themeOn
                        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    visible: window.activityText === ""
                    text: window.hudValue + "%"
                    color: window.themeSubtext
                    font.family: window.uiFont
                    font.pixelSize: 10
                }
            }
        }
    }

    // A separate window/file rather than another card inside `island`: this
    // one is meant to close the island and take over the whole screen, so it
    // needs its own layer-shell surface, not just another layer of z-order.
    SettingsMenu {
        host: window
        screen: window.screen
        open: window.settingsOpen
        onDismissRequested: window.settingsOpen = false
    }

    // ------------------------------------------------------------- components
    component Spectrum: Row {
        id: spectrum
        property int bars: 16
        property real barWidth: 3
        property real barSpacing: 3
        property real peak: 15
        property real floorHeight: 2
        // Folds the band list around the centre so the low bands meet in the
        // middle, which reads much better than a one-directional ramp.
        property bool mirrored: false
        property color barColor: window.themeText
        property string animationStyle: window.mediaAnimationStyle
        property bool fillWidth: false
        property real baseAlpha: 0.28
        property real gainAlpha: 0.62
        property real intensity: window.mediaAnimationIntensity / 100

        spacing: barSpacing

        // Goes away entirely when nothing is playing. Leaving it up with every
        // bar collapsed to its floor height left a motionless row of stubs on
        // the pill, which reads exactly like an animation that got stuck.
        opacity: window.mediaStatus === "Playing" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        Repeater {
            model: spectrum.bars
            Rectangle {
                required property int index

                readonly property int band: {
                    if (!spectrum.mirrored) return index
                    let half = Math.floor(spectrum.bars / 2)
                    return index < half ? (half - 1 - index) : (index - half)
                }
                readonly property real level: window.visualLevels[band % window.visualLevels.length] || 0
                readonly property real audioAmp: window.cavaLive && level > 1
                    ? Math.min(1, level / 100) : 0
                readonly property real fallbackWave: Math.abs(Math.sin(window.visualPhase + band * 0.72))
                readonly property real rawAmp: window.cavaLive ? audioAmp : fallbackWave
                readonly property real amp: {
                    if (window.mediaStatus !== "Playing") return 0
                    // Live never invents motion: every bar comes directly from
                    // cava, so it matches the playing audio frame for frame.
                    if (spectrum.animationStyle === "live")
                        return window.cavaLive ? audioAmp : 0.035
                    if (spectrum.animationStyle === "calm")
                        return 0.08 + rawAmp * 0.32
                    // Wave keeps the flowing band-to-band silhouette while
                    // still leaning primarily on real audio when available.
                    return window.cavaLive
                        ? Math.min(1, audioAmp * 0.72 + fallbackWave * 0.28)
                        : fallbackWave
                }

                width: spectrum.fillWidth
                    ? Math.max(1, (spectrum.width - (spectrum.bars - 1) * spectrum.barSpacing) / spectrum.bars)
                    : spectrum.barWidth
                height: spectrum.floorHeight + amp * spectrum.peak
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(spectrum.barColor.r, spectrum.barColor.g, spectrum.barColor.b,
                               Math.min(1, (spectrum.baseAlpha + amp * spectrum.gainAlpha)
                                        * spectrum.intensity))

                // Only smooth cava's discrete 30 Hz samples. The synthetic
                // fallback already moves continuously, and running a Behavior
                // against a target that changes every frame just retargets the
                // animation before it goes anywhere — which flattened the wave
                // into a nearly motionless row of stubs.
                Behavior on height {
                    enabled: window.cavaLive
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                Behavior on color {
                    enabled: window.cavaLive
                    ColorAnimation { duration: 140 }
                }
            }
        }
    }

    component StatusDot: Item {
        id: dot
        property string icon: ""
        property bool lit: false
        // Privacy-sensitive indicators (mic/camera actually in use) get the
        // live-status green instead of the theme's plain "on" colour, so the
        // one thing worth noticing at a glance still stands out in a
        // greyscale UI. Everything else stays grayscale.
        property bool statusColored: false
        readonly property color litColor: statusColored ? window.themeStatusLive : window.themeText
        width: 22
        height: 30

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            text: dot.icon
            color: dot.lit ? dot.litColor : window.themeMuted
            font.family: window.iconFont
            font.pixelSize: 17
            Behavior on color { ColorAnimation { duration: 200 } }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: dot.lit ? 14 : 4
            height: 2.5
            radius: 1.25
            color: dot.lit ? dot.litColor : window.themeTrack
            Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    component CompactTransportButton: Rectangle {
        id: compactTransport
        property string icon: ""
        property bool primary: false
        signal triggered()

        width: primary ? 30 : 26
        height: 30
        radius: 10
        color: compactTransport.primary
            ? window.themeOn
            : (compactTransportHit.containsMouse ? window.themeChipHover : "transparent")
        scale: compactTransportHit.pressed ? 0.86 : 1
        Behavior on color { ColorAnimation { duration: 130 } }
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: compactTransport.icon
            color: compactTransport.primary ? window.themeOnText : window.themeSubtext
            font.family: window.iconFont
            font.pixelSize: compactTransport.primary ? 16 : 14
        }

        MouseArea {
            id: compactTransportHit
            anchors.fill: parent
            hoverEnabled: true
            onClicked: compactTransport.triggered()
        }
    }

    component CallButton: Column {
        id: callBtn
        property bool accept: true
        property bool callEnabled: true
        property real size: 38
        property string label: ""
        // Lets two buttons in the same row pop in one after another instead
        // of both snapping in at once — small, but it's the difference
        // between "a card appeared" and "controls are arriving".
        property int entranceDelay: 0
        property bool entranceActive: true
        signal triggered()

        spacing: 6

        property real popScale: 1
        onEntranceActiveChanged: if (entranceActive) entrancePop.restart()
        SequentialAnimation {
            id: entrancePop
            PauseAnimation { duration: callBtn.entranceDelay }
            NumberAnimation { target: callBtn; property: "popScale"; from: 0.5; to: 1.18; duration: 170; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            NumberAnimation { target: callBtn; property: "popScale"; to: 1; duration: 130; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: callBtn.size
            implicitHeight: callBtn.size
            radius: callBtn.size / 2
            opacity: callBtn.callEnabled ? 1 : 0.35
            color: callBtn.accept
                ? (btnHit.containsMouse ? "#3aa863" : "#276b41")
                : (btnHit.containsMouse ? "#c24a4e" : "#7a3235")
            scale: btnHit.pressed ? 0.88 : callBtn.popScale
            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 140 } }

            Text {
                anchors.centerIn: parent
                text: callBtn.accept ? "󰏲" : "󰏵"
                // Action buttons keep their semantic green/red surfaces in
                // every theme; their glyph must therefore stay light too.
                color: "#ffffff"
                font.family: window.iconFont
                font.pixelSize: callBtn.size * 0.4
            }

            MouseArea {
                id: btnHit
                anchors.fill: parent
                hoverEnabled: true
                enabled: callBtn.callEnabled
                onClicked: callBtn.triggered()
            }
        }

        Text {
            visible: callBtn.label !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: callBtn.label
            color: window.themeSubtext
            font.family: window.uiFont
            font.pixelSize: 10
        }
    }

    // A miniature of PanelChip for the one place that cannot use it: these sit
    // on the cover-art scrim, which deliberately ignores the theme (see the note
    // on its container), so the colors are fixed light-on-dark rather than theme
    // tokens — themeChip/themeOn would disappear against it on the white theme.
    component PlayerChip: Rectangle {
        id: pchip
        property string text: ""
        property bool lit: false
        signal triggered()

        implicitWidth: Math.min(56, pchipLabel.implicitWidth + 10)
        implicitHeight: 13
        radius: 4
        color: pchip.lit ? "#26ffffff" : "transparent"
        Behavior on color { ColorAnimation { duration: 160 } }
        scale: pchipHit.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        Text {
            id: pchipLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, pchip.width - 8)
            text: pchip.text
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: pchip.lit ? "#ffffff" : "#8a8a8a"
            font.family: window.uiFont
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1
            font.pixelSize: 8
            font.weight: pchip.lit ? Font.Bold : Font.Normal
            Behavior on color { ColorAnimation { duration: 160 } }
        }
        MouseArea {
            id: pchipHit
            anchors.fill: parent
            anchors.margins: -2
            hoverEnabled: true
            onClicked: pchip.triggered()
        }
    }

    // The one button shape the time page uses for everything that is not the
    // primary action: presets, steppers, lap, skip, reset. Same geometry
    // throughout, so the row keeps its rhythm as the stage changes modes.
    component TimeKey: Rectangle {
        id: key
        property string label: ""
        property string glyph: ""
        property bool active: false
        signal triggered()

        height: 34
        radius: 11
        color: key.active ? window.themeOn
            : (keyHit.containsMouse ? window.themeChipHover : window.themeChip)
        border.width: 1
        border.color: key.active ? window.themeOn : window.themeLine
        scale: keyHit.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        Row {
            anchors.centerIn: parent
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: key.glyph !== ""
                text: key.glyph
                color: key.active ? window.themeOnText : window.themeSubtext
                font.family: window.iconFont
                font.pixelSize: 11
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: key.label !== ""
                text: key.label
                color: key.active ? window.themeOnText : window.themeSubtext
                font.family: window.uiFont
                font.weight: Font.Bold
                font.pixelSize: 9
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        MouseArea {
            id: keyHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: key.triggered()
        }
    }

    component PanelChip: Rectangle {
        id: chip
        property string icon: ""
        // Set instead of `icon` for chips whose whole point is to show a word
        // rather than a symbol — the language switch has to say which language
        // it is currently in, which no icon can do.
        property string label: ""
        property bool lit: false
        // The classic close-button convention: this chip closes/dismisses
        // something, so hovering it should read as "clicking this is
        // destructive" the same way it does everywhere else on the desktop,
        // not blend in with the neutral toggle chips next to it.
        property bool danger: false
        readonly property bool dangerHover: chip.danger && chipHit.containsMouse
        signal triggered()

        implicitWidth: chip.label !== "" ? Math.max(28, chipLabel.implicitWidth + 12) : 28
        implicitHeight: 24
        radius: 9
        color: chip.lit ? window.themeOn
            : (chip.dangerHover ? window.themeStatusAlert : (chipHit.containsMouse ? window.themeChipHover : window.themeChip))
        Behavior on color { ColorAnimation { duration: 160 } }
        scale: chipHit.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        Text {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label !== "" ? chip.label : chip.icon
            color: chip.lit ? window.themeOnText : (chip.dangerHover ? "#ffffff" : window.themeSubtext)
            font.family: chip.label !== "" ? window.uiFont : window.iconFont
            font.weight: chip.label !== "" ? Font.Bold : Font.Normal
            font.letterSpacing: chip.label !== "" ? 0.5 : 0
            font.pixelSize: chip.label !== "" ? 10 : 12
            Behavior on color { ColorAnimation { duration: 160 } }
        }
        MouseArea {
            id: chipHit
            anchors.fill: parent
            anchors.margins: -3
            hoverEnabled: true
            onClicked: chip.triggered()
        }
    }

}
