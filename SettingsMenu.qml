// The island's settings, as their own full-screen layer-shell surface rather
// than a card squeezed into the island: opening it closes the island (see
// DynamicIsland.qml's gear PanelChip) and this takes over the whole screen
// instead, centered, the way a real settings app would.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Deliberately "dumb": every setting it shows and every toggle it triggers
// reads/writes straight through `host` (the DynamicIsland PanelWindow), and
// closing is a signal rather than owning its own open state — so there is
// exactly one source of truth (window.settingsOpen) and this file is free to
// be reloaded/restyled without touching that state machine.
PanelWindow {
    id: settingsWin

    required property var host
    property bool open: false
    property string section: "appearance"

    // Shared by the sliding nav indicator and by keyboard navigation, so both
    // move through sections in the same order the sidebar lists them in.
    readonly property var navOrder: ["appearance", "clock", "timetools", "media", "calls", "notifications", "panels", "general"]
    readonly property int sectionIndex: navOrder.indexOf(section)
    function moveSection(delta) {
        var idx = navOrder.indexOf(settingsWin.section)
        settingsWin.section = navOrder[(idx + delta + navOrder.length) % navOrder.length]
    }

    signal dismissRequested()

    readonly property var i18n: host.i18n

    // The one place a theme id maps to its display name, so the picker's
    // cards and the group note below it can't drift out of sync with each
    // other — or with settings.json valid values.
    function themeDisplayName(name) {
        switch (name) {
        case "black": return i18n.themeBlack
        case "gray": return i18n.themeGray
        case "white": return i18n.themeWhite
        case "gold": return i18n.themeGold
        case "amber": return i18n.themeAmber
        case "red": return i18n.themeRed
        default: return i18n.themeUmbra
        }
    }

    // These used to be hardcoded to the umbra palette so the settings menu
    // stayed put while the island changed theme underneath it — the name
    // "fixed" is what's left of that. They now track whichever theme is
    // actually active, the same table the island itself reads, and each one
    // carries a Behavior so picking a new theme crossfades the whole window
    // instead of cutting to it.
    // Not readonly, unlike the rest of this file's properties: a Behavior
    // has to be able to take a property over mid-transition, which this QML
    // engine refuses on a read-only one — these are still only ever driven
    // by the bindings below, nothing else in the file assigns to them.
    readonly property var livePalette: host.palette
    property color fixedScrim: livePalette.scrim
    property color fixedSurface: livePalette.surface
    property color fixedSurfaceAlt: livePalette.surfaceAlt
    property color fixedText: livePalette.text
    property color fixedSubtext: livePalette.subtext
    property color fixedMuted: livePalette.muted
    property color fixedLine: livePalette.line
    property color fixedLineStrong: livePalette.lineStrong
    property color fixedChip: livePalette.chip
    property color fixedChipHover: livePalette.chipHover
    property color fixedOn: livePalette.on
    property color fixedOnText: livePalette.onText
    property color fixedTrack: livePalette.track
    property color fixedGrid: livePalette.grid
    // Alerts (a muted mic, a destructive action) stay this fixed red no
    // matter the theme — the same rule the island itself follows.
    readonly property color fixedStatusAlert: "#c24a4e"

    Behavior on fixedScrim { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedSurface { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedSurfaceAlt { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedText { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedSubtext { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedMuted { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedLine { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedLineStrong { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedChip { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedChipHover { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedOn { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedOnText { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedTrack { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fixedGrid { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }

    // A deep link from the settingsSection IPC call. Consumed once and cleared,
    // so it steers this opening only and the next one still remembers where the
    // user actually was.
    //
    // Both triggers are needed: the request usually lands while the window is
    // still closed (so opening consumes it), but a second call made while it is
    // already open changes only the request, which would otherwise go ignored.
    function consumeSectionRequest() {
        if (!settingsWin.open || host.settingsSectionRequest === "") return
        settingsWin.section = host.settingsSectionRequest
        host.settingsSectionRequest = ""
    }

    onOpenChanged: consumeSectionRequest()

    Connections {
        target: settingsWin.host
        function onSettingsSectionRequestChanged() { settingsWin.consumeSectionRequest() }
    }

    function revealClock() {
        // Clock choices should have an observable result even while media is
        // playing. The next time the island is shown, lead with the live clock.
        settingsWin.host.showClock = true
    }

    // Stays mapped the whole time — same rule the rest of this project
    // follows (see `island`'s own mask in DynamicIsland.qml): a layer-shell
    // surface whose Wayland mapping gets toggled on a QtQuick `visible`
    // binding is a known way to end up with an unkillable, unresponsive
    // surface still owning input on some compositors. Interactivity is
    // gated by `mask` instead — an empty region while closed is fully
    // click-through, so this is a no-op on the desktop until opened.
    WlrLayershell.namespace: "qs-dynamic-island-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: Region {
        x: 0
        y: 0
        width: settingsWin.open ? settingsWin.width : 0
        height: settingsWin.open ? settingsWin.height : 0
    }

    Shortcut {
        sequence: "Escape"
        enabled: settingsWin.open
        onActivated: settingsWin.dismissRequested()
    }

    Shortcut {
        sequence: "Down"
        enabled: settingsWin.open
        onActivated: settingsWin.moveSection(1)
    }

    Shortcut {
        sequence: "Up"
        enabled: settingsWin.open
        onActivated: settingsWin.moveSection(-1)
    }

    // Click-outside-to-dismiss. The window below has its own MouseArea that
    // swallows clicks so they never reach this one.
    Rectangle {
        anchors.fill: parent
        visible: opacity > 0.01
        color: settingsWin.fixedScrim
        opacity: settingsWin.open ? 1 : 0

        MouseArea {
            anchors.fill: parent
            onClicked: settingsWin.dismissRequested()
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        id: win

        anchors.centerIn: parent
        visible: opacity > 0.01
        width: Math.min(920, settingsWin.width - 32)
        height: Math.min(640, settingsWin.height - 32)
        radius: 28
        clip: true
        color: settingsWin.fixedSurface
        border.width: 1
        border.color: settingsWin.fixedLine
        opacity: settingsWin.open ? 1 : 0
        scale: settingsWin.open ? 1 : 0.97

        MouseArea {
            anchors.fill: parent
            onClicked: {
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 340
                easing.type: Easing.OutExpo
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ------------------------------------------------------ sidebar
            Rectangle {
                Layout.preferredWidth: 220
                Layout.fillHeight: true
                color: settingsWin.fixedChip

                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: settingsWin.fixedLine
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 22
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 16
                        Layout.leftMargin: 6
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 11
                            color: settingsWin.fixedOn

                            Text {
                                anchors.centerIn: parent
                                text: "󰀻"
                                color: settingsWin.fixedOnText
                                font.family: settingsWin.host.iconFont
                                font.pixelSize: 17
                            }
                        }

                        ColumnLayout {
                            spacing: 0

                            Text {
                                text: "Dynamic Island"
                                color: settingsWin.fixedText
                                font.family: settingsWin.host.uiFont
                                font.weight: Font.Bold
                                font.pixelSize: 15
                            }

                            Text {
                                text: "quickshell"
                                color: settingsWin.fixedMuted
                                font.family: settingsWin.host.uiFont
                                font.pixelSize: 12
                            }
                        }
                    }

                    // A single pill that slides between items, rather than each
                    // item fading its own background in and out — the motion
                    // reads as "the selection moved" instead of "two rows
                    // changed colour", which is the more legible story for what
                    // actually happened.
                    Item {
                        id: navWrap
                        Layout.fillWidth: true
                        implicitHeight: navColumn.implicitHeight

                        Rectangle {
                            id: navIndicator
                            width: navWrap.width
                            height: 42
                            radius: 12
                            color: settingsWin.fixedOn
                            y: settingsWin.sectionIndex * (42 + navColumn.spacing)
                            Behavior on y {
                                NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                            }
                        }

                        Column {
                            id: navColumn
                            width: navWrap.width
                            spacing: 6

                            Repeater {
                                model: settingsWin.navOrder

                                NavItem {
                                    required property string modelData
                                    width: navColumn.width
                                    icon: {
                                        switch (modelData) {
                                        case "clock": return "󰥔"
                                        case "timetools": return "󰔛"
                                        case "media": return "󰎈"
                                        case "calls": return "󰏶"
                                        case "notifications": return "󰂚"
                                        case "panels": return "󰕾"
                                        case "general": return "󰖟"
                                        default: return "󰸌"
                                        }
                                    }
                                    label: {
                                        switch (modelData) {
                                        case "clock": return settingsWin.i18n.secClock
                                        case "timetools": return settingsWin.i18n.secTimeTools
                                        case "media": return settingsWin.i18n.secMedia
                                        case "calls": return settingsWin.i18n.secCalls
                                        case "notifications": return settingsWin.i18n.secNotifications
                                        case "panels": return settingsWin.i18n.secPanels
                                        case "general": return settingsWin.i18n.secGeneral
                                        default: return settingsWin.i18n.secAppearance
                                        }
                                    }
                                    active: settingsWin.section === modelData
                                    onTriggered: settingsWin.section = modelData
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.bottomMargin: 10
                        color: settingsWin.fixedLine
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        text: "~/.config/quickshell"
                        color: settingsWin.fixedMuted
                        font.family: settingsWin.host.uiFont
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                }
            }

            // --------------------------------------------------- content pane
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: paneHeader
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    anchors.topMargin: 24
                    anchors.leftMargin: 28
                    anchors.rightMargin: 24
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            Layout.fillWidth: true
                            text: {
                                switch (settingsWin.section) {
                                case "clock": return settingsWin.i18n.secClock
                                case "timetools": return settingsWin.i18n.secTimeTools
                                case "media": return settingsWin.i18n.secMedia
                                case "calls": return settingsWin.i18n.secCalls
                                case "notifications": return settingsWin.i18n.secNotifications
                                case "panels": return settingsWin.i18n.secPanels
                                case "general": return settingsWin.i18n.secGeneral
                                default: return settingsWin.i18n.secAppearance
                                }
                            }
                            color: settingsWin.fixedText
                            font.family: settingsWin.host.uiFont
                            font.weight: Font.Bold
                            font.pixelSize: 23
                        }

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 18
                            scale: closeHit.containsMouse ? 1.08 : 1
                            color: closeHit.containsMouse ? settingsWin.fixedStatusAlert
                                                          : settingsWin.fixedChip
                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                color: closeHit.containsMouse ? "#ffffff" : settingsWin.fixedSubtext
                                font.family: settingsWin.host.iconFont
                                font.pixelSize: 15
                                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                id: closeHit
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: settingsWin.dismissRequested()
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            switch (settingsWin.section) {
                            case "clock": return settingsWin.i18n.secClockSub
                            case "timetools": return settingsWin.i18n.secTimeToolsSub
                            case "media": return settingsWin.i18n.secMediaSub
                            case "calls": return settingsWin.i18n.secCallsSub
                            case "notifications": return settingsWin.i18n.secNotificationsSub
                            case "panels": return settingsWin.i18n.secPanelsSub
                            case "general": return settingsWin.i18n.secGeneralSub
                            default: return settingsWin.i18n.secAppearanceSub
                            }
                        }
                        color: settingsWin.fixedMuted
                        font.family: settingsWin.host.uiFont
                        font.pixelSize: 14
                    }
                }

                // A Flickable rather than a fixed column: the clock section is
                // taller than the window on short screens, and a settings pane
                // that silently clips its last row is worse than one that
                // scrolls.
                Flickable {
                    id: flick
                    anchors {
                        top: paneHeader.bottom
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    anchors.topMargin: 20
                    anchors.leftMargin: 28
                    anchors.rightMargin: 24
                    anchors.bottomMargin: 24
                    clip: true
                    contentHeight: sections.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    // Switching sections keeps the previous section's scroll
                    // offset, which lands you mid-way down a shorter section
                    // looking at nothing. Every section starts at its top.
                    Connections {
                        target: settingsWin
                        function onSectionChanged() {
                            flick.contentY = 0
                            sectionEnter.restart()
                        }
                    }
                    ScrollBar.vertical: ScrollBar {
                        policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    // A quick fade-and-rise for the new section's content, so
                    // switching sections reads as the pane refreshing rather
                    // than as a hard cut to different text.
                    SequentialAnimation {
                        id: sectionEnter
                        PropertyAction { target: sections; property: "opacity"; value: 0 }
                        PropertyAction { target: sections; property: "y"; value: 10 }
                        ParallelAnimation {
                            NumberAnimation { target: sections; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
                            NumberAnimation { target: sections; property: "y"; to: 0; duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    ColumnLayout {
                        id: sections
                        width: flick.width
                        spacing: 14

                        // ------------------------------------------ appearance
                        SettingGroup {
                            visible: settingsWin.section === "appearance"
                            label: settingsWin.i18n.grpTheme
                            // Names the active theme right in the note, so
                            // confirming a pick doesn't mean scanning the
                            // grid for whichever card has the checkmark.
                            note: settingsWin.i18n.grpThemeNote + " — " + settingsWin.themeDisplayName(settingsWin.host.themeName)

                            ThemePicker { Layout.fillWidth: true }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "appearance"
                            label: settingsWin.i18n.grpBorders
                            note: settingsWin.i18n.grpBordersNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰺕"
                                label: settingsWin.i18n.setBorders
                                preview: Component { PvBorders {} }
                                detail: settingsWin.i18n.setBordersDesc
                                checked: settingsWin.host.showBorders
                                onToggled: {
                                    settingsWin.host.showBorders = !settingsWin.host.showBorders
                                    settingsWin.host.saveSettings()
                                }
                            }

                        }

                        SettingGroup {
                            visible: settingsWin.section === "appearance"
                            label: settingsWin.i18n.grpMountStyle
                            note: settingsWin.i18n.grpMountStyleNote

                            MountStylePicker { Layout.fillWidth: true }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "appearance"
                            label: settingsWin.i18n.grpMediaSurface
                            note: settingsWin.i18n.grpMediaSurfaceNote

                            SurfacePicker { Layout.fillWidth: true }
                        }

                        // ----------------------------------------------- clock
                        SettingGroup {
                            visible: settingsWin.section === "clock"
                            label: settingsWin.i18n.grpStyle
                            note: settingsWin.i18n.grpStyleNote

                            ClockStylePicker { Layout.fillWidth: true }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "clock"
                            label: settingsWin.i18n.grpFormat
                            note: settingsWin.i18n.grpFormatNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰥔"
                                label: settingsWin.i18n.setClock24h
                                preview: Component { PvClock24 {} }
                                detail: settingsWin.i18n.setClock24hDesc
                                checked: settingsWin.host.clock24Hour
                                onToggled: {
                                    settingsWin.host.clock24Hour = !settingsWin.host.clock24Hour
                                    settingsWin.revealClock()
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰔛"
                                label: settingsWin.i18n.setSeconds
                                preview: Component { PvClockSeconds {} }
                                detail: settingsWin.i18n.setSecondsDesc
                                checked: settingsWin.host.clockSeconds
                                onToggled: {
                                    settingsWin.host.clockSeconds = !settingsWin.host.clockSeconds
                                    settingsWin.revealClock()
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰃭"
                                label: settingsWin.i18n.setDateLine
                                preview: Component { PvClockDate {} }
                                detail: settingsWin.i18n.setDateLineDesc
                                checked: settingsWin.host.clockDate
                                onToggled: {
                                    settingsWin.host.clockDate = !settingsWin.host.clockDate
                                    settingsWin.revealClock()
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰕰"
                                label: settingsWin.i18n.setClockGrid
                                preview: Component { PvClockGrid {} }
                                detail: settingsWin.i18n.setClockGridDesc
                                // The dormant matrix only exists in pixel mode;
                                // offering it elsewhere would be a dead switch.
                                enabled: settingsWin.host.clockStyle === "pixel"
                                checked: settingsWin.host.clockGrid
                                onToggled: {
                                    settingsWin.host.clockGrid = !settingsWin.host.clockGrid
                                    settingsWin.revealClock()
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        // ----------------------------------------------- calls
                        SettingGroup {
                            visible: settingsWin.section === "calls"
                            label: settingsWin.i18n.grpBehaviour
                            note: settingsWin.i18n.grpBehaviourNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰏶"
                                label: settingsWin.i18n.setCallAutoPopup
                                preview: Component { PvCallPopup {} }
                                detail: settingsWin.i18n.setCallAutoPopupDesc
                                checked: settingsWin.host.callAutoPopup
                                onToggled: {
                                    settingsWin.host.callAutoPopup = !settingsWin.host.callAutoPopup
                                    settingsWin.host.saveSettings()
                                }
                            }

                            ChoiceRow {
                                Layout.fillWidth: true
                                icon: "󰔛"
                                label: settingsWin.i18n.setRingTimeout
                                detail: settingsWin.i18n.setRingTimeoutDesc
                                options: [settingsWin.i18n.seconds(15),
                                          settingsWin.i18n.seconds(35),
                                          settingsWin.i18n.seconds(60)]
                                values: [15, 35, 60]
                                current: settingsWin.host.callRingSeconds
                                onPicked: value => {
                                    settingsWin.host.callRingSeconds = value
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰝤"
                                label: settingsWin.i18n.setCallPulse
                                preview: Component { PvPulseRing {} }
                                detail: settingsWin.i18n.setCallPulseDesc
                                checked: settingsWin.host.callPulseRing
                                onToggled: {
                                    settingsWin.host.callPulseRing = !settingsWin.host.callPulseRing
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        // --------------------------------------- notifications
                        SettingGroup {
                            visible: settingsWin.section === "notifications"
                            label: settingsWin.i18n.grpTiming
                            note: settingsWin.i18n.grpTimingNote

                            ChoiceRow {
                                Layout.fillWidth: true
                                icon: "󰔛"
                                label: settingsWin.i18n.setNotifDuration
                                detail: settingsWin.i18n.setNotifDurationDesc
                                options: [settingsWin.i18n.seconds(3),
                                          settingsWin.i18n.seconds(5),
                                          settingsWin.i18n.seconds(8)]
                                values: [3, 5, 8]
                                current: settingsWin.host.notificationSeconds
                                onPicked: value => {
                                    settingsWin.host.notificationSeconds = value
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "notifications"
                            label: settingsWin.i18n.grpContent
                            note: settingsWin.i18n.grpContentNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰑚"
                                label: settingsWin.i18n.setInlineReply
                                preview: Component { PvReply {} }
                                detail: settingsWin.i18n.setInlineReplyDesc
                                checked: settingsWin.host.notificationInlineReply
                                onToggled: {
                                    settingsWin.host.notificationInlineReply = !settingsWin.host.notificationInlineReply
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰋩"
                                label: settingsWin.i18n.setAppIcon
                                preview: Component { PvAppIcon {} }
                                detail: settingsWin.i18n.setAppIconDesc
                                checked: settingsWin.host.notificationAppIcon
                                onToggled: {
                                    settingsWin.host.notificationAppIcon = !settingsWin.host.notificationAppIcon
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        // ------------------------------------------- time tools
                        SettingGroup {
                            visible: settingsWin.section === "timetools"
                            label: settingsWin.i18n.grpTimePresets
                            note: settingsWin.i18n.grpTimePresetsNote

                            ChoiceRow {
                                Layout.fillWidth: true
                                icon: "󰔛"
                                label: settingsWin.i18n.setTimerDefault
                                detail: settingsWin.i18n.setTimerDefaultDesc
                                options: ["1 min", "3 min", "5 min", "10 min", "15 min", "25 min"]
                                values: [1, 3, 5, 10, 15, 25]
                                current: settingsWin.host.timerDefaultMinutes
                                onPicked: value => {
                                    settingsWin.host.timerDefaultMinutes = value
                                    settingsWin.host.saveSettings()
                                }
                            }

                            ChoiceRow {
                                Layout.fillWidth: true
                                icon: "󰄉"
                                label: settingsWin.i18n.setFocusDefault
                                detail: settingsWin.i18n.setFocusDefaultDesc
                                options: ["15 min", "20 min", "25 min", "30 min", "45 min", "60 min"]
                                values: [15, 20, 25, 30, 45, 60]
                                current: settingsWin.host.focusDefaultMinutes
                                onPicked: value => {
                                    settingsWin.host.focusDefaultMinutes = value
                                    settingsWin.host.saveSettings()
                                }
                            }

                            ChoiceRow {
                                Layout.fillWidth: true
                                icon: "󰅶"
                                label: settingsWin.i18n.setBreakDefault
                                detail: settingsWin.i18n.setBreakDefaultDesc
                                options: ["3 min", "5 min", "10 min", "15 min"]
                                values: [3, 5, 10, 15]
                                current: settingsWin.host.breakDefaultMinutes
                                onPicked: value => {
                                    settingsWin.host.breakDefaultMinutes = value
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "timetools"
                            label: settingsWin.i18n.grpTimeChime
                            note: settingsWin.i18n.grpTimeChimeNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰎈"
                                label: settingsWin.i18n.setChime
                                detail: settingsWin.i18n.setChimeDesc
                                checked: settingsWin.host.timeChimeEnabled
                                onToggled: {
                                    settingsWin.host.timeChimeEnabled = !settingsWin.host.timeChimeEnabled
                                    settingsWin.host.saveSettings()
                                }
                            }

                            // Not a ChoiceRow: eleven options laid out in one
                            // row ran past the right edge of the window, so
                            // the last four sounds could not be reached at
                            // all. This wraps, and picking one plays it —
                            // choosing a sound you cannot hear is not a
                            // choice.
                            ChimePicker { Layout.fillWidth: true }

                            ChoiceRow {
                                Layout.fillWidth: true
                                icon: "󰕾"
                                label: settingsWin.i18n.setChimeVolume
                                detail: settingsWin.i18n.setChimeVolumeDesc
                                options: [settingsWin.i18n.chimeVolSoft, settingsWin.i18n.chimeVolNormal, settingsWin.i18n.chimeVolLoud]
                                values: ["soft", "normal", "loud"]
                                current: settingsWin.host.timeChimeVolume
                                onPicked: value => {
                                    settingsWin.host.timeChimeVolume = value
                                    settingsWin.host.saveSettings()
                                }
                            }

                            Rectangle {
                                id: testChimeBtn
                                Layout.fillWidth: true
                                implicitHeight: 52
                                radius: 14
                                // There's no completion signal from the detached
                                // player process, so the button times itself out
                                // using each bundled sound's own length (measured
                                // with soxi) rather than guessing one duration
                                // for every clip — timesup.wav alone is 10s
                                // against ~0.3-1.1s for the rest.
                                property bool playing: false
                                color: testBtnHit.containsMouse ? settingsWin.fixedChipHover : settingsWin.fixedChip
                                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                function chimeDurationMs(name) {
                                    switch (name) {
                                    case "timesup": return 10000
                                    case "chime1": return 490
                                    case "chime2": return 510
                                    case "chime3": return 700
                                    case "chime4": return 370
                                    case "chime5": return 900
                                    case "chime6": return 300
                                    case "chime7": return 1050
                                    case "chime8": return 460
                                    case "chime9": return 600
                                    case "chime10": return 340
                                    default: return 1200
                                    }
                                }

                                Timer {
                                    id: chimeResetTimer
                                    onTriggered: testChimeBtn.playing = false
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 12

                                    Text {
                                        text: "󰓃"
                                        color: "#3aa863"
                                        font.family: settingsWin.host.iconFont
                                        font.pixelSize: 18
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: settingsWin.i18n.testChime
                                        color: settingsWin.fixedText
                                        font.family: settingsWin.host.uiFont
                                        font.weight: Font.DemiBold
                                        font.pixelSize: 14
                                    }

                                    Rectangle {
                                        implicitWidth: playLabel.implicitWidth + 32
                                        implicitHeight: 30
                                        radius: 10
                                        color: testChimeBtn.playing ? settingsWin.fixedStatusAlert : settingsWin.fixedOn
                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                        Text {
                                            id: playLabel
                                            anchors.centerIn: parent
                                            text: testChimeBtn.playing
                                                  ? ("󰏤  " + (settingsWin.i18n.tr ? "Durdur" : "Stop"))
                                                  : ("󰐊  " + (settingsWin.i18n.tr ? "Çal" : "Play"))
                                            color: testChimeBtn.playing ? "#ffffff" : settingsWin.fixedOnText
                                            font.family: settingsWin.host.uiFont
                                            font.weight: Font.Bold
                                            font.pixelSize: 12
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: testBtnHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (testChimeBtn.playing) {
                                            settingsWin.host.run(["chime-stop"])
                                            chimeResetTimer.stop()
                                            testChimeBtn.playing = false
                                        } else {
                                            settingsWin.host.run(["chime", settingsWin.host.chimeSound])
                                            testChimeBtn.playing = true
                                            chimeResetTimer.interval = testChimeBtn.chimeDurationMs(settingsWin.host.chimeSound)
                                            chimeResetTimer.restart()
                                        }
                                    }
                                }
                            }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "timetools"
                            label: settingsWin.i18n.grpTimeBehaviour
                            note: settingsWin.i18n.grpTimeBehaviourNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰔚"
                                label: settingsWin.i18n.setAutoStartBreak
                                detail: settingsWin.i18n.setAutoStartBreakDesc
                                checked: settingsWin.host.autoStartBreak
                                onToggled: {
                                    settingsWin.host.autoStartBreak = !settingsWin.host.autoStartBreak
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        // ----------------------------------------------- media (player)
                        SettingGroup {
                            visible: settingsWin.section === "media"
                            label: settingsWin.i18n.grpPlayerVisuals
                            note: settingsWin.i18n.grpPlayerVisualsNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰋩"
                                label: settingsWin.i18n.setAlbumArt
                                preview: Component { PvAlbumArt {} }
                                detail: settingsWin.i18n.setAlbumArtDesc
                                checked: settingsWin.host.mediaAlbumArtEnabled
                                onToggled: {
                                    settingsWin.host.mediaAlbumArtEnabled = !settingsWin.host.mediaAlbumArtEnabled
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰨖"
                                label: settingsWin.i18n.setLyrics
                                preview: Component { PvLyrics {} }
                                detail: settingsWin.i18n.setLyricsDesc
                                checked: settingsWin.host.mediaLyricsEnabled
                                onToggled: {
                                    settingsWin.host.mediaLyricsEnabled = !settingsWin.host.mediaLyricsEnabled
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰋅"
                                label: settingsWin.i18n.setSpectrum
                                preview: Component { PvSpectrum {} }
                                detail: settingsWin.i18n.setSpectrumDesc
                                checked: settingsWin.host.mediaSpectrumEnabled
                                onToggled: {
                                    settingsWin.host.mediaSpectrumEnabled = !settingsWin.host.mediaSpectrumEnabled
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰔟"
                                label: settingsWin.i18n.setProgressBar
                                preview: Component { PvProgressBar {} }
                                detail: settingsWin.i18n.setProgressBarDesc
                                checked: settingsWin.host.mediaProgressBar
                                onToggled: {
                                    settingsWin.host.mediaProgressBar = !settingsWin.host.mediaProgressBar
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "media"
                            label: settingsWin.i18n.grpPlayerBehavior
                            note: settingsWin.i18n.grpPlayerBehaviorNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰐊"
                                label: settingsWin.i18n.setCompactControls
                                preview: Component { PvMiniPlayer {} }
                                detail: settingsWin.i18n.setCompactControlsDesc
                                checked: settingsWin.host.compactMediaControls
                                onToggled: {
                                    settingsWin.host.compactMediaControls = !settingsWin.host.compactMediaControls
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰍜"
                                label: settingsWin.i18n.setAutoExpandTrack
                                detail: settingsWin.i18n.setAutoExpandTrackDesc
                                checked: settingsWin.host.mediaAutoExpandTrack
                                onToggled: {
                                    settingsWin.host.mediaAutoExpandTrack = !settingsWin.host.mediaAutoExpandTrack
                                    settingsWin.host.saveSettings()
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                text: settingsWin.i18n.setMediaSurfaceDesc
                                color: settingsWin.fixedMuted
                                font.family: settingsWin.host.uiFont
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.preferredHeight: contentHeight
                            }

                            SurfacePicker { Layout.fillWidth: true }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "media"
                            label: settingsWin.i18n.grpPlayerEffects
                            note: settingsWin.i18n.grpPlayerEffectsNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰌵"
                                label: settingsWin.i18n.setColorGlow
                                detail: settingsWin.i18n.setColorGlowDesc
                                checked: settingsWin.host.mediaColorGlow
                                onToggled: {
                                    settingsWin.host.mediaColorGlow = !settingsWin.host.mediaColorGlow
                                    settingsWin.host.saveSettings()
                                }
                            }

                            AnimationStylePicker { Layout.fillWidth: true }

                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                text: settingsWin.i18n.setAnimationIntensityDesc
                                color: settingsWin.fixedMuted
                                font.family: settingsWin.host.uiFont
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.preferredHeight: contentHeight
                            }

                            IntensityPicker { Layout.fillWidth: true }
                        }

                        // Each panel that opens from the status strip gets its
                        // own group: the toggle that shows the chip sits with
                        // the options that change what the chip opens, instead
                        // of the toggles piling up in one list and the layouts
                        // living a section away under Appearance.
                        SettingGroup {
                            visible: settingsWin.section === "panels"
                            label: settingsWin.i18n.grpAppVolume
                            note: settingsWin.i18n.grpAppVolumeNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰕾"
                                label: settingsWin.i18n.setAppVolume
                                preview: Component { PvAppVolume {} }
                                detail: settingsWin.i18n.setAppVolumeDesc
                                checked: settingsWin.host.appVolumeEnabled
                                onToggled: {
                                    settingsWin.host.appVolumeEnabled = !settingsWin.host.appVolumeEnabled
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "panels"
                            label: settingsWin.i18n.grpPlayerSwitcher
                            note: settingsWin.i18n.grpPlayerSwitcherNote

                            PlayerSwitcherPicker { Layout.fillWidth: true }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "panels"
                            label: settingsWin.i18n.grpQueue
                            note: settingsWin.i18n.grpQueueNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰐑"
                                label: settingsWin.i18n.setQueue
                                preview: Component { PvQueue {} }
                                detail: settingsWin.i18n.setQueueDesc
                                checked: settingsWin.host.queueEnabled
                                onToggled: {
                                    settingsWin.host.queueEnabled = !settingsWin.host.queueEnabled
                                    settingsWin.host.saveSettings()
                                }
                            }

                            QueueStylePicker {
                                Layout.fillWidth: true
                                dimmed: !settingsWin.host.queueEnabled
                            }
                        }

                        // --------------------------------------------- general
                        SettingGroup {
                            visible: settingsWin.section === "general"
                            label: settingsWin.i18n.grpLanguage
                            note: settingsWin.i18n.grpLanguageNote

                            ChoiceRow {
                                Layout.fillWidth: true
                                icon: "󰖟"
                                label: settingsWin.i18n.setLanguage
                                detail: settingsWin.i18n.setLanguageDesc
                                options: ["Türkçe", "English"]
                                values: ["tr", "en"]
                                current: settingsWin.host.lang
                                // Language has its own file and its own setter,
                                // so it deliberately does not go through
                                // saveSettings() like the rest.
                                onPicked: value => settingsWin.host.setLanguage(value)
                            }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "general"
                            label: settingsWin.i18n.grpWindow
                            note: settingsWin.i18n.grpWindowNote

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰇀"
                                label: settingsWin.i18n.setHoverOpen
                                preview: Component { PvHover {} }
                                detail: settingsWin.i18n.setHoverOpenDesc
                                checked: settingsWin.host.hoverToOpen
                                onToggled: {
                                    settingsWin.host.hoverToOpen = !settingsWin.host.hoverToOpen
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰐃"
                                label: settingsWin.i18n.setPinned
                                detail: settingsWin.i18n.setPinnedDesc
                                checked: settingsWin.host.lockedOpen
                                onToggled: settingsWin.host.lockedOpen = !settingsWin.host.lockedOpen
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ components
    // The active fill itself now lives in the shared navIndicator pill behind
    // the whole column, so this only ever paints a hover chip — never a
    // second, independently-animated background racing the indicator to the
    // same answer.
    component NavItem: Rectangle {
        id: nav

        property string icon: ""
        property string label: ""
        property bool active: false

        signal triggered()

        implicitHeight: 42
        radius: 12
        color: (!nav.active && navHit.containsMouse) ? settingsWin.fixedChipHover : "transparent"
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 11

            Text {
                text: nav.icon
                color: nav.active ? settingsWin.fixedOnText : settingsWin.fixedSubtext
                font.family: settingsWin.host.iconFont
                font.pixelSize: 16
                scale: nav.active ? 1.05 : 1
                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
            }

            Text {
                Layout.fillWidth: true
                text: nav.label
                color: nav.active ? settingsWin.fixedOnText : settingsWin.fixedSubtext
                font.family: settingsWin.host.uiFont
                font.weight: nav.active ? Font.DemiBold : Font.Normal
                font.pixelSize: 15
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
            }
        }

        MouseArea {
            id: navHit
            anchors.fill: parent
            hoverEnabled: true
            onClicked: nav.triggered()
        }
    }

    component SettingGroup: ColumnLayout {
        id: group

        property string label: ""
        // One line under the heading saying what this group actually changes and
        // where it shows up on the island. Without it a section can only be
        // understood by toggling things and watching what happens.
        property string note: ""

        // Layouts skip invisible children outright, so hiding a group is all
        // it takes for the six sections to share one column without a
        // StackLayout and without leaving a gap behind.
        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: group.note === "" ? 1 : 0
            text: group.label
            color: settingsWin.fixedMuted
            font.family: settingsWin.host.uiFont
            font.weight: Font.Bold
            font.pixelSize: 12
            font.letterSpacing: 1.2
            font.capitalization: Font.AllUppercase
        }

        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 2
            // A wrapping Text reports the height of a *single* line as its
            // implicitHeight, so a layout measuring it that way under-counts
            // every note that wraps — and the scroll area sizes itself from
            // that total, which would leave the last group unreachable on a
            // narrow window. contentHeight is the height actually drawn.
            Layout.preferredHeight: contentHeight
            visible: group.note !== ""
            text: group.note
            color: settingsWin.fixedMuted
            font.family: settingsWin.host.uiFont
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
    }

    // One setting: an icon tile, its label and description, and an on/off pill.
    // The whole row is clickable, not just the pill, so it isn't a tiny target.
    component SettingRow: Rectangle {
        id: row

        property string icon: ""
        property string label: ""
        property string detail: ""
        property bool checked: false
        // `locked` is for settings that are stated rather than offered — the
        // player exemption is a rule of the design, shown so it isn't a
        // mystery, not a switch.
        property bool locked: false
        // An optional miniature of what the setting produces, drawn between the
        // description and the pill. A row's words can only name a thing; this
        // shows it, which is the difference between reading "spectrum bars" and
        // knowing whether you want them.
        property Component preview: null

        signal toggled()

        implicitHeight: 66
        radius: 16
        scale: (rowHit.containsMouse && enabled && !locked) ? 1.006 : 1
        color: (rowHit.containsMouse && enabled && !locked) ? settingsWin.fixedChipHover
                                                            : settingsWin.fixedChip
        opacity: enabled ? 1 : 0.45
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 11
                color: settingsWin.fixedSurfaceAlt

                Text {
                    anchors.centerIn: parent
                    text: row.icon
                    color: settingsWin.fixedSubtext
                    font.family: settingsWin.host.iconFont
                    font.pixelSize: 16
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: row.label
                    color: settingsWin.fixedText
                    font.family: settingsWin.host.uiFont
                    font.pixelSize: 15
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: row.detail !== ""
                    text: row.detail
                    color: settingsWin.fixedMuted
                    font.family: settingsWin.host.uiFont
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
            }

            // Fades with the setting rather than disappearing: seeing the thing
            // you just switched off is how you confirm you switched off the
            // right one.
            Loader {
                // Wide enough for the roomiest miniature (a clock carrying
                // hours, minutes and seconds); everything else centres in it.
                Layout.preferredWidth: 100
                Layout.preferredHeight: 38
                visible: row.preview !== null
                active: row.preview !== null
                sourceComponent: row.preview
                opacity: row.checked ? 1 : 0.32
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            TogglePill {
                on: row.checked
                dimmed: row.locked
            }
        }

        MouseArea {
            id: rowHit
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.enabled && !row.locked
            onClicked: row.toggled()
        }
    }

    // A real sliding switch rather than a text pill: on/off reads from the
    // thumb's position and the track's fill at a glance, the way every other
    // toggle on the desktop already works, instead of asking the eye to read
    // a 10px word each time.
    component TogglePill: Rectangle {
        id: pill

        property bool on: false
        property bool dimmed: false

        implicitWidth: 48
        implicitHeight: 28
        radius: height / 2
        opacity: pill.dimmed ? 0.7 : 1
        color: pill.on ? settingsWin.fixedOn : settingsWin.fixedTrack
        border.width: pill.on ? 0 : 1
        border.color: settingsWin.fixedLineStrong
        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Rectangle {
            id: thumb
            width: 22
            height: 22
            radius: 11
            anchors.verticalCenter: parent.verticalCenter
            x: pill.on ? parent.width - width - 3 : 3
            color: pill.on ? settingsWin.fixedOnText : settingsWin.fixedSubtext

            Behavior on x {
                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
            }
            Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
    }

    // A row whose control is a segmented picker rather than a pill, for the
    // settings that have three answers instead of two.
    component ChoiceRow: Rectangle {
        id: choice

        property string icon: ""
        property string label: ""
        property string detail: ""
        property var options: []
        property var values: []
        property var current: null
        readonly property int activeIndex: choice.values.indexOf(choice.current)

        signal picked(var value)

        implicitHeight: 66
        radius: 16
        color: settingsWin.fixedChip

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 11
                color: settingsWin.fixedSurfaceAlt

                Text {
                    anchors.centerIn: parent
                    text: choice.icon
                    color: settingsWin.fixedSubtext
                    font.family: settingsWin.host.iconFont
                    font.pixelSize: 16
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: choice.label
                    color: settingsWin.fixedText
                    font.family: settingsWin.host.uiFont
                    font.pixelSize: 15
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: choice.detail !== ""
                    text: choice.detail
                    color: settingsWin.fixedMuted
                    font.family: settingsWin.host.uiFont
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredWidth: segHost.implicitWidth + 6
                Layout.preferredHeight: 38
                radius: 13
                color: settingsWin.fixedSurfaceAlt

                // One highlight that slides to the picked option, instead of
                // each segment flipping its own fill — the same "selection
                // moved" language as the sidebar's nav indicator.
                Item {
                    id: segHost
                    anchors.centerIn: parent
                    implicitWidth: segRow.implicitWidth
                    width: implicitWidth
                    height: 32

                    Rectangle {
                        id: segHighlight
                        visible: choice.activeIndex >= 0 && segRepeater.count > choice.activeIndex
                        radius: 10
                        height: 32
                        y: 0
                        color: settingsWin.fixedOn
                        x: segHighlight.visible ? segRepeater.itemAt(choice.activeIndex).x : 0
                        width: segHighlight.visible ? segRepeater.itemAt(choice.activeIndex).width : 0

                        Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    }

                    Row {
                        id: segRow
                        spacing: 4

                        Repeater {
                            id: segRepeater
                            model: choice.options.length

                            Rectangle {
                                id: seg
                                required property int index

                                readonly property bool active: choice.values[seg.index] === choice.current

                                implicitWidth: segLabel.implicitWidth + 20
                                implicitHeight: 32
                                radius: 10
                                color: (!seg.active && segHit.containsMouse) ? settingsWin.fixedChipHover : "transparent"
                                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                Text {
                                    id: segLabel
                                    anchors.centerIn: parent
                                    text: choice.options[seg.index]
                                    color: seg.active ? settingsWin.fixedOnText : settingsWin.fixedMuted
                                    font.family: settingsWin.host.uiFont
                                    font.weight: Font.DemiBold
                                    font.pixelSize: 13
                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                }

                                MouseArea {
                                    id: segHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: choice.picked(choice.values[seg.index])
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // The eleven bundled chimes, wrapped across as many rows as they need.
    // Picking one plays it immediately: the difference between chime3 and
    // chime7 is not something a label can carry.
    component ChimePicker: Rectangle {
        readonly property var sounds: ["timesup", "chime1", "chime2", "chime3", "chime4", "chime5",
                                       "chime6", "chime7", "chime8", "chime9", "chime10"]

        implicitHeight: chimeFlow.implicitHeight + chimeHead.implicitHeight + 34
        radius: 16
        color: settingsWin.fixedChip

        RowLayout {
            id: chimeHead
            anchors { top: parent.top; left: parent.left; right: parent.right }
            anchors.margins: 14
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 11
                color: settingsWin.fixedSurfaceAlt

                Text {
                    anchors.centerIn: parent
                    text: "󰕩"
                    color: settingsWin.fixedSubtext
                    font.family: settingsWin.host.iconFont
                    font.pixelSize: 16
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: settingsWin.i18n.setChimeSound
                    color: settingsWin.fixedText
                    font.family: settingsWin.host.uiFont
                    font.pixelSize: 15
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: settingsWin.i18n.setChimeSoundDesc
                    color: settingsWin.fixedMuted
                    font.family: settingsWin.host.uiFont
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
            }
        }

        Flow {
            id: chimeFlow
            anchors { top: chimeHead.bottom; left: parent.left; right: parent.right }
            anchors.topMargin: 12
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 7

            Repeater {
                model: parent.parent.sounds

                Rectangle {
                    id: chimeChip
                    required property string modelData

                    readonly property bool active: settingsWin.host.chimeSound === chimeChip.modelData
                    readonly property string displayLabel: chimeChip.modelData === "timesup"
                        ? settingsWin.i18n.chimeDefault
                        : chimeChip.modelData.replace("chime", "")

                    implicitWidth: Math.max(46, chimeLabel.implicitWidth + 22)
                    implicitHeight: 34
                    radius: 11
                    color: chimeChip.active ? settingsWin.fixedOn
                                            : (chimeHit.containsMouse ? settingsWin.fixedChipHover
                                                                      : settingsWin.fixedSurfaceAlt)
                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    scale: chimeHit.containsMouse && !chimeChip.active ? 1.05 : 1
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    Text {
                        id: chimeLabel
                        anchors.centerIn: parent
                        text: chimeChip.displayLabel
                        color: chimeChip.active ? settingsWin.fixedOnText : settingsWin.fixedSubtext
                        font.family: settingsWin.host.uiFont
                        font.weight: Font.DemiBold
                        font.pixelSize: 13
                        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: chimeHit
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            settingsWin.host.chimeSound = chimeChip.modelData
                            settingsWin.host.saveSettings()
                            settingsWin.host.run(["chime-stop"])
                            settingsWin.host.run(["chime", chimeChip.modelData])
                        }
                    }
                }
            }
        }
    }

    // A grid of small island mockups rather than flat colour chips: what
    // sells a theme is the accent against the surface, not the surface
    // alone, so each tile draws a shrunken pill in the theme's own fill,
    // line and accent colours, washes its own card in a sliver of that same
    // accent, and settles in with a staggered entrance the first time the
    // group is shown — gold, amber and red share a near-identical dark base,
    // and it's the accent that has to do all the telling-apart.
    component ThemePicker: Rectangle {
        implicitHeight: swatchGrid.implicitHeight + 24
        radius: 16
        color: settingsWin.fixedChip
        clip: true

        GridLayout {
            id: swatchGrid
            anchors.fill: parent
            anchors.margins: 12
            columns: 4
            rowSpacing: 10
            columnSpacing: 10

            Repeater {
                // Reads the same order the theme cycler and settings.json
                // validation use, so a new theme only ever needs adding in
                // one place (DynamicIsland.qml's themePalettes) to show up
                // here too.
                model: settingsWin.host.themeOrder

                // The entrance animation lives on this outer cell rather than
                // on the swatch itself: an imperative animation that targets
                // a property severs any declarative binding on it for good,
                // and the swatch below needs its own `scale` binding to stay
                // alive for hover feedback long after the cell has settled.
                Item {
                    id: cell
                    required property string modelData
                    required property int index

                    readonly property bool active: settingsWin.host.themeName === cell.modelData
                    readonly property var pal: settingsWin.host.themePalettes[cell.modelData]
                    readonly property string displayLabel: settingsWin.themeDisplayName(cell.modelData)

                    Layout.fillWidth: true
                    Layout.preferredHeight: 104

                    opacity: 0
                    scale: 0.88
                    Component.onCompleted: cellEnter.start()

                    SequentialAnimation {
                        id: cellEnter
                        PauseAnimation { duration: cell.index * 40 }
                        ParallelAnimation {
                            NumberAnimation { target: cell; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                            NumberAnimation { target: cell; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                        }
                    }

                    Rectangle {
                        id: swatch
                        anchors.fill: parent
                        radius: 14
                        scale: swatchHit.containsMouse ? 1.025 : 1
                        // Tinted by the theme's own accent rather than a
                        // neutral chip colour, so every card carries a hint
                        // of its identity even before it's picked.
                        color: Qt.rgba(cell.pal.on.r, cell.pal.on.g, cell.pal.on.b,
                                       cell.active ? 0.14 : (swatchHit.containsMouse ? 0.09 : 0.05))
                        border.width: cell.active ? 2 : 1
                        border.color: cell.active ? cell.pal.on : "transparent"
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        // A soft ring of the theme's own accent behind the
                        // active tile — the same "this one" language as the
                        // sidebar's sliding indicator, in the colour that's
                        // actually being picked rather than a neutral glow.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -5
                            radius: parent.radius + 5
                            color: "transparent"
                            border.width: 8
                            border.color: cell.pal.on
                            opacity: cell.active ? 0.16 : 0
                            z: -1
                            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            // A miniature of the real island — its fill
                            // graded toward its own surface, its hairline,
                            // and a glowing dot in the accent colour — rather
                            // than a flat colour bar, so the accent that
                            // defines a theme like Gold or Red is what the
                            // eye lands on.
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: 32
                                    radius: height / 2
                                    border.width: 1
                                    border.color: cell.pal.lineStrong
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: cell.pal.islandFill }
                                        GradientStop { position: 1.0; color: cell.pal.surfaceAlt }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Item {
                                            Layout.preferredWidth: 14
                                            Layout.preferredHeight: 14

                                            // The active theme's dot breathes
                                            // gently, on the same shared phase
                                            // the call-pulse preview uses —
                                            // one more "this one is live"
                                            // signal, at zero extra timer cost.
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 14; height: 14; radius: 7
                                                color: cell.pal.on
                                                opacity: cell.active
                                                         ? 0.3 + Math.abs(Math.sin(settingsWin.host.visualPhase)) * 0.3
                                                         : 0.35
                                            }
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 8; height: 8; radius: 4
                                                color: cell.pal.on
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 22
                                            Layout.preferredHeight: 4
                                            radius: 2
                                            color: cell.pal.text
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 13
                                            Layout.preferredHeight: 4
                                            radius: 2
                                            color: cell.pal.muted
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.displayLabel
                                color: cell.active ? settingsWin.fixedText
                                                   : settingsWin.fixedMuted
                                font.family: settingsWin.host.uiFont
                                font.weight: Font.DemiBold
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }
                        }

                        // A small check badge instead of relying on the
                        // border alone to say "this one" — legible even at a
                        // glance, and it pops in rather than appearing
                        // mid-frame.
                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            color: cell.pal.on
                            scale: cell.active ? 1 : 0
                            opacity: cell.active ? 1 : 0
                            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
                            Behavior on opacity { NumberAnimation { duration: 160 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰄬"
                                color: cell.pal.onText
                                font.family: settingsWin.host.iconFont
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: swatchHit
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: settingsWin.host.setTheme(cell.modelData)
                        }
                    }
                }
            }
        }
    }

    // Each option renders a live sample of the style it selects, using the
    // same PixelClock the island uses — so the preview is the real thing at a
    // smaller cell size, not an approximation of it.
    component ClockStylePicker: Rectangle {
        implicitHeight: 122
        radius: 16
        color: settingsWin.fixedChip

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Repeater {
                model: ["pixel", "segment", "plain"]

                Rectangle {
                    id: styleOpt
                    required property string modelData

                    readonly property bool active: settingsWin.host.clockStyle === styleOpt.modelData
                    readonly property string displayLabel: {
                        switch (styleOpt.modelData) {
                        case "segment": return settingsWin.i18n.clockStyleSegment
                        case "plain": return settingsWin.i18n.clockStylePlain
                        default: return settingsWin.i18n.clockStylePixel
                        }
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 11
                    scale: styleHit.containsMouse ? 1.03 : 1
                    color: settingsWin.fixedChipHover
                    border.width: 1
                    border.color: styleOpt.active ? settingsWin.fixedText : "transparent"
                    Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            PixelClock {
                                anchors.centerIn: parent
                                time: settingsWin.host.currentTime
                                lang: settingsWin.host.lang
                                hour24: settingsWin.host.clock24Hour
                                style: styleOpt.modelData
                                textFont: settingsWin.host.uiFont
                                showSeconds: false
                                showDate: false
                                cell: 3
                                gap: 1
                                color: settingsWin.fixedText
                                mutedColor: settingsWin.fixedMuted
                                gridColor: "transparent"
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: styleOpt.displayLabel
                            color: styleOpt.active ? settingsWin.fixedText
                                                   : settingsWin.fixedMuted
                            font.family: settingsWin.host.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: styleHit
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            settingsWin.host.clockStyle = styleOpt.modelData
                            settingsWin.revealClock()
                            settingsWin.host.saveSettings()
                        }
                    }
                }
            }
        }
    }

    // Each option draws a tiny "screen edge" with the actual mount geometry
    // in miniature (same corner-radius/flush logic the real island uses,
    // just at picker scale) rather than an icon standing in for it.
    component MountStylePicker: Rectangle {
        implicitHeight: 116
        radius: 16
        color: settingsWin.fixedChip

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Repeater {
                model: settingsWin.host.islandMountStyles

                Rectangle {
                    id: mountOpt
                    required property string modelData

                    readonly property bool active: settingsWin.host.islandMountStyle === mountOpt.modelData
                    readonly property string displayLabel: {
                        switch (mountOpt.modelData) {
                        case "soft-fused": return settingsWin.i18n.mountStyleSoftFused
                        case "notch": return settingsWin.i18n.mountStyleNotch
                        default: return settingsWin.i18n.mountStyleCapsule
                        }
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 11
                    scale: mountHit.containsMouse ? 1.03 : 1
                    color: settingsWin.fixedChipHover
                    border.width: 1
                    border.color: mountOpt.active ? settingsWin.fixedText : "transparent"
                    Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        // Miniature screen edge + island, geometry mirrors
                        // the real thing for this style.
                        Item {
                            id: screenSample
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            readonly property bool flush: mountOpt.modelData === "soft-fused" || mountOpt.modelData === "notch"
                            readonly property real topRadius: mountOpt.modelData === "soft-fused" ? 3
                                : (mountOpt.modelData === "notch" ? 0 : 9)

                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: -6
                                radius: 6
                                color: settingsWin.fixedSurfaceAlt
                            }

                            Item {
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 40
                                height: 9
                                visible: mountOpt.modelData === "notch"

                                Rectangle {
                                    anchors.left: parent.left
                                    width: 6; height: 6
                                    color: settingsWin.fixedSurfaceAlt
                                    bottomRightRadius: 6
                                }
                                Rectangle {
                                    anchors.right: parent.right
                                    width: 6; height: 6
                                    color: settingsWin.fixedSurfaceAlt
                                    bottomLeftRadius: 6
                                }
                            }

                            Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: screenSample.flush ? 0 : 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 40
                                height: 12
                                topLeftRadius: screenSample.topRadius
                                topRightRadius: screenSample.topRadius
                                bottomLeftRadius: 9
                                bottomRightRadius: 9
                                color: settingsWin.fixedText
                                opacity: 0.9
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: mountOpt.displayLabel
                            color: mountOpt.active ? settingsWin.fixedText
                                                   : settingsWin.fixedMuted
                            font.family: settingsWin.host.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: mountHit
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            settingsWin.host.islandMountStyle = mountOpt.modelData
                            settingsWin.host.saveSettings()
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- previews
    // Miniatures for SettingRow.preview. Every one draws on the same dark tile,
    // so a row reads as "this is the thing that shows up on the island", and
    // every one takes its colours from the theme tokens, so the previews follow
    // the palette exactly like the island does.
    component PreviewTile: Rectangle {
        default property alias tileContent: tileInner.data

        anchors.fill: parent
        radius: 8
        color: settingsWin.fixedSurfaceAlt
        clip: true

        Item {
            id: tileInner
            anchors.fill: parent
            anchors.margins: 5
        }
    }

    // The middle line is the one being sung — that highlight is the whole point
    // of synced lyrics, so it is what the miniature shows.
    component PvLyrics: PreviewTile {
        Column {
            anchors.centerIn: parent
            spacing: 3
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 32; height: 3; radius: 1
                color: settingsWin.fixedTrack
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 48; height: 4; radius: 2
                color: settingsWin.fixedOn
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 26; height: 3; radius: 1
                color: settingsWin.fixedTrack
            }
        }
    }

    component PvSpectrum: PreviewTile {
        Row {
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: 10
                Rectangle {
                    required property int index
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 4 + Math.abs(Math.sin(settingsWin.host.visualPhase + index * 0.7)) * 17
                    radius: 1
                    color: settingsWin.fixedOn
                }
            }
        }
    }

    component PvProgressBar: PreviewTile {
        Column {
            anchors.centerIn: parent
            spacing: 3
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 24
                Rectangle { width: 12; height: 3; radius: 1; color: settingsWin.fixedOn }
                Rectangle { width: 12; height: 3; radius: 1; color: settingsWin.fixedMuted }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 52; height: 4; radius: 2
                color: settingsWin.fixedSurfaceAlt
                Rectangle {
                    width: 30; height: 4; radius: 2
                    color: settingsWin.fixedOn
                }
            }
        }
    }

    component PvAlbumArt: PreviewTile {
        Row {
            anchors.centerIn: parent
            spacing: 5
            Rectangle {
                width: 22; height: 22; radius: 4
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#57657f" }
                    GradientStop { position: 1.0; color: "#7c4b39" }
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Rectangle { width: 28; height: 4; radius: 2; color: settingsWin.fixedOn }
                Rectangle { width: 18; height: 3; radius: 1; color: settingsWin.fixedTrack }
            }
        }
    }

    component PvMiniPlayer: PreviewTile {
        Rectangle {
            anchors.centerIn: parent
            width: 60; height: 19; radius: 10
            color: settingsWin.fixedChipHover

            Row {
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11; height: 11; radius: 3
                    color: settingsWin.fixedTrack
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 3; radius: 1
                    color: settingsWin.fixedOn
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 4
                    color: settingsWin.fixedOn
                }
            }
        }
    }

    component PvBorders: PreviewTile {
        Rectangle {
            anchors.centerIn: parent
            width: 54; height: 22; radius: 8
            color: "transparent"
            border.width: 1
            border.color: settingsWin.fixedText
        }
    }

    component PvAppVolume: PreviewTile {
        Column {
            anchors.centerIn: parent
            spacing: 5
            Repeater {
                model: 3
                Row {
                    required property int index
                    spacing: 5
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7; height: 7; radius: 3
                        color: settingsWin.fixedTrack
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: [40, 26, 33][index]; height: 4; radius: 2
                        color: settingsWin.fixedOn
                    }
                }
            }
        }
    }

    component PvQueue: PreviewTile {
        Column {
            anchors.centerIn: parent
            spacing: 5
            Repeater {
                model: 3
                Row {
                    required property int index
                    spacing: 5
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: 3; radius: 1
                        color: settingsWin.fixedMuted
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: [44, 34, 39][index]; height: 4; radius: 2
                        color: settingsWin.fixedOn
                    }
                }
            }
        }
    }

    component PvReply: PreviewTile {
        Column {
            anchors.centerIn: parent
            spacing: 4
            Rectangle { width: 44; height: 4; radius: 2; color: settingsWin.fixedOn }
            Rectangle {
                width: 54; height: 12; radius: 6
                color: "transparent"
                border.width: 1
                border.color: settingsWin.fixedMuted

                Rectangle {
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1; height: 6
                    color: settingsWin.fixedText
                }
            }
        }
    }

    component PvAppIcon: PreviewTile {
        Row {
            anchors.centerIn: parent
            spacing: 5
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 17; height: 17; radius: 5
                color: settingsWin.fixedOn
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Rectangle { width: 32; height: 4; radius: 2; color: settingsWin.fixedOn }
                Rectangle { width: 22; height: 3; radius: 1; color: settingsWin.fixedTrack }
            }
        }
    }

    // Answer and decline, in the colours the call card actually uses.
    component PvCallPopup: PreviewTile {
        Row {
            anchors.centerIn: parent
            spacing: 5
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 17; height: 17; radius: 9
                color: settingsWin.fixedTrack
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Rectangle { width: 30; height: 4; radius: 2; color: settingsWin.fixedOn }
                Row {
                    spacing: 4
                    Rectangle { width: 15; height: 7; radius: 3; color: "#65d58a" }
                    Rectangle { width: 15; height: 7; radius: 3; color: "#d5657f" }
                }
            }
        }
    }

    component PvPulseRing: PreviewTile {
        Item {
            anchors.centerIn: parent
            width: 26
            height: 26

            Rectangle {
                anchors.centerIn: parent
                width: 26; height: 26; radius: 13
                color: "transparent"
                border.width: 1
                border.color: "#65d58a"
                opacity: 0.3 + 0.4 * Math.abs(Math.sin(settingsWin.host.visualPhase))
            }
            Rectangle {
                anchors.centerIn: parent
                width: 13; height: 13; radius: 7
                color: "#65d58a"
            }
        }
    }

    // The clock rows show the real clock with only their own option applied, so
    // "24 hour" is answered by reading the digits rather than the label.
    component PvClock24: PreviewTile {
        PixelClock {
            anchors.centerIn: parent
            time: settingsWin.host.currentTime
            lang: settingsWin.host.lang
            hour24: settingsWin.host.clock24Hour
            style: settingsWin.host.clockStyle
            textFont: settingsWin.host.uiFont
            showSeconds: false
            showDate: false
            cell: 2
            gap: 1
            color: settingsWin.fixedText
            mutedColor: settingsWin.fixedMuted
            gridColor: "transparent"
        }
    }

    // Schematic rather than a real PixelClock: the clock's own date/label text
    // has a hard minimum font size, so a wide clock cannot be made to fit this
    // tile by any combination of cell size and scaling. Cell blocks say "digits"
    // in the island's own vocabulary and always fit.
    component PvClockSeconds: PreviewTile {
        Row {
            anchors.centerIn: parent
            spacing: 3

            Repeater {
                model: 2
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11; height: 16; radius: 2
                    color: settingsWin.fixedText
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 3; radius: 1
                color: settingsWin.fixedMuted
            }
            Repeater {
                model: 2
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11; height: 16; radius: 2
                    color: settingsWin.fixedText
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 3; radius: 1
                color: settingsWin.fixedMuted
            }
            // The seconds sit smaller and dimmer beside the clock, which is
            // exactly how the island draws them.
            Repeater {
                model: 2
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 11; radius: 2
                    color: settingsWin.fixedMuted
                }
            }
        }
    }

    component PvClockDate: PreviewTile {
        Column {
            anchors.centerIn: parent
            spacing: 5

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 3

                Repeater {
                    model: 2
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 11; height: 15; radius: 2
                        color: settingsWin.fixedText
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3; height: 3; radius: 1
                    color: settingsWin.fixedMuted
                }
                Repeater {
                    model: 2
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 11; height: 15; radius: 2
                        color: settingsWin.fixedText
                    }
                }
            }

            // The line under the clock is the whole point of the setting.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 50; height: 3; radius: 1
                color: settingsWin.fixedMuted
            }
        }
    }

    component PvClockGrid: PreviewTile {
        PixelClock {
            anchors.centerIn: parent
            time: settingsWin.host.currentTime
            lang: settingsWin.host.lang
            hour24: settingsWin.host.clock24Hour
            style: settingsWin.host.clockStyle
            textFont: settingsWin.host.uiFont
            showSeconds: false
            showDate: false
            cell: 2
            gap: 1
            color: settingsWin.fixedText
            mutedColor: settingsWin.fixedMuted
            gridColor: settingsWin.host.clockGrid ? settingsWin.fixedGrid : "transparent"
        }
    }

    component PvHover: PreviewTile {
        Item {
            anchors.centerIn: parent
            width: 58
            height: 24

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: 58; height: 13; radius: 6
                color: settingsWin.fixedChipHover
            }
            // The pointer arriving from below is what opens it.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 12
                text: "󰆾"
                color: settingsWin.fixedOn
                font.family: settingsWin.host.iconFont
                font.pixelSize: 12
            }
        }
    }

    // "Theme / dark" is a question about a surface, which a swatch answers and a
    // word does not: each tile is the media panel drawn on that surface.
    component SurfacePicker: Rectangle {
        implicitHeight: 112
        radius: 16
        color: settingsWin.fixedChip

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Repeater {
                model: ["theme", "dark"]

                Rectangle {
                    id: surfOpt
                    required property string modelData

                    readonly property bool active: settingsWin.host.mediaSurfaceMode === surfOpt.modelData

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 11
                    color: settingsWin.fixedChipHover
                    border.width: 1
                    border.color: surfOpt.active ? settingsWin.fixedText : "transparent"
                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 7

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: surfOpt.modelData === "dark" ? "#000000"
                                                                : settingsWin.fixedSurface
                            border.width: 1
                            border.color: settingsWin.fixedLine

                            Row {
                                anchors.centerIn: parent
                                spacing: 5

                                Rectangle {
                                    width: 18; height: 18; radius: 4
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#57657f" }
                                        GradientStop { position: 1.0; color: "#7c4b39" }
                                    }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    Rectangle {
                                        width: 30; height: 4; radius: 2
                                        color: surfOpt.modelData === "dark" ? "#ededed"
                                                                            : settingsWin.fixedText
                                    }
                                    Rectangle {
                                        width: 20; height: 3; radius: 1
                                        color: surfOpt.modelData === "dark" ? "#7f7f7f"
                                                                            : settingsWin.fixedMuted
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: surfOpt.modelData === "dark" ? settingsWin.i18n.mediaSurfaceDark
                                                               : settingsWin.i18n.mediaSurfaceTheme
                            color: surfOpt.active ? settingsWin.fixedText
                                                  : settingsWin.fixedMuted
                            font.family: settingsWin.host.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            settingsWin.host.mediaSurfaceMode = surfOpt.modelData
                            settingsWin.host.saveSettings()
                        }
                    }
                }
            }
        }
    }

    // Intensity is a contrast, so each tile shows the same bars at the contrast
    // that option produces — the thing being chosen, not a word for it.
    component IntensityPicker: Rectangle {
        implicitHeight: 112
        radius: 16
        color: settingsWin.fixedChip

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Repeater {
                model: [45, 70, 100]

                Rectangle {
                    id: intOpt
                    required property int modelData

                    readonly property bool active: settingsWin.host.mediaAnimationIntensity === intOpt.modelData
                    readonly property string displayLabel: {
                        switch (intOpt.modelData) {
                        case 45: return settingsWin.i18n.intensitySoft
                        case 70: return settingsWin.i18n.intensityBalanced
                        default: return settingsWin.i18n.intensityBold
                        }
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 11
                    color: settingsWin.fixedChipHover
                    border.width: 1
                    border.color: intOpt.active ? settingsWin.fixedText : "transparent"
                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 7

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            Row {
                                anchors.centerIn: parent
                                spacing: 3

                                Repeater {
                                    model: 9

                                    Rectangle {
                                        required property int index
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 4
                                        height: 5 + Math.abs(Math.sin(
                                            settingsWin.host.visualPhase + index * 0.72)) * 30
                                        radius: 2
                                        color: settingsWin.fixedText
                                        opacity: intOpt.modelData / 100
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: intOpt.displayLabel
                            color: intOpt.active ? settingsWin.fixedText
                                                 : settingsWin.fixedMuted
                            font.family: settingsWin.host.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            settingsWin.host.mediaAnimationIntensity = intOpt.modelData
                            settingsWin.host.saveSettings()
                        }
                    }
                }
            }
        }
    }

    // "Names / logos / in strip" says nothing about what lands on screen, so
    // each option draws the shape it actually produces over the cover art.
    component PlayerSwitcherPicker: Rectangle {
        implicitHeight: 118
        radius: 16
        color: settingsWin.fixedChip

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Repeater {
                model: ["chips", "logos", "segment"]

                Rectangle {
                    id: swOpt
                    required property string modelData

                    readonly property bool active: settingsWin.host.playerSwitcherStyle === swOpt.modelData
                    readonly property string displayLabel: {
                        switch (swOpt.modelData) {
                        case "logos": return settingsWin.i18n.switcherLogos
                        case "segment": return settingsWin.i18n.switcherSegment
                        default: return settingsWin.i18n.switcherChips
                        }
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 11
                    color: settingsWin.fixedChipHover
                    border.width: 1
                    border.color: swOpt.active ? settingsWin.fixedText : "transparent"
                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            Row {
                                anchors.centerIn: parent
                                visible: swOpt.modelData === "chips"
                                spacing: 3
                                Rectangle {
                                    width: 30; height: 13; radius: 4
                                    color: settingsWin.fixedOn
                                }
                                Rectangle {
                                    width: 30; height: 13; radius: 4
                                    color: settingsWin.fixedTrack
                                }
                            }

                            Row {
                                anchors.centerIn: parent
                                visible: swOpt.modelData === "logos"
                                spacing: 7
                                Rectangle {
                                    width: 15; height: 15; radius: 8
                                    color: settingsWin.fixedOn
                                    border.width: 1
                                    border.color: settingsWin.fixedText
                                }
                                Rectangle {
                                    width: 15; height: 15; radius: 8
                                    color: settingsWin.fixedTrack
                                }
                                Rectangle {
                                    width: 15; height: 15; radius: 8
                                    color: settingsWin.fixedTrack
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                visible: swOpt.modelData === "segment"
                                width: 68; height: 19; radius: 6
                                color: settingsWin.fixedTrack

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Rectangle {
                                        width: 31; height: 15; radius: 5
                                        color: settingsWin.fixedOn
                                    }
                                    Rectangle {
                                        width: 31; height: 15; radius: 5
                                        color: "transparent"
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: swOpt.displayLabel
                            color: swOpt.active ? settingsWin.fixedText
                                                : settingsWin.fixedMuted
                            font.family: settingsWin.host.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            settingsWin.host.playerSwitcherStyle = swOpt.modelData
                            settingsWin.host.saveSettings()
                        }
                    }
                }
            }
        }
    }

    // Same reasoning as the switcher picker. `dimmed` is set while the queue
    // itself is switched off: the options stay readable so you can see what
    // turning it on would give you, but they stop accepting clicks rather than
    // quietly changing a setting with no visible effect.
    component QueueStylePicker: Rectangle {
        id: queuePicker
        property bool dimmed: false

        implicitHeight: 118
        radius: 16
        color: settingsWin.fixedChip
        opacity: queuePicker.dimmed ? 0.4 : 1
        enabled: !queuePicker.dimmed
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Repeater {
                model: ["list", "covers", "timeline"]

                Rectangle {
                    id: qOpt
                    required property string modelData

                    readonly property bool active: settingsWin.host.queueStyle === qOpt.modelData
                    readonly property string displayLabel: {
                        switch (qOpt.modelData) {
                        case "covers": return settingsWin.i18n.queueStyleCovers
                        case "timeline": return settingsWin.i18n.queueStyleTimeline
                        default: return settingsWin.i18n.queueStyleList
                        }
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 11
                    color: settingsWin.fixedChipHover
                    border.width: 1
                    border.color: qOpt.active ? settingsWin.fixedText : "transparent"
                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            Column {
                                anchors.centerIn: parent
                                visible: qOpt.modelData === "list"
                                spacing: 5

                                Repeater {
                                    model: 3
                                    Row {
                                        spacing: 5
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 4; height: 4; radius: 1
                                            color: settingsWin.fixedMuted
                                        }
                                        Column {
                                            spacing: 2
                                            Rectangle {
                                                width: 36; height: 3; radius: 1
                                                color: settingsWin.fixedOn
                                            }
                                            Rectangle {
                                                width: 24; height: 2; radius: 1
                                                color: settingsWin.fixedTrack
                                            }
                                        }
                                    }
                                }
                            }

                            Row {
                                anchors.centerIn: parent
                                visible: qOpt.modelData === "covers"
                                spacing: 5

                                Repeater {
                                    model: 3
                                    Column {
                                        spacing: 3
                                        Rectangle {
                                            width: 21; height: 21; radius: 5
                                            color: settingsWin.fixedTrack
                                        }
                                        Rectangle {
                                            width: 21; height: 3; radius: 1
                                            color: settingsWin.fixedOn
                                        }
                                    }
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                visible: qOpt.modelData === "timeline"
                                spacing: 6

                                Repeater {
                                    model: 3
                                    Row {
                                        spacing: 5
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 14; height: 3; radius: 1
                                            color: settingsWin.fixedTrack
                                        }
                                        // The knots lining up down the column is
                                        // what reads as the rail at this size.
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 5; height: 5; radius: 3
                                            color: settingsWin.fixedMuted
                                        }
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 30; height: 3; radius: 1
                                            color: settingsWin.fixedOn
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: qOpt.displayLabel
                            color: qOpt.active ? settingsWin.fixedText
                                               : settingsWin.fixedMuted
                            font.family: settingsWin.host.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            settingsWin.host.queueStyle = qOpt.modelData
                            settingsWin.host.saveSettings()
                        }
                    }
                }
            }
        }
    }

    // Motion is easier to choose by feel than by name, so every option shows
    // the same miniature bar field used by the player instead of a static icon.
    component AnimationStylePicker: Rectangle {
        implicitHeight: 118
        radius: 16
        color: settingsWin.fixedChip

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Repeater {
                model: ["wave", "live", "calm"]

                Rectangle {
                    id: previewOpt
                    required property string modelData

                    readonly property bool active: settingsWin.host.mediaAnimationStyle === previewOpt.modelData
                    readonly property string displayLabel: {
                        switch (previewOpt.modelData) {
                        case "live": return settingsWin.i18n.animLive
                        case "calm": return settingsWin.i18n.animCalm
                        default: return settingsWin.i18n.animWave
                        }
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 11
                    color: settingsWin.fixedChipHover
                    border.width: 1
                    border.color: previewOpt.active ? settingsWin.fixedText : "transparent"
                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 7

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            Row {
                                anchors.centerIn: parent
                                spacing: 3

                                Repeater {
                                    model: 11

                                    Rectangle {
                                        required property int index
                                        readonly property real phase: settingsWin.host.visualPhase
                                        readonly property real amount: {
                                            if (previewOpt.modelData === "live") {
                                                let levels = settingsWin.host.visualLevels
                                                let level = levels && levels.length > 0
                                                    ? Number(levels[index % levels.length] || 0) / 100 : 0
                                                return settingsWin.host.cavaLive ? 0.08 + Math.min(1, level) * 0.88 : 0.08
                                            }
                                            if (previewOpt.modelData === "calm")
                                                return 0.12 + Math.abs(Math.sin(phase * 0.48 + index * 0.32)) * 0.28
                                            return 0.12 + Math.abs(Math.sin(phase + index * 0.72)) * 0.82
                                        }
                                        width: 4
                                        height: 5 + amount * 34
                                        radius: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: settingsWin.fixedText
                                        opacity: settingsWin.host.mediaAnimationIntensity / 100
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: previewOpt.displayLabel
                            color: previewOpt.active ? settingsWin.fixedText : settingsWin.fixedMuted
                            font.family: settingsWin.host.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            settingsWin.host.mediaAnimationStyle = previewOpt.modelData
                            settingsWin.host.saveSettings()
                        }
                    }
                }
            }
        }
    }
}
