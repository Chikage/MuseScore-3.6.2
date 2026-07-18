import QtQuick 2.0
import MuseScore 3.0

MuseScore {
    menuPath: "Plugins.visualPlugin"
    pluginType: "dock"
    requiresScore: false

    property int completedCount: 0

    Component.onCompleted: completedCount += 1
}
