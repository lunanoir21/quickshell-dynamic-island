import QtQuick
import Quickshell

Variants {
    model: Quickshell.screens

    delegate: Component {
        DynamicIsland {
            required property var modelData
            screen: modelData
        }
    }
}
