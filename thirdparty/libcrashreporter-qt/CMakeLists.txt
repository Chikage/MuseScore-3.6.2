cmake_minimum_required(VERSION 3.16)
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    project(libcrashreporter-qt LANGUAGES C CXX)
endif()

if(POLICY CMP0071)
    cmake_policy(SET CMP0071 NEW)
endif()

option(ENABLE_GPL_CODE "Enable GPL-licensed depencencies of libcrashreporter-qt (dr.konqui integration)" OFF)
option(ENABLE_CRASH_REPORTER "Enable libcrashreporter-qt GUI component" ON)

if(NOT DEFINED MSCORE_QT_MAJOR_VERSION)
    set(MSCORE_QT_MAJOR_VERSION "5" CACHE STRING "Qt major version used to build libcrashreporter-qt (5 or 6)")
endif()
set(QT_TARGET_PREFIX "Qt${MSCORE_QT_MAJOR_VERSION}")
find_package(${QT_TARGET_PREFIX} REQUIRED CONFIG COMPONENTS Core Network Widgets)

if((CMAKE_COMPILER_IS_GNUCXX AND CMAKE_CXX_FLAGS) OR
   (UNIX AND NOT APPLE AND CMAKE_CXX_COMPILER_ID MATCHES "Clang"))
    # Breakpad uses GNU compiler extensions like typeof.
    # Luckily these features are not used on OSX, so we can build the
    # crashreporter there with the normal C++11 standard.
    string(REPLACE "-std=c++11" "-std=gnu++11" CMAKE_CXX_FLAGS ${CMAKE_CXX_FLAGS})
    string(REPLACE "-std=c++14" "-std=gnu++14" CMAKE_CXX_FLAGS ${CMAKE_CXX_FLAGS})
endif()

if(ENABLE_CRASH_REPORTER)
    add_definitions(-DENABLE_CRASH_REPORTER)
endif(ENABLE_CRASH_REPORTER)

add_subdirectory(3rdparty)
add_subdirectory(src)
