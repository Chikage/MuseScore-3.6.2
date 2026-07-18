// QtQuick 1 was removed in Qt 6.  QtQuick 2.0 is available in both the
// Qt 5 and Qt 6 runtimes used by MuseScore and provides the same primitives
// used by this small effect panel.
import QtQuick 2.0

Rectangle {
    id: screen
    width: 642
    height: 77
    border.width: 1
    border.color: "white"
    radius: 5
    color: "#3f3f3f"
    // Rectangle.smooth was a QtQuick 1 property; QtQuick 2 uses
    // antialiasing for rounded rectangle edges.
    antialiasing: true

    signal valueChanged(string name, real val)

    function updateValues() {
        }
    Text {
        anchors.centerIn: parent
        text: "Freeverb (under construction)"
        color: "white"
        }
    }
