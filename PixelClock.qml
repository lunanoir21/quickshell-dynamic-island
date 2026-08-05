import QtQuick
import "pixelfont.js" as PixelFont

// Pixel-art clock: chunky HH:MM digits over a dormant LED grid, a smaller
// seconds pair hanging off the right, and a date strip underneath. Every digit
// rolls vertically when it changes, one pixel row at a time.
Item {
    id: root

    property date time: new Date()
    property real cell: 7
    property real gap: 2
    property color color: "#f4f4f4"
    property color gridColor: "#1c1c1c"
    property color mutedColor: "#8a8a8a"
    property bool showSeconds: true
    property bool showDate: true
    property bool compact: false
    // Only the date strip is language-dependent; the digits are digits.
    property string lang: "en"

    implicitWidth: stack.implicitWidth
    implicitHeight: stack.implicitHeight

    Column {
        id: stack
        anchors.centerIn: parent
        spacing: Math.round(root.cell * (root.compact ? 1.1 : 1.9))

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(root.cell * 1.9)

            PixelText {
                id: hoursMinutes
                anchors.bottom: parent.bottom
                text: Qt.formatDateTime(root.time, "HH:mm")
                cell: root.cell
                gap: root.gap
                color: root.color
                offColor: root.gridColor
                animated: true
                rollDuration: 340
            }

            // No dormant grid behind the seconds: at half the cell size it reads
            // as noise rather than as a matrix, and it muddies the big digits
            // sitting right next to it.
            PixelText {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(root.cell * 0.5)
                visible: root.showSeconds
                text: Qt.formatDateTime(root.time, "ss")
                cell: Math.max(1, Math.round(root.cell * 0.5))
                gap: Math.max(1, Math.round(root.gap * 0.5))
                color: root.mutedColor
                animated: true
                rollDuration: 260
            }
        }

        PixelText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showDate
            text: root.compact ? PixelFont.shortDateLine(root.time, root.lang)
                               : PixelFont.fullDateLine(root.time, root.lang)
            cell: Math.max(1, Math.round(root.cell * (root.compact ? 0.3 : 0.34)))
            gap: Math.max(1, Math.round(root.gap * 0.5))
            color: root.mutedColor
        }
    }
}
