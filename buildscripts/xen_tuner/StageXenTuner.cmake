# Stage the vendored Xen Tuner runtime from the MuseScore source tree while
# keeping development tools, documentation, tests, and the MuseScore 4 entry
# point out of the application package.

if(NOT DEFINED MUSESCORE_ROOT_DIR OR MUSESCORE_ROOT_DIR STREQUAL "")
      get_filename_component(MUSESCORE_ROOT_DIR
            "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
endif()

if(NOT DEFINED MUSESCORE_XEN_TUNER_SOURCE_DIR
      OR MUSESCORE_XEN_TUNER_SOURCE_DIR STREQUAL "")
      set(MUSESCORE_XEN_TUNER_SOURCE_DIR
          "${MUSESCORE_ROOT_DIR}/plugins/musescore-xen-tuner")
endif()
get_filename_component(MUSESCORE_XEN_TUNER_SOURCE_DIR
      "${MUSESCORE_XEN_TUNER_SOURCE_DIR}" ABSOLUTE)

if(NOT DEFINED MUSESCORE_XEN_TUNER_STAGE_DIR
      OR MUSESCORE_XEN_TUNER_STAGE_DIR STREQUAL "")
      set(MUSESCORE_XEN_TUNER_STAGE_DIR
          "${CMAKE_BINARY_DIR}/xen-tuner-runtime")
endif()
get_filename_component(MUSESCORE_XEN_TUNER_STAGE_DIR
      "${MUSESCORE_XEN_TUNER_STAGE_DIR}" ABSOLUTE)

set(_xen_tuner_manifest "${MUSESCORE_XEN_TUNER_STAGE_DIR}.manifest")

if(NOT IS_DIRECTORY "${MUSESCORE_XEN_TUNER_SOURCE_DIR}")
      message(FATAL_ERROR
          "The vendored Xen Tuner source directory is missing:\n"
          "  ${MUSESCORE_XEN_TUNER_SOURCE_DIR}\n\n"
          "Restore plugins/musescore-xen-tuner from the MuseScore source "
          "tree, or configure with "
          "-DMUSESCORE_XEN_TUNER_SOURCE_DIR=<ordinary source directory>.\n"
          "To intentionally omit the plugin, configure with "
          "-DMUSESCORE_BUNDLE_XEN_TUNER=OFF.")
endif()

if(MUSESCORE_XEN_TUNER_SOURCE_DIR STREQUAL MUSESCORE_XEN_TUNER_STAGE_DIR)
      message(FATAL_ERROR
          "The Xen Tuner source and staging directories must be different: "
          "${MUSESCORE_XEN_TUNER_SOURCE_DIR}")
endif()

# Remove outputs from both the current vendored staging flow and the former
# Git archive/overlay flow so an existing build directory cannot retain stale
# runtime files.
file(REMOVE_RECURSE
      "${MUSESCORE_XEN_TUNER_STAGE_DIR}"
      "${MUSESCORE_XEN_TUNER_STAGE_DIR}.source")
file(REMOVE
      "${MUSESCORE_XEN_TUNER_STAGE_DIR}.tar"
      "${_xen_tuner_manifest}")

# Explicit runtime allowlist. Documentation, generators, development tools,
# tests, and the MuseScore 4 entry point stay out of the application package.
set(_xen_tuner_runtime_files
      "LICENSE"
      "xen-tuner.config.json"
      "Xen Tuner/calc steps.qml"
      "Xen Tuner/clear tuning cache.qml"
      "Xen Tuner/display cents.qml"
      "Xen Tuner/display steps.qml"
      "Xen Tuner/export midi csv.qml"
      "Xen Tuner/export midx.qml"
      "Xen Tuner/midx_pitch_bend_converter.py"
      "Xen Tuner/midx_powershell_writer.ps1"
      "Xen Tuner/midx_python_writer.py"
      "Xen Tuner/midx_shell_writer.sh"
      "Xen Tuner/xen tuner.qml"
      "Xen Tuner/runtime/fns.js"
      "Xen Tuner/runtime/fns.ms.js"
      "Xen Tuner/runtime/modules/00-runtime.js"
      "Xen Tuner/runtime/modules/01-lifecycle-cache.js"
      "Xen Tuner/runtime/modules/02-symbols-and-notes.js"
      "Xen Tuner/runtime/modules/03-config-parser.js"
      "Xen Tuner/runtime/modules/04-note-tuning.js"
      "Xen Tuner/runtime/modules/05-score-navigation.js"
      "Xen Tuner/runtime/modules/06-note-editing.js"
      "Xen Tuner/runtime/modules/07-layout-display.js"
      "Xen Tuner/runtime/modules/08-operations.js"
      "Xen Tuner/runtime/tables/generated-tables.js"
      "Xen Tuner/runtime/tables/lookup-tables.js"
      )

if(CMAKE_SCRIPT_MODE_FILE)
      file(GLOB_RECURSE _xen_tuner_key_signature_files
            RELATIVE "${MUSESCORE_XEN_TUNER_SOURCE_DIR}"
            "${MUSESCORE_XEN_TUNER_SOURCE_DIR}/Key Signature/*.json")
      file(GLOB_RECURSE _xen_tuner_tuning_files
            RELATIVE "${MUSESCORE_XEN_TUNER_SOURCE_DIR}"
            "${MUSESCORE_XEN_TUNER_SOURCE_DIR}/tunings/*.json"
            "${MUSESCORE_XEN_TUNER_SOURCE_DIR}/tunings/*.txt")
else()
      file(GLOB_RECURSE _xen_tuner_key_signature_files CONFIGURE_DEPENDS
            RELATIVE "${MUSESCORE_XEN_TUNER_SOURCE_DIR}"
            "${MUSESCORE_XEN_TUNER_SOURCE_DIR}/Key Signature/*.json")
      file(GLOB_RECURSE _xen_tuner_tuning_files CONFIGURE_DEPENDS
            RELATIVE "${MUSESCORE_XEN_TUNER_SOURCE_DIR}"
            "${MUSESCORE_XEN_TUNER_SOURCE_DIR}/tunings/*.json"
            "${MUSESCORE_XEN_TUNER_SOURCE_DIR}/tunings/*.txt")
endif()

list(FILTER _xen_tuner_key_signature_files EXCLUDE
     REGEX "^Key Signature/testks\\.json$")
list(FILTER _xen_tuner_tuning_files EXCLUDE REGEX "^tunings/test/")
list(APPEND _xen_tuner_runtime_files
     ${_xen_tuner_key_signature_files} ${_xen_tuner_tuning_files})
list(REMOVE_DUPLICATES _xen_tuner_runtime_files)
list(SORT _xen_tuner_runtime_files)

file(MAKE_DIRECTORY "${MUSESCORE_XEN_TUNER_STAGE_DIR}")
set(_xen_tuner_manifest_content "")
set(_xen_tuner_source_dependencies "")
foreach(_xen_tuner_relative_path IN LISTS _xen_tuner_runtime_files)
      set(_xen_tuner_source_path
          "${MUSESCORE_XEN_TUNER_SOURCE_DIR}/${_xen_tuner_relative_path}")
      if(NOT EXISTS "${_xen_tuner_source_path}"
            OR IS_DIRECTORY "${_xen_tuner_source_path}")
            message(FATAL_ERROR
                "Vendored Xen Tuner runtime file is missing: "
                "${_xen_tuner_relative_path}")
      endif()

      get_filename_component(_xen_tuner_relative_dir
            "${_xen_tuner_relative_path}" DIRECTORY)
      if(_xen_tuner_relative_dir STREQUAL "")
            set(_xen_tuner_destination_dir
                "${MUSESCORE_XEN_TUNER_STAGE_DIR}")
      else()
            set(_xen_tuner_destination_dir
                "${MUSESCORE_XEN_TUNER_STAGE_DIR}/${_xen_tuner_relative_dir}")
      endif()
      file(MAKE_DIRECTORY "${_xen_tuner_destination_dir}")
      file(COPY "${_xen_tuner_source_path}"
           DESTINATION "${_xen_tuner_destination_dir}")

      file(SHA256 "${_xen_tuner_source_path}" _xen_tuner_file_sha256)
      string(APPEND _xen_tuner_manifest_content
             "${_xen_tuner_file_sha256}  ${_xen_tuner_relative_path}\n")
      list(APPEND _xen_tuner_source_dependencies "${_xen_tuner_source_path}")
endforeach()

# Content changes to vendored files must restage the runtime even when the file
# list itself is unchanged. CONFIGURE_DEPENDS above separately covers added or
# removed tuning/key-signature files.
if(NOT CMAKE_SCRIPT_MODE_FILE)
      set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
            ${_xen_tuner_source_dependencies})
endif()

file(WRITE "${_xen_tuner_manifest}" "${_xen_tuner_manifest_content}")
string(SHA256 _xen_tuner_runtime_sha256 "${_xen_tuner_manifest_content}")
list(LENGTH _xen_tuner_runtime_files _xen_tuner_runtime_file_count)

message(STATUS
    "Staged vendored Xen Tuner runtime: ${_xen_tuner_runtime_file_count} files "
    "(manifest SHA256 ${_xen_tuner_runtime_sha256})")
