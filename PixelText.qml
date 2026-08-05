import QtQuick
import "pixelfont.js" as PixelFont

// Draws text as a grid of hard-edged squares. A Canvas is used rather than a
// Repeater of Rectangles because a single line of the date already needs a few
// hundred cells, and hundreds of scene-graph nodes per label is a real cost for
// something that only redraws once a second.
Item {
    id: root

    property string text: ""
    // Size of one lit pixel and the dead space around it. Keeping them separate
    // is what gives the glyphs their visible grid.
    property real cell: 3
    property real gap: 1
    property color color: "#f2f2f2"
    // When set, the unlit pixels of the glyph box are drawn faintly, which reads
    // as a dormant LED matrix behind the digits.
    property color offColor: "transparent"
    property int tracking: 1
    property bool animated: false
    property int rollDuration: 320

    readonly property real step: cell + gap
    readonly property int rowCount: PixelFont.ROWS

    // Text currently drawn at rest. During a roll it holds the outgoing string
    // while `text` holds the incoming one.
    property string shownText: ""
    property string rollTarget: ""
    property real rollPhase: 1

    implicitWidth: Math.max(1, PixelFont.columns(text, tracking) * step - gap)
    implicitHeight: rowCount * step - gap

    onTextChanged: {
        if (!animated || shownText === "") {
            rollAnimation.stop()
            shownText = text
            rollPhase = 1
            canvas.requestPaint()
            return
        }
        if (shownText === text) return
        // A change arriving mid-roll settles the previous one instantly, so the
        // outgoing glyph is never two generations stale.
        if (rollAnimation.running) {
            rollAnimation.stop()
            shownText = rollTarget
        }
        rollTarget = text
        rollPhase = 0
        rollAnimation.start()
    }

    onRollPhaseChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onOffColorChanged: canvas.requestPaint()
    onCellChanged: canvas.requestPaint()
    onGapChanged: canvas.requestPaint()

    NumberAnimation {
        id: rollAnimation
        target: root
        property: "rollPhase"
        from: 0
        to: 1
        duration: root.rollDuration
        easing.type: Easing.OutCubic
        onFinished: root.shownText = root.rollTarget
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            let ctx = getContext("2d")
            ctx.reset()

            let step = root.step
            let cell = root.cell
            let boxHeight = root.rowCount * step
            let incoming = root.text
            let outgoing = root.shownText
            let phase = root.rollPhase
            let showOff = root.offColor.a > 0

            // Snapping the offset to whole rows keeps every pixel on the grid
            // during the roll, so the transition still looks like a pixel
            // display rather than a smoothly sliding bitmap.
            let shift = Math.round(phase * root.rowCount) * step
            let x = 0

            for (let i = 0; i < incoming.length; i++) {
                let ch = incoming.charAt(i)
                let glyph = PixelFont.glyph(ch)
                let cols = glyph[0].length
                let previous = i < outgoing.length ? outgoing.charAt(i) : ch

                if (showOff) {
                    ctx.fillStyle = root.offColor
                    for (let r = 0; r < root.rowCount; r++)
                        for (let c = 0; c < cols; c++)
                            ctx.fillRect(x + c * step, r * step, cell, cell)
                }

                ctx.fillStyle = root.color
                if (phase >= 1 || previous === ch) {
                    paintGlyph(ctx, glyph, x, 0, step, cell)
                } else {
                    ctx.save()
                    ctx.beginPath()
                    ctx.rect(x - 1, -1, cols * step + 2, boxHeight + 2)
                    ctx.clip()
                    paintGlyph(ctx, PixelFont.glyph(previous), x, -shift, step, cell)
                    paintGlyph(ctx, glyph, x, boxHeight - shift, step, cell)
                    ctx.restore()
                }

                x += (cols + root.tracking) * step
            }
        }

        function paintGlyph(ctx, glyph, x, y, step, cell) {
            for (let r = 0; r < glyph.length; r++) {
                let row = glyph[r]
                for (let c = 0; c < row.length; c++)
                    if (row.charAt(c) === "1")
                        ctx.fillRect(x + c * step, y + r * step, cell, cell)
            }
        }
    }
}
