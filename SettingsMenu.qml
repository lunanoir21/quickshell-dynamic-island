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
                        model: ["appearance", "clock", "calls", "notifications", "media", "panels", "general"]

                        NavItem {
                            required property string modelData
                            Layout.fillWidth: true
                            icon: {
                                switch (modelData) {
                                case "clock": return "󰥔"
                                case "calls": return "󰏶"
                                case "notifications": return "󰂚"
                                case "media": return "󰎈"
                                case "panels": return "󰕾"
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
                                case "panels": return settingsWin.i18n.secPanels
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
                                case "panels": return settingsWin.i18n.secPanels
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
                            case "panels": return settingsWin.i18n.secPanelsSub
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
                    // Switching sections keeps the previous section's scroll
                    // offset, which lands you mid-way down a shorter section
                    // looking at nothing. Every section starts at its top.
                    Connections {
                        target: settingsWin
                        function onSectionChanged() { flick.contentY = 0 }
                    }
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
                            note: settingsWin.i18n.grpThemeNote

                            ThemePicker { Layout.fillWidth: true }
                        }

                        SettingGroup {
                            visible: settingsWin.section === "appearance"
                            label: settingsWin.i18n.grpSurfaces
                            note: settingsWin.i18n.grpSurfacesNote

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

                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                text: settingsWin.i18n.setMediaSurfaceDesc
                                color: settingsWin.host.themeMuted
                                font.family: settingsWin.host.uiFont
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.preferredHeight: contentHeight
                            }

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

                        // ----------------------------------------------- media
                        SettingGroup {
                            visible: settingsWin.section === "media"
                            label: settingsWin.i18n.grpPanel
                            note: settingsWin.i18n.grpPanelNote

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

                        SettingGroup {
                            visible: settingsWin.section === "media"
                            label: settingsWin.i18n.grpMotion
                            note: settingsWin.i18n.grpMotionNote

                            AnimationStylePicker { Layout.fillWidth: true }

                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                text: settingsWin.i18n.setAnimationIntensityDesc
                                color: settingsWin.host.themeMuted
                                font.family: settingsWin.host.uiFont
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.preferredHeight: contentHeight
                            }

                            IntensityPicker { Layout.fillWidth: true }
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
            color: settingsWin.host.themeMuted
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
            color: settingsWin.host.themeMuted
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

    // ------------------------------------------------------------- previews
    // Miniatures for SettingRow.preview. Every one draws on the same dark tile,
    // so a row reads as "this is the thing that shows up on the island", and
    // every one takes its colours from the theme tokens, so the previews follow
    // the palette exactly like the island does.
    component PreviewTile: Rectangle {
        default property alias tileContent: tileInner.data

        anchors.fill: parent
        radius: 8
        color: settingsWin.host.themeSurfaceAlt
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
                color: settingsWin.host.themeTrack
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 48; height: 4; radius: 2
                color: settingsWin.host.themeOn
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 26; height: 3; radius: 1
                color: settingsWin.host.themeTrack
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
                    color: settingsWin.host.themeOn
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
                Rectangle { width: 28; height: 4; radius: 2; color: settingsWin.host.themeOn }
                Rectangle { width: 18; height: 3; radius: 1; color: settingsWin.host.themeTrack }
            }
        }
    }

    component PvMiniPlayer: PreviewTile {
        Rectangle {
            anchors.centerIn: parent
            width: 60; height: 19; radius: 10
            color: settingsWin.host.themeChipHover

            Row {
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11; height: 11; radius: 3
                    color: settingsWin.host.themeTrack
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 3; radius: 1
                    color: settingsWin.host.themeOn
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 4
                    color: settingsWin.host.themeOn
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
            border.color: settingsWin.host.themeText
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
                        color: settingsWin.host.themeTrack
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: [40, 26, 33][index]; height: 4; radius: 2
                        color: settingsWin.host.themeOn
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
                        color: settingsWin.host.themeMuted
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: [44, 34, 39][index]; height: 4; radius: 2
                        color: settingsWin.host.themeOn
                    }
                }
            }
        }
    }

    component PvReply: PreviewTile {
        Column {
            anchors.centerIn: parent
            spacing: 4
            Rectangle { width: 44; height: 4; radius: 2; color: settingsWin.host.themeOn }
            Rectangle {
                width: 54; height: 12; radius: 6
                color: "transparent"
                border.width: 1
                border.color: settingsWin.host.themeMuted

                Rectangle {
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1; height: 6
                    color: settingsWin.host.themeText
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
                color: settingsWin.host.themeOn
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Rectangle { width: 32; height: 4; radius: 2; color: settingsWin.host.themeOn }
                Rectangle { width: 22; height: 3; radius: 1; color: settingsWin.host.themeTrack }
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
                color: settingsWin.host.themeTrack
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Rectangle { width: 30; height: 4; radius: 2; color: settingsWin.host.themeOn }
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
            color: settingsWin.host.themeText
            mutedColor: settingsWin.host.themeMuted
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
                    color: settingsWin.host.themeText
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 3; radius: 1
                color: settingsWin.host.themeMuted
            }
            Repeater {
                model: 2
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11; height: 16; radius: 2
                    color: settingsWin.host.themeText
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 3; radius: 1
                color: settingsWin.host.themeMuted
            }
            // The seconds sit smaller and dimmer beside the clock, which is
            // exactly how the island draws them.
            Repeater {
                model: 2
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 11; radius: 2
                    color: settingsWin.host.themeMuted
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
                        color: settingsWin.host.themeText
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3; height: 3; radius: 1
                    color: settingsWin.host.themeMuted
                }
                Repeater {
                    model: 2
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 11; height: 15; radius: 2
                        color: settingsWin.host.themeText
                    }
                }
            }

            // The line under the clock is the whole point of the setting.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 50; height: 3; radius: 1
                color: settingsWin.host.themeMuted
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
            color: settingsWin.host.themeText
            mutedColor: settingsWin.host.themeMuted
            gridColor: settingsWin.host.clockGrid ? settingsWin.host.themeGrid : "transparent"
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
                color: settingsWin.host.themeChipHover
            }
            // The pointer arriving from below is what opens it.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 12
                text: "󰆾"
                color: settingsWin.host.themeOn
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
        color: settingsWin.host.themeChip

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
                    color: settingsWin.host.themeChipHover
                    border.width: 1
                    border.color: surfOpt.active ? settingsWin.host.themeText : "transparent"
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
                                                                : settingsWin.host.themeSurface
                            border.width: 1
                            border.color: settingsWin.host.themeLine

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
                                                                            : settingsWin.host.themeText
                                    }
                                    Rectangle {
                                        width: 20; height: 3; radius: 1
                                        color: surfOpt.modelData === "dark" ? "#7f7f7f"
                                                                            : settingsWin.host.themeMuted
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: surfOpt.modelData === "dark" ? settingsWin.i18n.mediaSurfaceDark
                                                               : settingsWin.i18n.mediaSurfaceTheme
                            color: surfOpt.active ? settingsWin.host.themeText
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
        color: settingsWin.host.themeChip

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
                    color: settingsWin.host.themeChipHover
                    border.width: 1
                    border.color: intOpt.active ? settingsWin.host.themeText : "transparent"
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
                                        color: settingsWin.host.themeText
                                        opacity: intOpt.modelData / 100
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: intOpt.displayLabel
                            color: intOpt.active ? settingsWin.host.themeText
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
        color: settingsWin.host.themeChip

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
                    color: settingsWin.host.themeChipHover
                    border.width: 1
                    border.color: swOpt.active ? settingsWin.host.themeText : "transparent"
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
                                    color: settingsWin.host.themeOn
                                }
                                Rectangle {
                                    width: 30; height: 13; radius: 4
                                    color: settingsWin.host.themeTrack
                                }
                            }

                            Row {
                                anchors.centerIn: parent
                                visible: swOpt.modelData === "logos"
                                spacing: 7
                                Rectangle {
                                    width: 15; height: 15; radius: 8
                                    color: settingsWin.host.themeOn
                                    border.width: 1
                                    border.color: settingsWin.host.themeText
                                }
                                Rectangle {
                                    width: 15; height: 15; radius: 8
                                    color: settingsWin.host.themeTrack
                                }
                                Rectangle {
                                    width: 15; height: 15; radius: 8
                                    color: settingsWin.host.themeTrack
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                visible: swOpt.modelData === "segment"
                                width: 68; height: 19; radius: 6
                                color: settingsWin.host.themeTrack

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Rectangle {
                                        width: 31; height: 15; radius: 5
                                        color: settingsWin.host.themeOn
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
                            color: swOpt.active ? settingsWin.host.themeText
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
        color: settingsWin.host.themeChip
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
                    color: settingsWin.host.themeChipHover
                    border.width: 1
                    border.color: qOpt.active ? settingsWin.host.themeText : "transparent"
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
                                            color: settingsWin.host.themeMuted
                                        }
                                        Column {
                                            spacing: 2
                                            Rectangle {
                                                width: 36; height: 3; radius: 1
                                                color: settingsWin.host.themeOn
                                            }
                                            Rectangle {
                                                width: 24; height: 2; radius: 1
                                                color: settingsWin.host.themeTrack
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
                                            color: settingsWin.host.themeTrack
                                        }
                                        Rectangle {
                                            width: 21; height: 3; radius: 1
                                            color: settingsWin.host.themeOn
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
                                            color: settingsWin.host.themeTrack
                                        }
                                        // The knots lining up down the column is
                                        // what reads as the rail at this size.
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 5; height: 5; radius: 3
                                            color: settingsWin.host.themeMuted
                                        }
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 30; height: 3; radius: 1
                                            color: settingsWin.host.themeOn
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: qOpt.displayLabel
                            color: qOpt.active ? settingsWin.host.themeText
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
