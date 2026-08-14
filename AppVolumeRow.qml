import QtQuick

// One application's row in the per-app mixer.
//
// Horizontal rather than the vertical channel strips the home meters use: a
// mixer has to stay readable at eight applications, and eight vertical strips
// squeeze the names down to nothing. The track keeps the island's segmented
// language — quantised cells, 3px gaps, radius 2, the leading segment glowing —
// so a row still reads as a relative of BarMeter rather than a stock slider.
Item {
    id: root

    property string appName: ""
    property string iconSource: ""
    property string fontFamily: ""
    property string iconFont: "Iosevka Nerd Font"
    property real value: 0
    property bool muted: false
    // The stream is uncorked, i.e. actually producing sound rather than merely
    // being open. Drives the shimmer, which is the only thing distinguishing an
    // app that is playing from one paused with a stream still held.
    property bool active: false
    property real phase: 0
    property int segments: 16
    property real nameWidth: 108

    property color textColor: "#f2f2f2"
    property color filledColor: "#f2f2f2"
    property color emptyColor: "#292929"
    property color disabledColor: "#5a5a5a"

    signal moved(real value)
    signal muteToggled()

    property bool dragging: false
    property real liveValue: value
    onValueChanged: if (!dragging && !settleGuard.running) liveValue = value

    implicitHeight: 30

    // One shared driver for the leading segment's glow, for the same reason
    // BarMeter uses one: a per-segment animation gated on being the edge leaves
    // its opacity frozen mid-fade once the bar moves past it.
    property real edgeGlow: 0
    NumberAnimation on edgeGlow {
        running: root.visible && !root.muted
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: 950
        easing.type: Easing.OutCubic
        onRunningChanged: if (!running) root.edgeGlow = 0
    }

    Timer {
        id: sendThrottle
        interval: 60
        onTriggered: root.moved(root.liveValue)
    }

    // Ignore backend echoes briefly after we move the bar ourselves, so an
    // in-flight poll carrying the old value can't snap it backwards.
    Timer {
        id: settleGuard
        interval: 1200
    }

    Item {
        id: logoSlot
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 22
        height: 22

        Image {
            anchors.fill: parent
            visible: root.iconSource !== ""
            source: root.iconSource
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            opacity: root.muted ? 0.3 : 1
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // Plenty of audio comes from things with no .desktop entry at all
        // (paplay, scripts, wrappers), so the slot always has something in it.
        Text {
            anchors.centerIn: parent
            visible: root.iconSource === ""
            text: "󰝚"
            color: root.muted ? root.disabledColor : root.textColor
            font.family: root.iconFont
            font.pixelSize: 14
        }
    }

    Text {
        id: nameLabel
        anchors { left: logoSlot.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
        width: root.nameWidth
        text: root.appName
        elide: Text.ElideRight
        color: root.muted ? root.disabledColor : root.textColor
        font.family: root.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Text {
        id: muteGlyph
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 18
        horizontalAlignment: Text.AlignHCenter
        text: root.muted ? "󰝟" : "󰕾"
        color: root.muted ? root.disabledColor : root.textColor
        font.family: root.iconFont
        font.pixelSize: 15
        scale: muteHit.pressed ? 0.85 : 1

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        MouseArea {
            id: muteHit
            anchors.fill: parent
            anchors.margins: -7
            onClicked: root.muteToggled()
        }
    }

    Text {
        id: readout
        anchors { right: muteGlyph.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        width: 38
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.muted ? 0 : root.liveValue) + "%"
        color: root.muted ? root.disabledColor : root.textColor
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.Bold
        // Keeps the column from twitching as the digits change mid-drag.
        font.features: ({ "tnum": 1 })
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Item {
        id: track
        anchors {
            left: nameLabel.right
            leftMargin: 14
            right: readout.left
            rightMargin: 14
            verticalCenter: parent.verticalCenter
        }
        height: 14
        scale: dragArea.pressed ? 1.02 : 1.0
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Row {
            anchors.fill: parent
            spacing: 3

            Repeater {
                model: root.segments
                Rectangle {
                    id: seg
                    required property int index

                    width: (track.width - (root.segments - 1) * 3) / root.segments
                    height: track.height
                    radius: 2

                    readonly property real threshold: (index / root.segments) * 100
                    readonly property bool filled: root.liveValue > threshold
                    readonly property bool edgeSeg: filled && root.liveValue <= threshold + (100 / root.segments)

                    color: filled ? (root.muted ? root.disabledColor : root.filledColor) : root.emptyColor
                    opacity: !filled && root.active && !root.muted
                        ? 0.35 + 0.25 * Math.abs(Math.sin(root.phase + index * 0.5))
                        : 1.0

                    Behavior on color { ColorAnimation { duration: root.dragging ? 0 : 150 } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: root.filledColor
                        opacity: (seg.edgeSeg && !root.muted) ? (1 - root.edgeGlow) * 0.55 : 0
                    }
                }
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            anchors.margins: -6
            onPressed: mouse => { root.dragging = true; root.updateFromX(mouse.x) }
            onPositionChanged: mouse => { if (pressed) root.updateFromX(mouse.x) }
            onReleased: {
                sendThrottle.stop()
                root.moved(root.liveValue)
                root.dragging = false
                settleGuard.restart()
            }
            onCanceled: {
                // Mirrors BarMeter: a grab stolen by the compositor would
                // otherwise leave `dragging` set, and with it the island's
                // interaction lock that keeps the panel from closing.
                root.dragging = false
                settleGuard.restart()
            }
        }
    }

    function updateFromX(x) {
        const ratio = Math.max(0, Math.min(1, (x - 6) / track.width))
        root.liveValue = Math.round(ratio * 100)
        if (!sendThrottle.running) sendThrottle.start()
    }
}
