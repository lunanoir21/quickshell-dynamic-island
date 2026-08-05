import QtQuick

Column {
    id: root

    property string label: ""
    property string fontFamily: ""
    property string iconFont: "Iosevka Nerd Font"
    property string icon: ""
    property real value: 0
    property bool active: true
    property bool shimmer: false
    property real phase: 0
    property int segments: 20
    property real barWidth: 28
    property real barHeight: 156

    signal moved(real value)
    signal iconClicked()

    property bool dragging: false
    property real liveValue: value
    readonly property real displayValue: liveValue
    onValueChanged: if (!dragging && !settleGuard.running) liveValue = value

    spacing: 9

    // One shared driver for the leading segment's glow. Previously each of the
    // twenty segments owned an infinite animation gated on being the edge, and
    // stopping one left its opacity frozen mid-fade, so segments the bar had
    // already passed stayed half-lit.
    property real edgeGlow: 0
    NumberAnimation on edgeGlow {
        running: root.visible && root.active
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
        repeat: false
        onTriggered: root.moved(root.liveValue)
    }

    // Ignore backend echoes for a bit after we change the value ourselves, so a
    // stale/in-flight poll response can't briefly snap the bar to an old value.
    Timer {
        id: settleGuard
        interval: 1200
        repeat: false
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label
        color: "#7d7d7d"
        font.family: root.fontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: 1.1
        font.pixelSize: 8
    }

    Item {
        id: track
        width: root.barWidth
        height: root.barHeight
        anchors.horizontalCenter: parent.horizontalCenter
        scale: dragArea.pressed ? 1.05 : 1.0
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Column {
            anchors.fill: parent
            spacing: 3

            Repeater {
                model: root.segments
                Rectangle {
                    id: seg
                    required property int index

                    width: track.width
                    height: (track.height - (root.segments - 1) * 3) / root.segments
                    radius: 2

                    readonly property int fromBottom: root.segments - 1 - index
                    readonly property real threshold: (fromBottom / root.segments) * 100
                    readonly property bool filled: root.displayValue > threshold
                    readonly property bool edgeSeg: filled && root.displayValue <= threshold + (100 / root.segments)

                    color: filled ? "#f2f2f2" : "#292929"
                    opacity: !filled && root.shimmer
                        ? 0.35 + 0.25 * Math.abs(Math.sin(root.phase + fromBottom * 0.5))
                        : 1.0

                    Behavior on color { ColorAnimation { duration: root.dragging ? 0 : 150 } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: "#ffffff"
                        // Reads straight off the shared driver, so it is exactly
                        // zero whenever the driver is at rest.
                        opacity: seg.edgeSeg ? (1 - root.edgeGlow) * 0.55 : 0
                    }
                }
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            anchors.margins: -6
            onPressed: mouse => { root.dragging = true; root.updateFromY(mouse.y) }
            onPositionChanged: mouse => { if (pressed) root.updateFromY(mouse.y) }
            onReleased: {
                sendThrottle.stop()
                root.moved(root.liveValue)
                root.dragging = false
                settleGuard.restart()
            }
            onCanceled: {
                // Without this a grab stolen by the compositor would leave
                // `dragging` set, and with it the island's interaction lock.
                root.dragging = false
                settleGuard.restart()
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.icon
        color: root.active ? "#f2f2f2" : "#5a5a5a"
        font.family: root.iconFont
        font.pixelSize: 15
        scale: iconHit.pressed ? 0.85 : 1

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        MouseArea {
            id: iconHit
            anchors.fill: parent
            anchors.margins: -7
            onClicked: root.iconClicked()
        }
    }

    function updateFromY(y) {
        const local = y - 6
        const ratio = 1 - Math.max(0, Math.min(1, local / track.height))
        root.liveValue = Math.round(ratio * 100)
        if (!sendThrottle.running) sendThrottle.start()
    }
}
