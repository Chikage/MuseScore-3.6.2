# Stage the pinned Xen Tuner runtime without copying the external repository
# into the MuseScore source tree or install image wholesale.

set(MUSESCORE_XEN_TUNER_REVISION
    "ebbeb1763af3a4bb4562e1a653731d19dfe6bfab")
set(MUSESCORE_XEN_TUNER_RUNTIME_SHA256
    "d77988216bc16a7f16fab8b6de9f441c7373133c43172588dc4f12e541159f64")

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

set(_xen_tuner_patch
    "${MUSESCORE_ROOT_DIR}/buildscripts/xen_tuner/qt6-runtime.patch")
set(_xen_tuner_export_dir "${MUSESCORE_XEN_TUNER_STAGE_DIR}.source")
get_filename_component(_xen_tuner_export_parent
      "${_xen_tuner_export_dir}" DIRECTORY)
set(_xen_tuner_archive "${MUSESCORE_XEN_TUNER_STAGE_DIR}.tar")
set(_xen_tuner_manifest "${MUSESCORE_XEN_TUNER_STAGE_DIR}.manifest")

if(NOT EXISTS "${MUSESCORE_XEN_TUNER_SOURCE_DIR}/.git")
      message(FATAL_ERROR
          "Xen Tuner is required for the default package, but its pinned source "
          "checkout is unavailable at:\n  ${MUSESCORE_XEN_TUNER_SOURCE_DIR}\n\n"
          "Online checkout:\n"
          "  git submodule update --init --depth 1 plugins/musescore-xen-tuner\n\n"
          "Offline checkout:\n"
          "  configure with -DMUSESCORE_XEN_TUNER_SOURCE_DIR=<local git checkout>\n"
          "The local checkout must contain commit ${MUSESCORE_XEN_TUNER_REVISION}.\n"
          "To intentionally omit the plugin, configure with "
          "-DMUSESCORE_BUNDLE_XEN_TUNER=OFF.")
endif()

find_package(Git QUIET)
if(NOT GIT_FOUND)
      message(FATAL_ERROR
          "Git is required to export and verify pinned Xen Tuner commit "
          "${MUSESCORE_XEN_TUNER_REVISION}.")
endif()

execute_process(
      COMMAND "${GIT_EXECUTABLE}" -C "${MUSESCORE_XEN_TUNER_SOURCE_DIR}"
              cat-file -e "${MUSESCORE_XEN_TUNER_REVISION}^{commit}"
      RESULT_VARIABLE _xen_tuner_commit_result
      ERROR_VARIABLE _xen_tuner_commit_error
      )
if(NOT _xen_tuner_commit_result EQUAL 0)
      string(STRIP "${_xen_tuner_commit_error}" _xen_tuner_commit_error)
      message(FATAL_ERROR
          "The Xen Tuner source checkout does not contain pinned commit "
          "${MUSESCORE_XEN_TUNER_REVISION}.\n"
          "Checkout: ${MUSESCORE_XEN_TUNER_SOURCE_DIR}\n"
          "Git error: ${_xen_tuner_commit_error}\n"
          "Fetch that commit while online, or point "
          "MUSESCORE_XEN_TUNER_SOURCE_DIR at an offline checkout containing it.")
endif()

# Export the pinned commit rather than the worktree. This deliberately preserves
# local edits in the nested repository while producing deterministic input.
file(REMOVE_RECURSE "${_xen_tuner_export_dir}" "${MUSESCORE_XEN_TUNER_STAGE_DIR}")
file(REMOVE "${_xen_tuner_archive}" "${_xen_tuner_manifest}")
file(MAKE_DIRECTORY "${_xen_tuner_export_dir}")

execute_process(
      COMMAND "${GIT_EXECUTABLE}" -C "${MUSESCORE_XEN_TUNER_SOURCE_DIR}"
              archive --format=tar --output "${_xen_tuner_archive}"
              "${MUSESCORE_XEN_TUNER_REVISION}"
      RESULT_VARIABLE _xen_tuner_archive_result
      ERROR_VARIABLE _xen_tuner_archive_error
      )
if(NOT _xen_tuner_archive_result EQUAL 0)
      string(STRIP "${_xen_tuner_archive_error}" _xen_tuner_archive_error)
      message(FATAL_ERROR "Unable to export pinned Xen Tuner source: "
                          "${_xen_tuner_archive_error}")
endif()

execute_process(
      COMMAND "${CMAKE_COMMAND}" -E tar xf "${_xen_tuner_archive}"
      WORKING_DIRECTORY "${_xen_tuner_export_dir}"
      RESULT_VARIABLE _xen_tuner_extract_result
      ERROR_VARIABLE _xen_tuner_extract_error
      )
if(NOT _xen_tuner_extract_result EQUAL 0)
      string(STRIP "${_xen_tuner_extract_error}" _xen_tuner_extract_error)
      message(FATAL_ERROR "Unable to extract pinned Xen Tuner source: "
                          "${_xen_tuner_extract_error}")
endif()

execute_process(
      # Keep Git from discovering a parent repository when the build directory
      # lives below the MuseScore worktree. Otherwise git apply can skip every
      # path while still reporting success because they are outside its
      # subdirectory prefix.
      COMMAND "${CMAKE_COMMAND}" -E env
              "GIT_CEILING_DIRECTORIES=${_xen_tuner_export_parent}"
              "${GIT_EXECUTABLE}" apply --no-index --check --whitespace=nowarn
              "${_xen_tuner_patch}"
      WORKING_DIRECTORY "${_xen_tuner_export_dir}"
      RESULT_VARIABLE _xen_tuner_patch_check_result
      ERROR_VARIABLE _xen_tuner_patch_check_error
      )
if(NOT _xen_tuner_patch_check_result EQUAL 0)
      string(STRIP "${_xen_tuner_patch_check_error}"
                   _xen_tuner_patch_check_error)
      message(FATAL_ERROR
          "The MuseScore Xen Tuner overlay no longer applies to pinned commit "
          "${MUSESCORE_XEN_TUNER_REVISION}:\n${_xen_tuner_patch_check_error}")
endif()

execute_process(
      COMMAND "${CMAKE_COMMAND}" -E env
              "GIT_CEILING_DIRECTORIES=${_xen_tuner_export_parent}"
              "${GIT_EXECUTABLE}" apply --no-index --whitespace=nowarn
              "${_xen_tuner_patch}"
      WORKING_DIRECTORY "${_xen_tuner_export_dir}"
      RESULT_VARIABLE _xen_tuner_patch_result
      ERROR_VARIABLE _xen_tuner_patch_error
      )
if(NOT _xen_tuner_patch_result EQUAL 0)
      string(STRIP "${_xen_tuner_patch_error}" _xen_tuner_patch_error)
      message(FATAL_ERROR "Unable to apply the MuseScore Xen Tuner overlay: "
                          "${_xen_tuner_patch_error}")
endif()

# Explicit runtime allowlist. Documentation, generators, development tools,
# tests, the MuseScore 4 entry point, and nested repository metadata stay out of
# the application package.
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

file(GLOB_RECURSE _xen_tuner_key_signature_files
      RELATIVE "${_xen_tuner_export_dir}"
      "${_xen_tuner_export_dir}/Key Signature/*.json")
file(GLOB_RECURSE _xen_tuner_tuning_files
      RELATIVE "${_xen_tuner_export_dir}"
      "${_xen_tuner_export_dir}/tunings/*.json"
      "${_xen_tuner_export_dir}/tunings/*.txt")
list(FILTER _xen_tuner_key_signature_files EXCLUDE
     REGEX "^Key Signature/testks\\.json$")
list(FILTER _xen_tuner_tuning_files EXCLUDE REGEX "^tunings/test/")
list(APPEND _xen_tuner_runtime_files
     ${_xen_tuner_key_signature_files} ${_xen_tuner_tuning_files})
list(REMOVE_DUPLICATES _xen_tuner_runtime_files)
list(SORT _xen_tuner_runtime_files)

file(MAKE_DIRECTORY "${MUSESCORE_XEN_TUNER_STAGE_DIR}")
set(_xen_tuner_manifest_content "")
foreach(_xen_tuner_relative_path IN LISTS _xen_tuner_runtime_files)
      set(_xen_tuner_source_path
          "${_xen_tuner_export_dir}/${_xen_tuner_relative_path}")
      if(NOT EXISTS "${_xen_tuner_source_path}")
            message(FATAL_ERROR
                "Pinned Xen Tuner runtime file is missing: "
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
endforeach()

file(WRITE "${_xen_tuner_manifest}" "${_xen_tuner_manifest_content}")
string(SHA256 _xen_tuner_runtime_sha256 "${_xen_tuner_manifest_content}")
if(NOT "${_xen_tuner_runtime_sha256}" STREQUAL
       "${MUSESCORE_XEN_TUNER_RUNTIME_SHA256}")
      message(FATAL_ERROR
          "Pinned Xen Tuner runtime checksum mismatch.\n"
          "Expected: ${MUSESCORE_XEN_TUNER_RUNTIME_SHA256}\n"
          "Actual:   ${_xen_tuner_runtime_sha256}\n"
          "Manifest: ${_xen_tuner_manifest}")
endif()

message(STATUS
    "Staged Xen Tuner ${MUSESCORE_XEN_TUNER_REVISION} "
    "(SHA256 ${_xen_tuner_runtime_sha256})")
