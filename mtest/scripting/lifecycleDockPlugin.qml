import QtQuick 2.0
import MuseScore 3.0

MuseScore {
    menuPath: "Plugins.lifecycleDockTest"
    pluginType: "dock"
    dockArea: "right"
    requiresScore: false

    implicitWidth: 160
    implicitHeight: 90

    property bool pluginLifecycleTestFixture: true

    onRun: {}
    }
