import QtQuick
import "pixelfont.js" as PixelFont

// Pixel-art clock: chunky HH:MM digits over a dormant LED grid, a smaller
// seconds pair hanging off the right, and a date strip underneath. Every digit
// rolls vertically when it changes, one pixel row at a time.
//
// Three styles, all driven from the same 5x7 bitmaps rather than three separate
// renderers: "pixel" keeps the gap between cells so the matrix reads as
// discrete LEDs, "segment" closes it to zero so neighbouring cells fuse into
// solid strokes, and "plain" drops the matrix for ordinary text.
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
    property bool hour24: true
    property bool compact: false
    // "pixel" | "segment" | "plain"
    property string style: "pixel"
    // The face used by the plain style. Left to the caller so the clock matches
    // whatever the rest of the shell is set to.
    property string textFont: "sans-serif"
    // Only the date strip is language-dependent; the digits are digits.
    property string lang: "en"

    readonly property bool plain: style === "plain"
    // Segment mode fuses the cells; the dormant grid behind them would show
    // through the joins as a solid block, so it is dropped there. Its cell
    // absorbs the removed gap so the finished glyph keeps exactly the same
    // outer footprint as the pixel style instead of shrinking by ~25%.
    readonly property real mainCell: style === "segment" ? cell + gap : cell
    readonly property real activeGap: style === "segment" ? 0 : gap
    readonly property color activeGrid: style === "segment" ? "transparent" : gridColor
    readonly property real smallCellBase: Math.max(1, Math.round(cell * 0.5))
    readonly property real smallGapBase: Math.max(1, Math.round(gap * 0.5))
    readonly property real smallCell: style === "segment" ? smallCellBase + smallGapBase : smallCellBase
    readonly property real smallGap: style === "segment" ? 0 : smallGapBase
    readonly property real dateCellBase: Math.max(1, Math.round(cell * (compact ? 0.3 : 0.34)))
    readonly property real dateGapBase: Math.max(1, Math.round(gap * 0.5))
    readonly property real dateCell: style === "segment" ? dateCellBase + dateGapBase : dateCellBase
    readonly property real dateGap: style === "segment" ? 0 : dateGapBase

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
                visible: !root.plain
                text: Qt.formatDateTime(root.time, root.hour24 ? "HH:mm" : "hh:mm")
                cell: root.mainCell
                gap: root.activeGap
                color: root.color
                offColor: root.activeGrid
                animated: true
                rollDuration: 340
            }

            // Plain style: ordinary text at a size that matches the matrix it
            // replaces, so switching styles doesn't resize the panel.
            Text {
                anchors.bottom: parent.bottom
                visible: root.plain
                text: Qt.formatDateTime(root.time, root.hour24 ? "HH:mm" : "hh:mm")
                color: root.color
                font.family: root.textFont
                font.weight: Font.Bold
                font.pixelSize: Math.round(root.cell * 9.3)
                font.letterSpacing: Math.round(root.cell * 0.6)
            }

            // No dormant grid behind the seconds: at half the cell size it reads
            // as noise rather than as a matrix, and it muddies the big digits
            // sitting right next to it.
            PixelText {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(root.cell * 0.5)
                visible: root.showSeconds && !root.plain
                text: Qt.formatDateTime(root.time, "ss")
                cell: root.smallCell
                gap: root.smallGap
                color: root.mutedColor
                animated: true
                rollDuration: 260
            }

            // AM/PM, only meaningful (and only shown) in 12-hour mode.
            PixelText {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(root.cell * 0.5)
                visible: !root.hour24 && !root.plain
                text: Qt.formatDateTime(root.time, "AP")
                cell: root.smallCell
                gap: root.smallGap
                color: root.mutedColor
            }

            // Plain style keeps seconds and AM/PM as one trailing label rather
            // than two separately-aligned blocks — at text sizes the matrix's
            // baseline trickery isn't needed.
            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(root.cell * 0.8)
                visible: root.plain && (root.showSeconds || !root.hour24)
                text: (root.showSeconds ? Qt.formatDateTime(root.time, "ss") : "")
                      + (!root.hour24 ? (root.showSeconds ? " " : "") + Qt.formatDateTime(root.time, "AP") : "")
                color: root.mutedColor
                font.family: root.textFont
                font.weight: Font.Bold
                font.pixelSize: Math.round(root.cell * 3.4)
            }
        }

        PixelText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showDate && !root.plain
            text: root.compact ? PixelFont.shortDateLine(root.time, root.lang)
                               : PixelFont.fullDateLine(root.time, root.lang)
            cell: root.dateCell
            gap: root.dateGap
            color: root.mutedColor
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showDate && root.plain
            text: root.compact ? PixelFont.shortDateLine(root.time, root.lang)
                               : PixelFont.fullDateLine(root.time, root.lang)
            color: root.mutedColor
            font.family: root.textFont
            font.weight: Font.Bold
            font.letterSpacing: 1.2
            font.pixelSize: Math.max(8, Math.round(root.cell * (root.compact ? 1.8 : 2.5)))
        }
    }
}
