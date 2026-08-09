import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
    readonly property bool alertVisible: notificationVisible || deviceEventVisible || callVisible
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

    property var islandState: ({media:{status:"Stopped",title:"",artist:"",art:"",player:"",shuffle:"Off",loop:"None",length:0,position:0},volume:0,muted:false,micVolume:0,micMuted:false,micActive:false,brightness:0,battery:100,batteryStatus:"",batteryTime:"",bluetooth:"",weather:{icon:"",temp:"",apparent:""},cameraActive:false,call:{active:false,app:"",duration:0},system:{wifi:"",activeWindow:"",fullscreen:0}})

    property int previousVolume: -1
    property int previousBrightness: -1
    property int previousBattery: -1
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
        }
    })
    readonly property var themeOrder: ["black", "umbra", "gray", "white"]
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
            mediaAnimationIntensity: window.mediaAnimationIntensity
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
        running: window.mediaStatus === "Playing" || window.islandState.micActive || window.callRinging || window.callAnswering
        loops: Animation.Infinite
        from: 0; to: Math.PI * 2
        duration: 1100
        onRunningChanged: if (!running) window.visualPhase = 0
    }

    // ----------------------------------------------------------------- media
    // Transport controls apply locally first so the UI reacts on click instead
    // of waiting for the next backend poll. Overrides expire once a snapshot
    // has had time to catch up.
    property string mediaStatusOverride: ""
    property string mediaShuffleOverride: ""
    property string mediaLoopOverride: ""
    readonly property string mediaStatus: mediaStatusOverride !== "" ? mediaStatusOverride : islandState.media.status
    readonly property string mediaShuffle: mediaShuffleOverride !== "" ? mediaShuffleOverride : islandState.media.shuffle
    readonly property string mediaLoop: mediaLoopOverride !== "" ? mediaLoopOverride : islandState.media.loop

    Timer {
        id: mediaOverrideTimer
        interval: 1000
        onTriggered: {
            window.mediaStatusOverride = ""
            window.mediaShuffleOverride = ""
            window.mediaLoopOverride = ""
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
    }

    function closeIsland() {
        lockedOpen = false
        hovering = false
        notificationVisible = false
        deviceEventVisible = false
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
        onTriggered: window.currentTime = new Date()
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
        deviceEventVisible = false
        notificationVisible = true
        notificationTimer.restart()
        notificationProgress.restart()
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

    function showDeviceEvent(type, enabled, value) {
        if (window.callVisible) return
        notificationVisible = false
        deviceEventType = type
        if (type === "camera") {
            deviceEventIcon = enabled ? "󰄀" : "󰄁"
            deviceEventTitle = enabled ? i18n.cameraOn : i18n.cameraOff
            deviceEventSubtitle = enabled ? i18n.cameraOnDetail : i18n.cameraOffDetail
        } else {
            deviceEventIcon = enabled ? "󰍬" : "󰍭"
            deviceEventTitle = enabled ? i18n.micOn : i18n.micOff
            deviceEventSubtitle = enabled ? i18n.micOnDetail(value) : i18n.micOffDetail
        }
        deviceEventVisible = true
        deviceEventTimer.restart()
        devicePulse.restart()
    }

    IpcHandler {
        target: "dynamicIsland"
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
        function settings(): void {
            window.settingsOpen = !window.settingsOpen
            if (window.settingsOpen) window.closeIsland()
        }
        // "black", "umbra", "gray", "white", or "cycle" — so a keybind can
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
        command: [window.backend, "snapshot"]
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
        interval: window.expanded
            ? 800
            : (window.mediaStatus === "Playing" || window.islandState.micActive || window.islandState.cameraActive ? 1400 : 2000)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!snapshot.running) snapshot.running = true
    }
    Timer { id: delayedRefresh; interval: 180; onTriggered: if (!snapshot.running) snapshot.running = true }
    Timer { id: hudTimer; interval: 1700 }
    Timer { id: activityTimer; interval: 5000; onTriggered: window.activityText = "" }
    Timer {
        id: deviceEventTimer
        interval: 2800
        onTriggered: window.deviceEventVisible = false
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
    readonly property real targetWidth: expanded
        ? Math.min(notificationVisible ? 500 : (deviceEventVisible ? 420 : (callVisible ? (callBigView ? 360 : 500) : 780)), window.width - 40)
        : compactWidth
    // Mirrors replyRow's own visibility rather than notificationHasReply alone:
    // with inline reply switched off the field is gone, and the card must not
    // keep reserving the 42px it used to occupy.
    readonly property bool notificationReplyShown: notificationHasReply && notificationInlineReply
    readonly property real targetHeight: expanded
        ? (notificationVisible ? (notificationReplyShown ? 168 : 124) : (deviceEventVisible ? 98 : (callVisible ? (callBigView ? 270 : 124) : 324)))
        : 54

    Rectangle {
        id: island

        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !window.fullscreenActive

        width: window.targetWidth
        height: window.targetHeight
        radius: window.expanded ? (window.alertVisible ? 24 : 30) : 20
        clip: true

        // Only ever reachable while pinned, since that is the only state where
        // the surface holds the keyboard.
        focus: true
        Keys.onPressed: event => {
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
        border.width: ringPulseActive ? 1 : 0
        border.color: Qt.rgba(0.35, 0.86, 0.55, 0.4 + Math.abs(Math.sin(window.visualPhase)) * 0.35)

        color: window.themeIslandFill

        // Opening overshoots very slightly, closing does not: a pop on the way
        // out reads as a glitch, while a pop on the way in reads as physical.
        Behavior on width {
            NumberAnimation {
                duration: window.expanded ? 460 : 300
                easing.type: window.expanded ? Easing.OutBack : Easing.InOutQuad
                easing.overshoot: 0.7
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: window.expanded ? 460 : 300
                easing.type: window.expanded ? Easing.OutBack : Easing.InOutQuad
                easing.overshoot: 0.55
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

                Rectangle {
                    visible: !window.compactPlayerMode
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 24
                    color: window.themeLineStrong
                }

                Text {
                    visible: !window.compactPlayerMode
                    text: (window.islandState.batteryStatus === "Charging" ? "󰂄  " : "󰁹  ") + window.islandState.battery + "%"
                    color: window.themeSubtext
                    font.family: window.iconFont
                    font.pixelSize: 14
                }

                Row {
                    visible: !window.compactPlayerMode
                    spacing: 9
                    StatusDot {
                        icon: window.islandState.micMuted ? "󰍭" : "󰍬"
                        lit: window.islandState.micActive && !window.islandState.micMuted
                    }
                    StatusDot {
                        icon: window.islandState.cameraActive ? "󰄀" : "󰄁"
                        lit: window.islandState.cameraActive
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
                                Text {
                                    width: parent.width
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
                            disabledColor: window.idleView ? window.themeMuted : window.mediaPanelMuted
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
                            iconColor: window.idleView ? window.themeText : window.mediaPanelText
                            disabledColor: window.idleView ? window.themeMuted : window.mediaPanelMuted
                            onDraggingChanged: window.setInteracting(dragging)
                            onMoved: v => window.runDirect(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SOURCE@", v + "%"])
                            onIconClicked: window.run(["mic-mute"])
                        }
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
                        border.width: 1
                        border.color: window.themeLineStrong
                        opacity: window.deviceEventType === "microphone"
                            ? 0.35 + Math.abs(Math.sin(window.visualPhase)) * 0.6
                            : 0.7
                        RotationAnimation on rotation {
                            running: window.deviceEventVisible && window.deviceEventType === "camera"
                            from: 0
                            to: 360
                            duration: 2400
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) devicePulseRing.rotation = 0
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 62; height: 62; radius: 21
                        color: "transparent"
                        border.width: 1
                        border.color: window.themeLine
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 42; height: 42; radius: 14
                        color: window.themeOn
                        Text {
                            anchors.centerIn: parent
                            text: window.deviceEventIcon
                            color: window.themeOnText
                            font.family: window.iconFont
                            font.pixelSize: 23
                        }
                    }

                    SequentialAnimation {
                        id: devicePulse
                        NumberAnimation { target: devicePulseRing; property: "scale"; from: 0.74; to: 1.14; duration: 340; easing.type: Easing.OutBack }
                        NumberAnimation { target: devicePulseRing; property: "scale"; to: 1.0; duration: 240; easing.type: Easing.OutCubic }
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
                            color: window.themeSubtext
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
                    color: window.islandState.cameraActive ? window.themeText : window.themeTrack
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
        width: 22
        height: 30

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            text: dot.icon
            color: dot.lit ? window.themeText : window.themeMuted
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
            color: dot.lit ? window.themeText : window.themeTrack
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

    component PanelChip: Rectangle {
        id: chip
        property string icon: ""
        // Set instead of `icon` for chips whose whole point is to show a word
        // rather than a symbol — the language switch has to say which language
        // it is currently in, which no icon can do.
        property string label: ""
        property bool lit: false
        signal triggered()

        implicitWidth: chip.label !== "" ? Math.max(28, chipLabel.implicitWidth + 12) : 28
        implicitHeight: 24
        radius: 9
        color: chip.lit ? window.themeOn : (chipHit.containsMouse ? window.themeChipHover : window.themeChip)
        Behavior on color { ColorAnimation { duration: 160 } }
        scale: chipHit.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        Text {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label !== "" ? chip.label : chip.icon
            color: chip.lit ? window.themeOnText : window.themeSubtext
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
