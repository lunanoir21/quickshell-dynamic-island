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

    signal dismissRequested()

    readonly property var i18n: host.i18n

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

    // Click-outside-to-dismiss. The window below has its own MouseArea that
    // swallows clicks so they never reach this one.
    Rectangle {
        anchors.fill: parent
        visible: opacity > 0.01
        color: settingsWin.host.themeScrim
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
        color: settingsWin.host.themeSurface
        border.width: 1
        border.color: settingsWin.host.themeLine
        opacity: settingsWin.open ? 1 : 0
        scale: settingsWin.open ? 1 : 0.94

        MouseArea {
            anchors.fill: parent
            onClicked: {
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutBack
                easing.overshoot: 0.6
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ------------------------------------------------------ sidebar
            Rectangle {
                Layout.preferredWidth: 220
                Layout.fillHeight: true
                color: settingsWin.host.themeChip

                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: settingsWin.host.themeLine
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
                            color: settingsWin.host.themeOn

                            Text {
                                anchors.centerIn: parent
                                text: "󰀻"
                                color: settingsWin.host.themeOnText
                                font.family: settingsWin.host.iconFont
                                font.pixelSize: 17
                            }
                        }

                        ColumnLayout {
                            spacing: 0

                            Text {
                                text: "Dynamic Island"
                                color: settingsWin.host.themeText
                                font.family: settingsWin.host.uiFont
                                font.weight: Font.Bold
                                font.pixelSize: 15
                            }

                            Text {
                                text: "quickshell"
                                color: settingsWin.host.themeMuted
                                font.family: settingsWin.host.uiFont
                                font.pixelSize: 12
                            }
                        }
                    }

                    Repeater {
                        model: ["appearance", "clock", "calls", "notifications", "media", "general"]

                        NavItem {
                            required property string modelData
                            Layout.fillWidth: true
                            icon: {
                                switch (modelData) {
                                case "clock": return "󰥔"
                                case "calls": return "󰏶"
                                case "notifications": return "󰂚"
                                case "media": return "󰎈"
                                case "general": return "󰖟"
                                default: return "󰸌"
                                }
                            }
                            label: {
                                switch (modelData) {
                                case "clock": return settingsWin.i18n.secClock
                                case "calls": return settingsWin.i18n.secCalls
                                case "notifications": return settingsWin.i18n.secNotifications
                                case "media": return settingsWin.i18n.secMedia
                                case "general": return settingsWin.i18n.secGeneral
                                default: return settingsWin.i18n.secAppearance
                                }
                            }
                            active: settingsWin.section === modelData
                            onTriggered: settingsWin.section = modelData
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.bottomMargin: 10
                        color: settingsWin.host.themeLine
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        text: "~/.config/quickshell"
                        color: settingsWin.host.themeMuted
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
                                case "calls": return settingsWin.i18n.secCalls
                                case "notifications": return settingsWin.i18n.secNotifications
                                case "media": return settingsWin.i18n.secMedia
                                case "general": return settingsWin.i18n.secGeneral
                                default: return settingsWin.i18n.secAppearance
                                }
                            }
                            color: settingsWin.host.themeText
                            font.family: settingsWin.host.uiFont
                            font.weight: Font.Bold
                            font.pixelSize: 23
                        }

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 18
                            color: closeHit.containsMouse ? settingsWin.host.themeChipHover
                                                          : settingsWin.host.themeChip
                            Behavior on color { ColorAnimation { duration: 140 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                color: settingsWin.host.themeSubtext
                                font.family: settingsWin.host.iconFont
                                font.pixelSize: 15
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
                            case "calls": return settingsWin.i18n.secCallsSub
                            case "notifications": return settingsWin.i18n.secNotificationsSub
                            case "media": return settingsWin.i18n.secMediaSub
                            case "general": return settingsWin.i18n.secGeneralSub
                            default: return settingsWin.i18n.secAppearanceSub
                            }
                        }
                        color: settingsWin.host.themeMuted
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
                    ScrollBar.vertical: ScrollBar {
                        policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    ColumnLayout {
                        id: sections
                        width: flick.width
                        spacing: 14

                        // ------------------------------------------ appearance
                        SettingGroup {
                            visible: settingsWin.section === "appearance"
                            label: settingsWin.i18n.grpTheme

                            ThemePicker { Layout.fillWidth: true }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "appearance"
                            label: settingsWin.i18n.grpSurfaces

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰺕"
                                label: settingsWin.i18n.setBorders
                                detail: settingsWin.i18n.setBordersDesc
                                checked: settingsWin.host.showBorders
                                onToggled: {
                                    settingsWin.host.showBorders = !settingsWin.host.showBorders
                                    settingsWin.host.saveSettings()
                                }
                            }

                            ChoiceRow {
                                Layout.fillWidth: true
                                icon: "󰋩"
                                label: settingsWin.i18n.setMediaSurface
                                detail: settingsWin.i18n.setMediaSurfaceDesc
                                options: [settingsWin.i18n.mediaSurfaceTheme,
                                          settingsWin.i18n.mediaSurfaceDark]
                                values: ["theme", "dark"]
                                current: settingsWin.host.mediaSurfaceMode
                                onPicked: value => {
                                    settingsWin.host.mediaSurfaceMode = value
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        // ----------------------------------------------- clock
                        SettingGroup {
                            visible: settingsWin.section === "clock"
                            label: settingsWin.i18n.grpStyle

                            ClockStylePicker { Layout.fillWidth: true }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "clock"
                            label: settingsWin.i18n.grpFormat

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰥔"
                                label: settingsWin.i18n.setClock24h
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

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰏶"
                                label: settingsWin.i18n.setCallAutoPopup
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

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰑚"
                                label: settingsWin.i18n.setInlineReply
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
                                detail: settingsWin.i18n.setAppIconDesc
                                checked: settingsWin.host.notificationAppIcon
                                onToggled: {
                                    settingsWin.host.notificationAppIcon = !settingsWin.host.notificationAppIcon
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        // ----------------------------------------------- media
                        SettingGroup {
                            visible: settingsWin.section === "media"
                            label: settingsWin.i18n.grpPanel

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰨖"
                                label: settingsWin.i18n.setLyrics
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
                                detail: settingsWin.i18n.setSpectrumDesc
                                checked: settingsWin.host.mediaSpectrumEnabled
                                onToggled: {
                                    settingsWin.host.mediaSpectrumEnabled = !settingsWin.host.mediaSpectrumEnabled
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰋩"
                                label: settingsWin.i18n.setAlbumArt
                                detail: settingsWin.i18n.setAlbumArtDesc
                                checked: settingsWin.host.mediaAlbumArtEnabled
                                onToggled: {
                                    settingsWin.host.mediaAlbumArtEnabled = !settingsWin.host.mediaAlbumArtEnabled
                                    settingsWin.host.saveSettings()
                                }
                            }

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰐊"
                                label: settingsWin.i18n.setCompactControls
                                detail: settingsWin.i18n.setCompactControlsDesc
                                checked: settingsWin.host.compactMediaControls
                                onToggled: {
                                    settingsWin.host.compactMediaControls = !settingsWin.host.compactMediaControls
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "media"
                            label: settingsWin.i18n.grpMotion

                            AnimationStylePicker { Layout.fillWidth: true }

                            ChoiceRow {
                                Layout.fillWidth: true
                                icon: "󰍉"
                                label: settingsWin.i18n.setAnimationIntensity
                                detail: settingsWin.i18n.setAnimationIntensityDesc
                                options: [settingsWin.i18n.intensitySoft,
                                          settingsWin.i18n.intensityBalanced,
                                          settingsWin.i18n.intensityBold]
                                values: [45, 70, 100]
                                current: settingsWin.host.mediaAnimationIntensity
                                onPicked: value => {
                                    settingsWin.host.mediaAnimationIntensity = value
                                    settingsWin.host.saveSettings()
                                }
                            }
                        }

                        // --------------------------------------------- general
                        SettingGroup {
                            visible: settingsWin.section === "general"
                            label: settingsWin.i18n.grpLanguage

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

                            SettingRow {
                                Layout.fillWidth: true
                                icon: "󰇀"
                                label: settingsWin.i18n.setHoverOpen
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
    component NavItem: Rectangle {
        id: nav

        property string icon: ""
        property string label: ""
        property bool active: false

        signal triggered()

        implicitHeight: 42
        radius: 12
        color: nav.active ? settingsWin.host.themeOn
                          : (navHit.containsMouse ? settingsWin.host.themeChipHover : "transparent")
        Behavior on color { ColorAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 11

            Rectangle {
                Layout.preferredWidth: 3
                Layout.preferredHeight: nav.active ? 20 : 8
                radius: 2
                color: nav.active ? settingsWin.host.themeOnText : "transparent"
                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            Text {
                text: nav.icon
                color: nav.active ? settingsWin.host.themeOnText : settingsWin.host.themeSubtext
                font.family: settingsWin.host.iconFont
                font.pixelSize: 16
                Behavior on color { ColorAnimation { duration: 140 } }
            }

            Text {
                Layout.fillWidth: true
                text: nav.label
                color: nav.active ? settingsWin.host.themeOnText : settingsWin.host.themeSubtext
                font.family: settingsWin.host.uiFont
                font.weight: nav.active ? Font.DemiBold : Font.Normal
                font.pixelSize: 15
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: 140 } }
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

        // Layouts skip invisible children outright, so hiding a group is all
        // it takes for the six sections to share one column without a
        // StackLayout and without leaving a gap behind.
        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 1
            text: group.label
            color: settingsWin.host.themeMuted
            font.family: settingsWin.host.uiFont
            font.weight: Font.Bold
            font.pixelSize: 12
            font.letterSpacing: 1.2
            font.capitalization: Font.AllUppercase
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

        signal toggled()

        implicitHeight: 66
        radius: 16
        color: (rowHit.containsMouse && enabled && !locked) ? settingsWin.host.themeChipHover
                                                            : settingsWin.host.themeChip
        opacity: enabled ? 1 : 0.45
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on opacity { NumberAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 11
                color: settingsWin.host.themeSurfaceAlt

                Text {
                    anchors.centerIn: parent
                    text: row.icon
                    color: settingsWin.host.themeSubtext
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
                    color: settingsWin.host.themeText
                    font.family: settingsWin.host.uiFont
                    font.pixelSize: 15
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: row.detail !== ""
                    text: row.detail
                    color: settingsWin.host.themeMuted
                    font.family: settingsWin.host.uiFont
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
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

    component TogglePill: Rectangle {
        id: pill

        property bool on: false
        property bool dimmed: false

        implicitWidth: 64
        implicitHeight: 30
        radius: 15
        opacity: pill.dimmed ? 0.75 : 1
        color: pill.on ? settingsWin.host.themeOn : settingsWin.host.themeSurfaceAlt
        Behavior on color { ColorAnimation { duration: 140 } }

        Text {
            anchors.centerIn: parent
            text: pill.on ? settingsWin.i18n.settingsOn : settingsWin.i18n.settingsOff
            color: pill.on ? settingsWin.host.themeOnText : settingsWin.host.themeMuted
            font.family: settingsWin.host.uiFont
            font.weight: Font.Bold
            font.pixelSize: 10
            font.letterSpacing: 0.4
            Behavior on color { ColorAnimation { duration: 140 } }
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

        signal picked(var value)

        implicitHeight: 66
        radius: 16
        color: settingsWin.host.themeChip

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 11
                color: settingsWin.host.themeSurfaceAlt

                Text {
                    anchors.centerIn: parent
                    text: choice.icon
                    color: settingsWin.host.themeSubtext
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
                    color: settingsWin.host.themeText
                    font.family: settingsWin.host.uiFont
                    font.pixelSize: 15
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: choice.detail !== ""
                    text: choice.detail
                    color: settingsWin.host.themeMuted
                    font.family: settingsWin.host.uiFont
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredWidth: segRow.implicitWidth + 6
                Layout.preferredHeight: 38
                radius: 13
                color: settingsWin.host.themeSurfaceAlt

                RowLayout {
                    id: segRow
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: choice.options.length

                        Rectangle {
                            id: seg
                            required property int index

                            readonly property bool active: choice.values[seg.index] === choice.current

                            implicitWidth: segLabel.implicitWidth + 20
                            implicitHeight: 32
                            radius: 10
                            color: seg.active ? settingsWin.host.themeOn
                                              : (segHit.containsMouse ? settingsWin.host.themeChipHover : "transparent")
                            Behavior on color { ColorAnimation { duration: 140 } }

                            Text {
                                id: segLabel
                                anchors.centerIn: parent
                                text: choice.options[seg.index]
                                color: seg.active ? settingsWin.host.themeOnText : settingsWin.host.themeMuted
                                font.family: settingsWin.host.uiFont
                                font.weight: Font.DemiBold
                                font.pixelSize: 13
                                Behavior on color { ColorAnimation { duration: 140 } }
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

    // Four swatches rather than a segmented control: the whole point of a
    // theme is what it looks like, so the control shows the colour itself.
    component ThemePicker: Rectangle {
        implicitHeight: 112
        radius: 16
        color: settingsWin.host.themeChip

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Repeater {
                model: ["black", "umbra", "gray", "white"]

                Rectangle {
                    id: swatch
                    required property string modelData

                    readonly property bool active: settingsWin.host.themeName === swatch.modelData
                    readonly property string displayLabel: {
                        switch (swatch.modelData) {
                        case "black": return settingsWin.i18n.themeBlack
                        case "gray": return settingsWin.i18n.themeGray
                        case "white": return settingsWin.i18n.themeWhite
                        default: return settingsWin.i18n.themeUmbra
                        }
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 11
                    color: settingsWin.host.themeChipHover
                    border.width: 1
                    border.color: swatch.active ? settingsWin.host.themeText : "transparent"
                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 7

                        // Reads the palette table directly instead of carrying a
                        // second copy of the hex values, so a colour tweak in
                        // DynamicIsland.qml is reflected here automatically.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 7
                            clip: true
                            color: settingsWin.host.themePalettes[swatch.modelData].islandFill
                            border.width: 1
                            border.color: settingsWin.host.themePalettes[swatch.modelData].lineStrong

                            Rectangle {
                                anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
                                width: parent.width * 0.38
                                color: settingsWin.host.themePalettes[swatch.modelData].surfaceAlt
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: swatch.displayLabel
                            color: swatch.active ? settingsWin.host.themeText
                                                 : settingsWin.host.themeMuted
                            font.family: settingsWin.host.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: settingsWin.host.setTheme(swatch.modelData)
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
        color: settingsWin.host.themeChip

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
                    color: settingsWin.host.themeChipHover
                    border.width: 1
                    border.color: styleOpt.active ? settingsWin.host.themeText : "transparent"
                    Behavior on border.color { ColorAnimation { duration: 140 } }

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
                                color: settingsWin.host.themeText
                                mutedColor: settingsWin.host.themeMuted
                                gridColor: "transparent"
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: styleOpt.displayLabel
                            color: styleOpt.active ? settingsWin.host.themeText
                                                   : settingsWin.host.themeMuted
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
                            settingsWin.host.clockStyle = styleOpt.modelData
                            settingsWin.revealClock()
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
        color: settingsWin.host.themeChip

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
                    color: settingsWin.host.themeChipHover
                    border.width: 1
                    border.color: previewOpt.active ? settingsWin.host.themeText : "transparent"
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
                                        color: settingsWin.host.themeText
                                        opacity: settingsWin.host.mediaAnimationIntensity / 100
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: previewOpt.displayLabel
                            color: previewOpt.active ? settingsWin.host.themeText : settingsWin.host.themeMuted
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
