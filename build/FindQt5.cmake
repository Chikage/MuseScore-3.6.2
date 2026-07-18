# Compatibility wrapper for external build scripts that still include
# FindQt5.cmake directly.
set(MSCORE_QT_MAJOR_VERSION 5 CACHE STRING "Qt major version used to build MuseScore" FORCE)
include(${CMAKE_CURRENT_LIST_DIR}/FindQt.cmake)
