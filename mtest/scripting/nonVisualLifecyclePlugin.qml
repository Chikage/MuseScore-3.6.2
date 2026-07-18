import QtQuick 2.0
import MuseScore 3.0

MuseScore {
    menuPath: "Plugins.nonVisualLifecycleTest"
    requiresScore: false

    onRun: {
        openLog(filePath + "/nonVisualLifecyclePlugin.log")
        logn("run")
        Qt.quit()
        }

    onScoreStateChanged: logn("endCmd")

    Component.onDestruction: {
        logn("destroyed")
        closeLog()
        }
    }
