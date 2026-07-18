get_filename_component(DIR_NAME ${CMAKE_CURRENT_SOURCE_DIR} NAME)
message("Configuring " ${DIR_NAME})

set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

set(LIBRARY_TYPE STATIC)
if (DYNAMIC_LINKING)
    set(LIBRARY_TYPE SHARED)
endif ()

file(GLOB_RECURSE qt-google-analytics_SOURCES RELATIVE ${CMAKE_CURRENT_LIST_DIR} *.cpp)
file(GLOB_RECURSE qt-google-analytics_HEADERS RELATIVE ${CMAKE_CURRENT_LIST_DIR} *.h)

add_library(qt-google-analytics ${LIBRARY_TYPE} ${qt-google-analytics_SOURCES} ${qt-google-analytics_HEADERS})
target_link_libraries(qt-google-analytics
    ${QT_TARGET_PREFIX}::Core
    ${QT_TARGET_PREFIX}::Network
    ${QT_TARGET_PREFIX}::Qml
)

if (MSVC)
  set_target_properties( qt-google-analytics PROPERTIES
    COMPILE_FLAGS "/wd4127 /wd4458 /wd4996"
  )
else (MSVC)
    if (MINGW OR APPLE)
        set_target_properties( qt-google-analytics PROPERTIES
          COMPILE_FLAGS "-Wno-deprecated-declarations"
        )
    endif (MINGW OR APPLE)

endif (MSVC)
