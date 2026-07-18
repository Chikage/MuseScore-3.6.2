#=============================================================================
#  MuseScore
#  Music Composition & Notation
#
#  Copyright (C) 2011 Werner Schweer
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2
#  as published by the Free Software Foundation and appearing in
#  the file LICENSE.GPL
#=============================================================================

set(TARGET tst_scripting)

set(MTEST_LINK_MSCOREAPP TRUE)

include(${PROJECT_SOURCE_DIR}/mtest/cmake.inc)

if (MSVC OR MINGW)
      get_target_property(
            MTEST_INSTALL_DESTINATION_DIR
            ${TARGET}
            MTEST_INSTALL_DESTINATION_DIR
            )
      install(DIRECTORY
            ${QT_INSTALL_QML}
            DESTINATION "${MTEST_INSTALL_DESTINATION_DIR}"
            REGEX ".*d\\.dll" EXCLUDE
            REGEX ".*QtMultimedia.*" EXCLUDE
            REGEX ".*QtSensors.*" EXCLUDE
            REGEX ".*QtTest.*" EXCLUDE
            REGEX ".*QtWebkit.*" EXCLUDE
            )
endif (MSVC OR MINGW)

# Full-application plugin lifecycle coverage is kept in a separate process.
# The regular scripting tests use MTest's lightweight MuseScoreCore fixture,
# which cannot exercise MuseScore::loadPlugin() or unloadPlugins().
set(TARGET tst_pluginlifecycle)

include(${PROJECT_SOURCE_DIR}/mtest/cmake.inc)

# Both scripting executables write QtTest XML to "result.xml". Give the
# lifecycle test its own CTest working directory so parallel test execution
# cannot make the two processes overwrite each other's report.
set(PLUGIN_LIFECYCLE_TEST_WORKING_DIR
      "${CMAKE_CURRENT_BINARY_DIR}/pluginlifecycle-results")
file(MAKE_DIRECTORY "${PLUGIN_LIFECYCLE_TEST_WORKING_DIR}")
set_tests_properties(${TARGET} PROPERTIES
      WORKING_DIRECTORY "${PLUGIN_LIFECYCLE_TEST_WORKING_DIR}")

# Both executables live in this source directory and cmake.inc writes the
# QtTest XML report as result.xml. Keep parallel CTest runs from racing on the
# same output file.
set(PLUGIN_LIFECYCLE_TEST_WORK_DIR "${CMAKE_CURRENT_BINARY_DIR}/pluginlifecycle-results")
file(MAKE_DIRECTORY "${PLUGIN_LIFECYCLE_TEST_WORK_DIR}")
set_tests_properties(tst_pluginlifecycle PROPERTIES
      WORKING_DIRECTORY "${PLUGIN_LIFECYCLE_TEST_WORK_DIR}"
      )
