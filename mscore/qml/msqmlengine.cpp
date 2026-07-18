//=============================================================================
//  MuseScore
//  Music Composition & Notation
//
//  Copyright (C) 2019 Werner Schweer and others
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 2.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
//=============================================================================

#include "msqmlengine.h"

namespace Ms {

extern QString mscoreGlobalShare;

namespace {

QString applicationQmlImportPath()
      {
#ifdef Q_OS_MAC
      return QDir(mscoreGlobalShare + QString("/qml")).absolutePath();
#else
      return QDir(QCoreApplication::applicationDirPath() + QString("/../qml")).absolutePath();
#endif
      }

}

//---------------------------------------------------------
//   MsQmlEngine
//---------------------------------------------------------

MsQmlEngine::MsQmlEngine(QObject* parent)
   : QQmlEngine(parent)
      {
      // Keep the paths initialized by Qt (qt.conf, environment variables,
      // built-in qrc imports and the Qt installation) and add the deployed
      // application QML tree after them. QmlPluginEngine inherits this setup.
      QStringList importPaths = importPathList();
      const QString appImportPath = applicationQmlImportPath();
      if (!importPaths.contains(appImportPath)) {
            importPaths.append(appImportPath);
            setImportPathList(importPaths);
            }
      }
}
