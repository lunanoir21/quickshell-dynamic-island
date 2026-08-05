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
    // Open/close has exactly two inputs: the pointer is over the island, or the
    // island was locked open from the keyboard. Alerts open it on their own and
    // close themselves on a timer. Nothing else may pin it open, because every
    // extra owner of the open state is another way for it to get stuck there.
    property bool hovering: false
    property bool lockedOpen: false
    property bool notificationVisible: false
    property bool deviceEventVisible: false
    readonly property bool alertVisible: notificationVisible || deviceEventVisible
    readonly property bool expanded: hovering || lockedOpen || alertVisible

    // Set while a slider is being dragged so the pointer straying a few pixels
    // outside the island mid-drag can't collapse it. Guarded by a dead-man timer
    // because a lost release event used to leave this stuck on forever, which
    // silently disabled every close path.
    property bool interacting: false

    property var islandState: ({media:{status:"Stopped",title:"",artist:"",art:"",player:"",lyrics:"",shuffle:"Off",loop:"None",length:0,position:0},volume:0,muted:false,micVolume:0,micMuted:false,micActive:false,brightness:0,battery:100,batteryStatus:"",batteryTime:"",bluetooth:"",weather:{icon:"",temp:"",apparent:""},cameraActive:false,system:{wifi:"",activeWindow:"",fullscreen:0}})

    property int previousVolume: -1
    property int previousBrightness: -1
    property int previousBattery: -1
    property bool previousMicMuted: false
    property bool previousMicActive: false
    property bool previousCameraActive: false
    property bool startupRead: false

    property string hudKind: ""
    property int hudValue: 0
    property string activityText: ""

    property string notificationApp: ""
    property string notificationIcon: ""
    property string notificationTitle: ""
    property string notificationBody: ""

    property string deviceEventType: ""
    property string deviceEventTitle: ""
    property string deviceEventSubtitle: ""
    property string deviceEventIcon: ""

    property string uiFont: bricolage.status === FontLoader.Ready ? bricolage.name : "Bricolage Grotesque"
    readonly property bool previewMode: Quickshell.env("QS_ISLAND_PREVIEW") === "1"
    property bool fullscreenActive: !previewMode && Number(islandState.system.fullscreen || 0) > 0
    property date currentTime: new Date()

    // Lets the pixel clock be pulled up while something is still playing.
    property bool showClock: false
    readonly property bool idleView: showClock || mediaStatus === "Stopped"

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
        running: window.mediaStatus === "Playing" || window.islandState.micActive
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

    function showNotification(app, title, body, icon) {
        notificationApp = app
        notificationIcon = resolveAppIcon(app, icon)
        notificationTitle = title
        notificationBody = body
        deviceEventVisible = false
        notificationVisible = true
        notificationTimer.restart()
        notificationProgress.restart()
    }

    function showHud(kind, value) {
        hudKind = kind
        hudValue = value
        hudTimer.restart()
    }

    function showDeviceEvent(type, enabled, value) {
        notificationVisible = false
        deviceEventType = type
        if (type === "camera") {
            deviceEventIcon = enabled ? "󰄀" : "󰄁"
            deviceEventTitle = enabled ? "Kamera kullanılıyor" : "Kamera kapatıldı"
            deviceEventSubtitle = enabled ? "Bir uygulama görüntü alıyor" : "Görüntü akışı sonlandırıldı"
        } else {
            deviceEventIcon = enabled ? "󰍬" : "󰍭"
            deviceEventTitle = enabled ? "Mikrofon etkin" : "Mikrofon sessize alındı"
            deviceEventSubtitle = enabled ? "Giriş seviyesi  %" + value : "Ses girişi durduruldu"
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
        function deviceEvent(type: string, enabled: bool, value: int): void { window.showDeviceEvent(type, enabled, value) }
        function notification(app: string, title: string, body: string): void {
            window.showNotification(app, title, body, "")
        }
        // The notification server already knows the sending app's icon, which is
        // more accurate than looking it up from the name.
        function notify(app: string, title: string, body: string, icon: string): void {
            window.showNotification(app, title, body, icon)
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
                            window.activityText = "󰂄  Şarj ediliyor  " + next.battery + "%"
                            activityTimer.restart()
                        }
                    }
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
        // Only spend a cava process on real spectrum data while the panel is
        // actually on screen; the collapsed pill's wave falls back to a cheap
        // synthetic curve that costs nothing.
        running: window.mediaStatus === "Playing" && window.expanded && !window.fullscreenActive
        onRunningChanged: if (!running) window.visualLevels = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
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
        interval: 5000
        onTriggered: {
            window.notificationVisible = false
            window.notificationApp = ""
            window.notificationIcon = ""
            window.notificationTitle = ""
            window.notificationBody = ""
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
    readonly property real targetWidth: expanded
        ? Math.min(notificationVisible ? 480 : (deviceEventVisible ? 400 : 700), window.width - 40)
        : compactWidth
    readonly property real targetHeight: expanded
        ? (notificationVisible ? 118 : (deviceEventVisible ? 92 : 300))
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

        border.width: 1
        border.color: window.expanded
            ? "#33ffffff"
            : Qt.rgba(1, 1, 1, 0.12 + window.playGlow * 0.22)

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#f4191919" }
            GradientStop { position: 0.5; color: "#f20d0d0d" }
            GradientStop { position: 1.0; color: "#f5121212" }
        }

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
            color: "#40ffffff"
            opacity: window.expanded ? 0.8 : 0.4
            Behavior on opacity { NumberAnimation { duration: 260 } }
        }

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: parent.height * 0.5
            opacity: window.expanded ? 0.045 : 0.085
            Behavior on opacity { NumberAnimation { duration: 260 } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#ffffff" }
                GradientStop { position: 1.0; color: "#00ffffff" }
            }
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
                if (hovered) {
                    closeTimer.stop()
                    window.hovering = true
                } else {
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
                closeTimer.stop()
                window.hovering = true
            }
            onExited: closeTimer.restart()
        }

        // Right click dismisses. Left click deliberately does nothing here:
        // leaving the island is meant to close it, so an accidental click on
        // empty panel space must never be able to latch it open. Pinning is
        // only ever an explicit act — the pin chip or the keybind.
        MouseArea {
            id: clickArea
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: window.closeIsland()
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

            // Spectrum ribbon along the top edge of the pill.
            Spectrum {
                anchors.top: parent.top
                anchors.topMargin: 3
                anchors.horizontalCenter: parent.horizontalCenter
                height: 18
                z: 5
                bars: 16
                barWidth: 3
                barSpacing: 3
                peak: 15
            }

            RowLayout {
                id: compactContent
                anchors.centerIn: parent
                anchors.verticalCenterOffset: window.mediaStatus === "Playing" ? 4 : 0
                spacing: 14

                PixelClock {
                    visible: window.mediaStatus === "Stopped"
                    time: window.currentTime
                    cell: 2
                    gap: 1
                    compact: true
                    color: "#f4f4f4"
                    mutedColor: "#7d7d7d"
                    gridColor: "#00000000"
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
                        color: "#1b1b1b"
                        clip: true
                        border.width: 1
                        border.color: "#38ffffff"
                        Image {
                            id: artThumbImage
                            anchors.fill: parent
                            source: String(window.islandState.media.art || "").replace("file://", "")
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: artThumbImage.status !== Image.Ready
                            text: "󰎈"
                            color: "#8a8a8a"
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
                        border.color: "#ffffff"
                        visible: window.mediaStatus === "Playing"
                        opacity: (1 - window.ringPulse) * 0.45
                        scale: 0.86 + window.ringPulse * 0.4
                    }
                }

                Text {
                    visible: window.mediaStatus !== "Stopped"
                    Layout.maximumWidth: 210
                    text: window.islandState.media.title || "Medya"
                    elide: Text.ElideRight
                    color: "#f2f2f2"
                    font.family: window.uiFont
                    font.weight: Font.DemiBold
                    font.pixelSize: 14
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 24; color: "#26ffffff" }

                Row {
                    visible: window.mediaStatus === "Stopped"
                    spacing: 7
                    Text { text: window.islandState.weather.icon || "󰖐"; color: "#e8e8e8"; font.family: window.iconFont; font.pixelSize: 18 }
                    Text { text: window.islandState.weather.temp || "--°"; color: "#d0d0d0"; font.family: window.uiFont; font.weight: Font.DemiBold; font.pixelSize: 14 }
                }

                PixelText {
                    visible: window.mediaStatus !== "Stopped"
                    text: Qt.formatDateTime(window.currentTime, "HH:mm")
                    cell: 2
                    gap: 1
                    color: "#e6e6e6"
                    animated: true
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 24; color: "#26ffffff" }

                Text {
                    text: (window.islandState.batteryStatus === "Charging" ? "󰂄  " : "󰁹  ") + window.islandState.battery + "%"
                    color: "#c6c6c6"
                    font.family: window.iconFont
                    font.pixelSize: 14
                }

                Row {
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

                // Controls only. Every readout — weather, bluetooth, battery,
                // load — belongs to the collapsed pill, which is the
                // at-a-glance surface; repeating it here just turned the open
                // panel into a status dashboard.
                Item { Layout.fillWidth: true }

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
                            color: "#141414"
                            clip: true
                            border.width: 1
                            border.color: "#16ffffff"

                            Image {
                                id: homeArt
                                anchors.fill: parent
                                source: String(window.islandState.media.art || "").replace("file://", "")
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
                            // Scrim so the caption stays legible over any cover.
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#20000000" }
                                    GradientStop { position: 0.55; color: "#66000000" }
                                    GradientStop { position: 1.0; color: "#e0000000" }
                                }
                            }
                            Column {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 13 }
                                spacing: 3
                                Text {
                                    width: parent.width
                                    text: window.islandState.media.title || "Bir şey çalmıyor"
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
                                color: "#ffffff"
                                font.family: window.uiFont
                                font.bold: true
                                font.pixelSize: 19
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                text: window.islandState.media.artist || "Bilinmeyen sanatçı"
                                elide: Text.ElideRight
                                color: "#989898"
                                font.family: window.uiFont
                                font.pixelSize: 11
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                visible: window.islandState.media.lyrics !== ""
                                text: window.islandState.media.lyrics
                                elide: Text.ElideRight
                                color: "#767676"
                                font.family: window.uiFont
                                font.italic: true
                                font.pixelSize: 10
                            }

                            // Music mode's own spectrum. The collapsed pill's
                            // ribbon is hidden while the panel is open, so
                            // without this the expanded view had no visualiser
                            // at all.
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 34

                                Spectrum {
                                    anchors.centerIn: parent
                                    height: Math.min(46, parent.height)
                                    bars: 32
                                    barWidth: 4
                                    barSpacing: 4
                                    peak: Math.max(6, height - 8)
                                    floorHeight: 3
                                    mirrored: true
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
                                to: Math.max(1, window.islandState.media.length || 1)

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
                                    color: "#2b2b2b"
                                    Rectangle {
                                        width: seekSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color: "#ededed"
                                    }
                                }
                                handle: Rectangle {
                                    x: seekSlider.leftPadding + seekSlider.visualPosition * (seekSlider.availableWidth - width)
                                    y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                                    width: 11
                                    height: 11
                                    radius: 6
                                    color: "#ffffff"
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
                                Text { text: window.formatTime(window.mediaPosition); color: "#7f7f7f"; font.family: window.uiFont; font.pixelSize: 9 }
                                Item { Layout.fillWidth: true }
                                Text { text: window.formatTime(window.islandState.media.length); color: "#7f7f7f"; font.family: window.uiFont; font.pixelSize: 9 }
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
                                        color: modelData.lit ? "#ffffff" : (transportHit.containsMouse ? "#ffffff" : "#adadad")
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
                            cell: 8
                            gap: 2
                            color: "#f6f6f6"
                            mutedColor: "#8d8d8d"
                            gridColor: "#191919"
                        }
                    }
                }

                // ------------------------------------------------------ meters
                Rectangle {
                    Layout.preferredWidth: 152
                    Layout.fillHeight: true
                    radius: 20
                    color: "#131313"
                    border.width: 1
                    border.color: "#16ffffff"

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 15

                        BarMeter {
                            label: "SES"
                            fontFamily: window.uiFont
                            iconFont: window.iconFont
                            icon: window.islandState.muted ? "󰝟" : "󰕾"
                            value: window.islandState.muted ? 0 : window.islandState.volume
                            active: !window.islandState.muted
                            phase: window.visualPhase
                            onDraggingChanged: window.setInteracting(dragging)
                            onMoved: v => window.runDirect(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", v + "%"])
                            onIconClicked: window.run(["mute"])
                        }
                        BarMeter {
                            label: "IŞIK"
                            fontFamily: window.uiFont
                            iconFont: window.iconFont
                            icon: "󰃠"
                            value: window.islandState.brightness
                            phase: window.visualPhase
                            onDraggingChanged: window.setInteracting(dragging)
                            onMoved: v => window.runDirect(["brightnessctl", "set", v + "%"])
                        }
                        BarMeter {
                            label: "MİK"
                            fontFamily: window.uiFont
                            iconFont: window.iconFont
                            icon: window.islandState.micMuted ? "󰍭" : "󰍬"
                            value: window.islandState.micMuted ? 0 : window.islandState.micVolume
                            active: !window.islandState.micMuted
                            shimmer: window.islandState.micActive && !window.islandState.micMuted
                            phase: window.visualPhase
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
                color: "#ffffff"
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
                        border.color: "#66ffffff"
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
                        border.color: "#1effffff"
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 42; height: 42; radius: 14
                        color: "#ededed"
                        Text {
                            anchors.centerIn: parent
                            text: window.deviceEventIcon
                            color: "#0a0a0a"
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
                        color: "#f5f5f5"
                        font.family: window.uiFont
                        font.weight: Font.Bold
                        font.pixelSize: 16
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.deviceEventSubtitle
                        color: "#8b8b8b"
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
                            color: "#dedede"
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
                    color: window.islandState.cameraActive ? "#f2f2f2" : "#4d4d4d"
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

            RowLayout {
                anchors { fill: parent; leftMargin: 18; rightMargin: 22; topMargin: 14; bottomMargin: 18 }
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 50
                    Layout.preferredHeight: 50
                    Layout.alignment: Qt.AlignVCenter
                    radius: 16
                    color: window.notificationIcon !== "" ? "#1a1a1a" : "#f0f0f0"
                    border.width: 1
                    border.color: window.notificationIcon !== "" ? "#2effffff" : "#ffffff"

                    Image {
                        id: notificationLogo
                        anchors.centerIn: parent
                        width: 30; height: 30
                        source: window.notificationIcon
                        visible: window.notificationIcon !== "" && status === Image.Ready
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
                        color: "#0b0b0b"
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
                        text: window.notificationApp || "Bildirim"
                        color: "#8b8b8b"
                        font.family: window.uiFont
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.2
                        font.pixelSize: 9
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.notificationTitle || "Yeni bildirim"
                        color: "#f5f5f5"
                        font.family: window.uiFont
                        font.weight: Font.Bold
                        font.pixelSize: 16
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.notificationBody || "Bildirim içeriği bulunmuyor."
                        color: "#b2b2b2"
                        font.family: window.uiFont
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
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
                color: "#242424"

                Rectangle {
                    id: notificationBar
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "#f2f2f2"
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
                duration: 5000
                easing.type: Easing.Linear
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
            color: "#f21b1b1b"
            border.width: 1
            border.color: "#26ffffff"
            z: 20

            RowLayout {
                id: hudRow
                anchors.centerIn: parent
                spacing: 10
                Text {
                    text: window.activityText !== "" ? window.activityText : window.hudKind
                    color: "#ffffff"
                    font.family: window.iconFont
                    font.pixelSize: 13
                }
                Rectangle {
                    visible: window.activityText === ""
                    Layout.preferredWidth: 104
                    Layout.preferredHeight: 4
                    radius: 2
                    color: "#3b3b3b"
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(100, window.hudValue)) / 100
                        height: parent.height
                        radius: 2
                        color: "#ffffff"
                        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    visible: window.activityText === ""
                    text: window.hudValue + "%"
                    color: "#c4c4c4"
                    font.family: window.uiFont
                    font.pixelSize: 10
                }
            }
        }
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
                readonly property real amp: window.mediaStatus !== "Playing" ? 0
                    : (window.cavaLive && level > 1 ? Math.min(1, level / 100)
                                                    : Math.abs(Math.sin(window.visualPhase + band * 0.72)))

                width: spectrum.barWidth
                height: spectrum.floorHeight + amp * spectrum.peak
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.28 + amp * 0.62)

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
            color: dot.lit ? "#ffffff" : "#666666"
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
            color: dot.lit ? "#ffffff" : "#454545"
            Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    component PanelChip: Rectangle {
        id: chip
        property string icon: ""
        property bool lit: false
        signal triggered()

        implicitWidth: 28
        implicitHeight: 24
        radius: 9
        color: chip.lit ? "#ededed" : (chipHit.containsMouse ? "#26ffffff" : "#14ffffff")
        Behavior on color { ColorAnimation { duration: 160 } }
        scale: chipHit.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: chip.icon
            color: chip.lit ? "#0b0b0b" : "#d6d6d6"
            font.family: window.iconFont
            font.pixelSize: 12
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
