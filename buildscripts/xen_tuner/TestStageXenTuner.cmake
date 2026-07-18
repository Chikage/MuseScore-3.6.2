# Regression-test Xen Tuner staging from an ordinary source directory outside
# the MuseScore repository. This deliberately avoids Git metadata so the
# packaging contract cannot accidentally depend on submodules or git archive.

if(NOT DEFINED MUSESCORE_ROOT_DIR OR MUSESCORE_ROOT_DIR STREQUAL "")
      get_filename_component(MUSESCORE_ROOT_DIR
            "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
endif()
get_filename_component(MUSESCORE_ROOT_DIR "${MUSESCORE_ROOT_DIR}" ABSOLUTE)

if(NOT DEFINED MUSESCORE_XEN_TUNER_SOURCE_DIR
      OR MUSESCORE_XEN_TUNER_SOURCE_DIR STREQUAL "")
      set(MUSESCORE_XEN_TUNER_SOURCE_DIR
          "${MUSESCORE_ROOT_DIR}/plugins/musescore-xen-tuner")
endif()
get_filename_component(MUSESCORE_XEN_TUNER_SOURCE_DIR
      "${MUSESCORE_XEN_TUNER_SOURCE_DIR}" ABSOLUTE)

if(NOT IS_DIRECTORY "${MUSESCORE_XEN_TUNER_SOURCE_DIR}")
      message(FATAL_ERROR
          "Xen Tuner staging regression source is missing: "
          "${MUSESCORE_XEN_TUNER_SOURCE_DIR}")
endif()

if(NOT DEFINED MUSESCORE_XEN_TUNER_TEST_ROOT
      OR MUSESCORE_XEN_TUNER_TEST_ROOT STREQUAL "")
      if(DEFINED ENV{RUNNER_TEMP} AND NOT "$ENV{RUNNER_TEMP}" STREQUAL "")
            set(_xen_tuner_test_base "$ENV{RUNNER_TEMP}")
      elseif(WIN32 AND DEFINED ENV{TEMP} AND NOT "$ENV{TEMP}" STREQUAL "")
            set(_xen_tuner_test_base "$ENV{TEMP}")
      elseif(DEFINED ENV{TMPDIR} AND NOT "$ENV{TMPDIR}" STREQUAL "")
            set(_xen_tuner_test_base "$ENV{TMPDIR}")
      else()
            set(_xen_tuner_test_base "/tmp")
      endif()
      set(MUSESCORE_XEN_TUNER_TEST_ROOT
          "${_xen_tuner_test_base}/musescore-xen-tuner-stage-regression")
endif()
get_filename_component(MUSESCORE_XEN_TUNER_TEST_ROOT
      "${MUSESCORE_XEN_TUNER_TEST_ROOT}" ABSOLUTE)

file(RELATIVE_PATH _xen_tuner_test_root_from_repository
     "${MUSESCORE_ROOT_DIR}" "${MUSESCORE_XEN_TUNER_TEST_ROOT}")
if(NOT _xen_tuner_test_root_from_repository MATCHES "^\\.\\./"
      AND NOT IS_ABSOLUTE "${_xen_tuner_test_root_from_repository}")
      message(FATAL_ERROR
          "The Xen Tuner staging regression directory must be outside the "
          "MuseScore repository: ${MUSESCORE_XEN_TUNER_TEST_ROOT}")
endif()

set(_xen_tuner_stage_script
    "${MUSESCORE_ROOT_DIR}/buildscripts/xen_tuner/StageXenTuner.cmake")
set(_xen_tuner_external_source
    "${MUSESCORE_XEN_TUNER_TEST_ROOT}/ordinary-source/musescore-xen-tuner")
set(_xen_tuner_vendored_stage
    "${MUSESCORE_XEN_TUNER_TEST_ROOT}/vendored-stage")
set(_xen_tuner_external_stage
    "${MUSESCORE_XEN_TUNER_TEST_ROOT}/external-stage")

file(REMOVE_RECURSE "${MUSESCORE_XEN_TUNER_TEST_ROOT}")
file(MAKE_DIRECTORY "${_xen_tuner_external_source}")
file(COPY "${MUSESCORE_XEN_TUNER_SOURCE_DIR}/"
     DESTINATION "${_xen_tuner_external_source}"
     PATTERN ".git" EXCLUDE)
file(REMOVE_RECURSE "${_xen_tuner_external_source}/.git")
if(EXISTS "${_xen_tuner_external_source}/.git")
      message(FATAL_ERROR
          "The ordinary Xen Tuner staging fixture unexpectedly contains .git")
endif()

function(_stage_xen_tuner source_dir stage_dir label)
      execute_process(
            COMMAND "${CMAKE_COMMAND}"
                  "-DMUSESCORE_ROOT_DIR=${MUSESCORE_ROOT_DIR}"
                  "-DMUSESCORE_XEN_TUNER_SOURCE_DIR=${source_dir}"
                  "-DMUSESCORE_XEN_TUNER_STAGE_DIR=${stage_dir}"
                  -P "${_xen_tuner_stage_script}"
            RESULT_VARIABLE _stage_result
            OUTPUT_VARIABLE _stage_stdout
            ERROR_VARIABLE _stage_stderr)
      if(NOT _stage_result EQUAL 0)
            message(FATAL_ERROR
                "Failed to stage the ${label} Xen Tuner source "
                "(exit ${_stage_result}).\n"
                "stdout:\n${_stage_stdout}\n"
                "stderr:\n${_stage_stderr}")
      endif()
endfunction()

function(_collect_stage_hashes stage_dir output_variable)
      file(GLOB_RECURSE _stage_files
            LIST_DIRECTORIES FALSE
            RELATIVE "${stage_dir}"
            "${stage_dir}/*")
      list(SORT _stage_files)
      set(_stage_hashes "")
      foreach(_relative_path IN LISTS _stage_files)
            file(SHA256 "${stage_dir}/${_relative_path}" _file_sha256)
            string(APPEND _stage_hashes
                   "${_file_sha256}  ${_relative_path}\n")
      endforeach()
      set(${output_variable} "${_stage_hashes}" PARENT_SCOPE)
endfunction()

_stage_xen_tuner("${MUSESCORE_XEN_TUNER_SOURCE_DIR}"
                 "${_xen_tuner_vendored_stage}" "selected")
_stage_xen_tuner("${_xen_tuner_external_source}"
                 "${_xen_tuner_external_stage}" "ordinary external")

file(READ "${_xen_tuner_vendored_stage}.manifest"
     _xen_tuner_vendored_manifest)
file(READ "${_xen_tuner_external_stage}.manifest"
     _xen_tuner_external_manifest)
if(NOT _xen_tuner_vendored_manifest STREQUAL _xen_tuner_external_manifest)
      message(FATAL_ERROR
          "Xen Tuner manifests differ between selected and ordinary external "
          "source directories")
endif()

_collect_stage_hashes("${_xen_tuner_vendored_stage}"
                      _xen_tuner_vendored_hashes)
_collect_stage_hashes("${_xen_tuner_external_stage}"
                      _xen_tuner_external_hashes)
if(NOT _xen_tuner_vendored_hashes STREQUAL _xen_tuner_external_hashes)
      message(FATAL_ERROR
          "Xen Tuner staged file trees differ between selected and ordinary "
          "external source directories")
endif()
if(NOT _xen_tuner_vendored_manifest STREQUAL _xen_tuner_vendored_hashes)
      message(FATAL_ERROR
          "Xen Tuner staging manifest does not exactly describe the staged "
          "runtime file tree")
endif()

string(SHA256 _xen_tuner_manifest_sha256
       "${_xen_tuner_vendored_manifest}")
string(REGEX MATCHALL "[^\n]+\n" _xen_tuner_manifest_lines
       "${_xen_tuner_vendored_manifest}")
list(LENGTH _xen_tuner_manifest_lines _xen_tuner_file_count)

file(REMOVE_RECURSE "${MUSESCORE_XEN_TUNER_TEST_ROOT}")
message(STATUS
    "Xen Tuner ordinary-directory staging regression passed: "
    "${_xen_tuner_file_count} files (manifest SHA256 "
    "${_xen_tuner_manifest_sha256})")
