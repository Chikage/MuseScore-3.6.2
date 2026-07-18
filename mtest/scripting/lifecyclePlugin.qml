import QtQuick 2.0
import MuseScore 3.0

MuseScore {
    menuPath: "Plugins.lifecycleTest"
    pluginType: "dialog"
    requiresScore: false

    width: 160
    height: 90

    property bool pluginLifecycleTestFixture: true

    onRun: {}

    function requestQuit() {
        Qt.quit()
        }
    }
