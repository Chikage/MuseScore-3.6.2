#=============================================================================
#  Mscore
#  Linux Music Score Editor
#
#  Copyright (C) 2002-2006 by Werner Schweer and others
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#=============================================================================

subdirs(templates wallpaper locale styles sound manual
   workspaces instruments tours)

install (DIRECTORY
      plugins
      DESTINATION ${Mscore_SHARE_NAME}${Mscore_INSTALL_NAME}
      PATTERN ".*" EXCLUDE
      )

if(MSCORE_QT_MAJOR_VERSION EQUAL 6)
      set(_musescore_bundle_xen_tuner_default ON)
else()
      set(_musescore_bundle_xen_tuner_default OFF)
endif()
option(MUSESCORE_BUNDLE_XEN_TUNER
      "Bundle the vendored Xen Tuner plugin runtime"
      ${_musescore_bundle_xen_tuner_default})
unset(_musescore_bundle_xen_tuner_default)
set(MUSESCORE_XEN_TUNER_SOURCE_DIR "" CACHE PATH
    "Optional alternate ordinary Xen Tuner source directory")

if(MUSESCORE_BUNDLE_XEN_TUNER)
      set(MUSESCORE_ROOT_DIR "${PROJECT_SOURCE_DIR}")
      set(MUSESCORE_XEN_TUNER_STAGE_DIR
          "${CMAKE_CURRENT_BINARY_DIR}/xen-tuner-runtime")
      include("${PROJECT_SOURCE_DIR}/buildscripts/xen_tuner/StageXenTuner.cmake")

      # The staging directory contains only the reviewed runtime allowlist and
      # the upstream license, so the install step cannot accidentally package
      # development tools or nested repository metadata.
      set(_musescore_xen_tuner_install_destination
          "${Mscore_SHARE_NAME}${Mscore_INSTALL_NAME}plugins/musescore-xen-tuner")
      install(CODE
            "file(REMOVE_RECURSE \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/${_musescore_xen_tuner_install_destination}\")"
            )
      install(DIRECTORY "${MUSESCORE_XEN_TUNER_STAGE_DIR}/"
            DESTINATION "${_musescore_xen_tuner_install_destination}"
            USE_SOURCE_PERMISSIONS
            )
      install(FILES "${MUSESCORE_XEN_TUNER_STAGE_DIR}.manifest"
            DESTINATION "${Mscore_SHARE_NAME}${Mscore_INSTALL_NAME}plugins"
            RENAME "musescore-xen-tuner.runtime.manifest"
            )
      unset(_musescore_xen_tuner_install_destination)
endif()
