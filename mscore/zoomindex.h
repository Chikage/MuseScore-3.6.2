//=============================================================================
//  MuseScore
//  Music Composition & Notation
//=============================================================================

#ifndef MSCORE_ZOOMINDEX_H
#define MSCORE_ZOOMINDEX_H

#include <QMetaType>

namespace Ms {

//---------------------------------------------------------
//   ZoomIndex
//    Indices of the items in the zoom box.
//---------------------------------------------------------

enum class ZoomIndex : char {
      ZOOM_25, ZOOM_50, ZOOM_75, ZOOM_100, ZOOM_150, ZOOM_200, ZOOM_400, ZOOM_800, ZOOM_1600,
      ZOOM_PAGE_WIDTH, ZOOM_WHOLE_PAGE, ZOOM_TWO_PAGES,
      ZOOM_FREE
      };

} // namespace Ms

Q_DECLARE_METATYPE(Ms::ZoomIndex)

#endif
