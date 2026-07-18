#=============================================================================
#  Qt discovery shared by the Qt 5 transition build and the Qt 6 port.
#=============================================================================

set(MSCORE_QT_MAJOR_VERSION "5" CACHE STRING "Qt major version used to build MuseScore (5 or 6)")
set_property(CACHE MSCORE_QT_MAJOR_VERSION PROPERTY STRINGS 5 6)

if(NOT MSCORE_QT_MAJOR_VERSION MATCHES "^[56]$")
    message(FATAL_ERROR "MSCORE_QT_MAJOR_VERSION must be either 5 or 6")
endif()

set(QT_VERSION_MAJOR "${MSCORE_QT_MAJOR_VERSION}")
set(QT_PACKAGE "Qt${QT_VERSION_MAJOR}")
set(QT_TARGET_PREFIX "${QT_PACKAGE}")
set(QT_DLL_PREFIX "Qt${QT_VERSION_MAJOR}")

set(_qt_components
    Core
    Gui
    Network
    Test
    Qml
    Quick
    QuickControls2
    QuickWidgets
    Xml
    Svg
    Sql
    Widgets
    PrintSupport
    Concurrent
    OpenGL
    LinguistTools
    Help
)

if(QT_VERSION_MAJOR EQUAL 5)
    list(APPEND _qt_components QuickTemplates2 XmlPatterns)
    if(WIN32)
        list(APPEND _qt_components WinExtras)
    endif()
    set(_qt_min_version "${QT_MIN_VERSION}")
else()
    # QtXmlPatterns and QtWinExtras were removed in Qt 6. QuickTemplates2 is
    # an implementation dependency of QuickControls2 and need not be linked
    # directly. Core5Compat is temporary while the source port is in progress.
    list(APPEND _qt_components Core5Compat StateMachine)
    set(_qt_min_version "6.5.0")
endif()

# Prefer the Qt installation selected by its qmake. This preserves the old
# build behavior on systems that have multiple Qt installations, while still
# using modern CONFIG-mode CMake packages below.
if(QT_VERSION_MAJOR EQUAL 6)
    set(_qt_qmake_names qmake6 qt6-qmake qmake)
else()
    set(_qt_qmake_names qmake qmake-qt5)
endif()

# A build directory may be reused while switching Qt majors. Discard a cached
# qmake from the other major so find_program() can search the updated PATH.
if(QT_QMAKE_EXECUTABLE)
    execute_process(
        COMMAND ${QT_QMAKE_EXECUTABLE} -query QT_VERSION
        RESULT_VARIABLE _cached_qmake_result
        OUTPUT_VARIABLE _cached_qmake_version
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(NOT _cached_qmake_result EQUAL 0 OR NOT _cached_qmake_version MATCHES "^${QT_VERSION_MAJOR}\\.")
        unset(QT_QMAKE_EXECUTABLE CACHE)
        unset(QT_QMAKE_EXECUTABLE)
    endif()
endif()

find_program(QT_QMAKE_EXECUTABLE NAMES ${_qt_qmake_names})
if(NOT QT_QMAKE_EXECUTABLE)
    message(FATAL_ERROR "Could not find qmake for Qt ${QT_VERSION_MAJOR}; set CMAKE_PREFIX_PATH or add the Qt bin directory to PATH")
endif()

execute_process(
    COMMAND ${QT_QMAKE_EXECUTABLE} -query QT_VERSION
    RESULT_VARIABLE _qt_version_result
    OUTPUT_VARIABLE _qmake_qt_version
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT _qt_version_result EQUAL 0 OR NOT _qmake_qt_version MATCHES "^${QT_VERSION_MAJOR}\\.")
    message(FATAL_ERROR
        "${QT_QMAKE_EXECUTABLE} does not provide the requested Qt ${QT_VERSION_MAJOR} "
        "(reported version: ${_qmake_qt_version}). Set QT_QMAKE_EXECUTABLE or adjust PATH."
    )
endif()

execute_process(
    COMMAND ${QT_QMAKE_EXECUTABLE} -query QT_INSTALL_PREFIX
    RESULT_VARIABLE _qt_prefix_result
    OUTPUT_VARIABLE QT_INSTALL_PREFIX
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(_qt_prefix_result EQUAL 0 AND QT_INSTALL_PREFIX)
    list(PREPEND CMAKE_PREFIX_PATH "${QT_INSTALL_PREFIX}")
    set(${QT_PACKAGE}_DIR "${QT_INSTALL_PREFIX}/lib/cmake/${QT_PACKAGE}" CACHE PATH "${QT_PACKAGE} CMake package directory" FORCE)
    foreach(_component IN LISTS _qt_components)
        if(EXISTS "${QT_INSTALL_PREFIX}/lib/cmake/${QT_PACKAGE}${_component}/${QT_PACKAGE}${_component}Config.cmake")
            set(${QT_PACKAGE}${_component}_DIR
                "${QT_INSTALL_PREFIX}/lib/cmake/${QT_PACKAGE}${_component}"
                CACHE PATH "${QT_PACKAGE} ${_component} CMake package directory" FORCE)
        endif()
    endforeach()
endif()

find_package(${QT_PACKAGE} ${_qt_min_version} REQUIRED CONFIG COMPONENTS ${_qt_components})

set(MUSESCORE_QT_WEBENGINE_FOUND FALSE)
if(USE_WEBENGINE)
    if(QT_VERSION_MAJOR EQUAL 5)
        set(_qt_webengine_components WebEngine WebEngineCore WebEngineWidgets)
    else()
        set(_qt_webengine_components WebEngineCore WebEngineWidgets)
    endif()

    find_package(${QT_PACKAGE} ${_qt_min_version} QUIET CONFIG COMPONENTS ${_qt_webengine_components})
    set(MUSESCORE_QT_WEBENGINE_FOUND TRUE)
    foreach(_component IN LISTS _qt_webengine_components)
        if(NOT TARGET ${QT_TARGET_PREFIX}::${_component})
            set(MUSESCORE_QT_WEBENGINE_FOUND FALSE)
        endif()
    endforeach()

    if(MUSESCORE_QT_WEBENGINE_FOUND)
        list(APPEND _qt_components ${_qt_webengine_components})
    endif()
endif()

set(QT_LIBRARIES "")
set(QT_INCLUDES "")
foreach(_component IN LISTS _qt_components)
    if(TARGET ${QT_TARGET_PREFIX}::${_component})
        list(APPEND QT_LIBRARIES ${QT_TARGET_PREFIX}::${_component})

        set(_component_variable_prefix "${QT_PACKAGE}${_component}")
        if(QT_VERSION_MAJOR EQUAL 6)
            get_target_property(_component_include_dirs
                ${QT_TARGET_PREFIX}::${_component}
                INTERFACE_INCLUDE_DIRECTORIES
            )
            foreach(_include_dir IN LISTS _component_include_dirs)
                if(_include_dir AND NOT _include_dir MATCHES "^\\$<")
                    list(APPEND QT_INCLUDES "${_include_dir}")
                endif()
            endforeach()
        else()
            list(APPEND QT_INCLUDES ${${_component_variable_prefix}_INCLUDE_DIRS})
        endif()
        # Qt 6 component definition variables contain generator expressions
        # intended for target properties. Feeding them to add_definitions()
        # writes the unevaluated expressions into every C and C++ command.
        # Imported Qt 6 targets already propagate their required definitions.
        if(QT_VERSION_MAJOR EQUAL 5)
            add_definitions(${${_component_variable_prefix}_DEFINITIONS})
        endif()
    endif()
endforeach()
list(REMOVE_DUPLICATES QT_LIBRARIES)
if(QT_VERSION_MAJOR EQUAL 6 AND EXISTS "${QT_INSTALL_PREFIX}/include")
    # Some Qt 6 framework headers include non-framework helper modules such
    # as QtQmlIntegration. Imported targets propagate those transitively, but
    # the legacy shared-PCH custom command needs the common include root.
    list(APPEND QT_INCLUDES "${QT_INSTALL_PREFIX}/include")
endif()
list(FILTER QT_INCLUDES EXCLUDE REGEX "^$")
list(FILTER QT_INCLUDES EXCLUDE REGEX "^\\$<")
list(REMOVE_DUPLICATES QT_INCLUDES)

set(QT_VERSION "${${QT_PACKAGE}Core_VERSION}")
set(QT_WIDGETS_VERSION "${${QT_PACKAGE}Widgets_VERSION}")

if(NOT QT_QMAKE_EXECUTABLE AND TARGET ${QT_TARGET_PREFIX}::qmake)
    get_target_property(QT_QMAKE_EXECUTABLE ${QT_TARGET_PREFIX}::qmake IMPORTED_LOCATION)
endif()
if(NOT QT_QMAKE_EXECUTABLE)
    if(QT_VERSION_MAJOR EQUAL 6)
        find_program(QT_QMAKE_EXECUTABLE NAMES qmake6 qmake qt6-qmake REQUIRED)
    else()
        find_program(QT_QMAKE_EXECUTABLE NAMES qmake qmake-qt5 REQUIRED)
    endif()
endif()

set(_qmake_vars
    QT_INSTALL_ARCHDATA
    QT_INSTALL_BINS
    QT_INSTALL_CONFIGURATION
    QT_INSTALL_DATA
    QT_INSTALL_DOCS
    QT_INSTALL_EXAMPLES
    QT_INSTALL_HEADERS
    QT_INSTALL_IMPORTS
    QT_INSTALL_LIBEXECS
    QT_INSTALL_LIBS
    QT_INSTALL_PLUGINS
    QT_INSTALL_PREFIX
    QT_INSTALL_QML
    QT_INSTALL_TESTS
    QT_INSTALL_TRANSLATIONS
)
foreach(_var IN LISTS _qmake_vars)
    execute_process(
        COMMAND ${QT_QMAKE_EXECUTABLE} -query ${_var}
        RESULT_VARIABLE _return_val
        OUTPUT_VARIABLE _out
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(_return_val EQUAL 0)
        set(${_var} "${_out}")
    endif()
endforeach()

set(QT_LUPDATE_TARGET ${QT_TARGET_PREFIX}::lupdate)
set(QT_LRELEASE_TARGET ${QT_TARGET_PREFIX}::lrelease)
if(QT_VERSION_MAJOR EQUAL 6)
    set(QT_QCOLLECTIONGENERATOR_TARGET ${QT_TARGET_PREFIX}::qhelpgenerator)
else()
    set(QT_QCOLLECTIONGENERATOR_TARGET ${QT_TARGET_PREFIX}::qcollectiongenerator)
endif()

macro(mscore_qt_wrap_ui outfiles)
    if(QT_VERSION_MAJOR EQUAL 6)
        qt6_wrap_ui(${outfiles} ${ARGN})
    else()
        qt5_wrap_ui(${outfiles} ${ARGN})
    endif()
endmacro()

macro(mscore_qt_add_resources outfiles)
    if(QT_VERSION_MAJOR EQUAL 6)
        qt6_add_resources(${outfiles} ${ARGN})
    else()
        qt5_add_resources(${outfiles} ${ARGN})
    endif()
endmacro()

include_directories(${QT_INCLUDES})

message(STATUS "Using Qt ${QT_VERSION} from ${QT_INSTALL_PREFIX}")
