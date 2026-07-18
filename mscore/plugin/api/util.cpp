//=============================================================================
//  MuseScore
//  Linux Music Score Editor
//
//  Copyright (C) 2009-2012 Werner Schweer and others
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

#include "config.h"
#include "util.h"

#include "score.h"

#include "libmscore/score.h"
#include "libmscore/measurebase.h"
#include "libmscore/page.h"
#include "libmscore/system.h"
#include "libmscore/staff.h"

#include <QStandardPaths>

namespace Ms {
namespace PluginAPI {

//---------------------------------------------------------
//   ScoreView
//---------------------------------------------------------

ScoreView::ScoreView(QQuickItem* parent)
   : QQuickPaintedItem(parent)
      {
      setAcceptedMouseButtons(Qt::LeftButton);
      score = 0;
      }

//---------------------------------------------------------
//   FileIO
//---------------------------------------------------------

FileIO::FileIO(QObject *parent) :
    QObject(parent)
      {
      }

static QString fileIOPath(const QString& source)
      {
      QUrl url(source);
      if (url.isValid() && url.isLocalFile())
            return url.toLocalFile();
      return source;
      }

QString FileIO::appDataPath() const
      {
      const QString path = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
      if (path.isEmpty())
            return QString();
      return QDir::cleanPath(path);
      }

QString FileIO::toLocalFile(const QUrl& url) const
      {
      if (url.isLocalFile())
            return QDir::cleanPath(url.toLocalFile());
      if (url.scheme().isEmpty()) {
            const QString path = url.toString(QUrl::FullyDecoded);
            return path.isEmpty() ? QString() : QDir::cleanPath(path);
            }
      return QString();
      }

bool FileIO::makePath(const QString& path) const
      {
      const QString localPath = fileIOPath(path);
      return !localPath.isEmpty() && QDir().mkpath(localPath);
      }

static bool readFileData(const QString& source, QByteArray* data)
      {
      QFile file(fileIOPath(source));
      if (!file.open(QIODevice::ReadOnly))
            return false;
      *data = file.readAll();
      return true;
      }

static bool writeFileData(const QString& source, const QByteArray& data)
      {
      QFile file(fileIOPath(source));
      if (!file.open(QFile::WriteOnly | QFile::Truncate))
            return false;
      const qint64 written = file.write(data);
      file.close();
      return written == data.size();
      }

QString FileIO::read()
      {
      if (mSource.isEmpty()) {
            emit error("source is empty");
            return QString();
            }
      QString source(fileIOPath(mSource));
      QFile file(source);
      QString fileContent;
      if ( file.open(QIODevice::ReadOnly) ) {
            QString line;
            QTextStream t( &file );
            do {
                line = t.readLine();
                fileContent += line + "\n";
                } while (!line.isNull());
            file.close();
            }
      else {
          emit error("Unable to open the file");
          return QString();
          }
      return fileContent;
      }

QString FileIO::readBinary()
      {
      if (mSource.isEmpty()) {
            emit error("source is empty");
            return QString();
            }
      QByteArray data;
      if (!readFileData(mSource, &data)) {
            emit error("Unable to open the file");
            return QString();
            }
      return QString::fromLatin1(data.constData(), data.size());
      }

QString FileIO::readBinaryBase64()
      {
      if (mSource.isEmpty()) {
            emit error("source is empty");
            return QString();
            }
      QByteArray data;
      if (!readFileData(mSource, &data)) {
            emit error("Unable to open the file");
            return QString();
            }
      return QString::fromLatin1(data.toBase64());
      }

bool FileIO::write(const QString& data)
      {
      if (mSource.isEmpty())
            return false;

      QFile file(fileIOPath(mSource));
      if (!file.open(QFile::WriteOnly | QFile::Truncate))
            return false;

      QTextStream out(&file);
      out << data;
      file.close();
      return true;
      }

bool FileIO::writeBinary(const QString& data)
      {
      if (mSource.isEmpty())
            return false;

      return writeFileData(mSource, data.toLatin1());
      }

bool FileIO::writeBinaryBase64(const QString& data)
      {
      if (mSource.isEmpty())
            return false;

      return writeFileData(mSource, QByteArray::fromBase64(data.toLatin1()));
      }

static bool isHexCharacter(char ch)
      {
      return (ch >= '0' && ch <= '9')
             || (ch >= 'a' && ch <= 'f')
             || (ch >= 'A' && ch <= 'F');
      }

bool FileIO::writeBinaryHex(const QString& data)
      {
      if (mSource.isEmpty())
            return false;

      QByteArray hex;
      const QByteArray raw = data.toLatin1();
      for (char ch : raw) {
            if (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t')
                  continue;
            if (!isHexCharacter(ch)) {
                  emit error("Invalid hexadecimal data");
                  return false;
                  }
            hex.append(ch);
            }
      if (hex.size() % 2) {
            emit error("Invalid hexadecimal data length");
            return false;
            }
      return writeFileData(mSource, QByteArray::fromHex(hex));
      }

bool FileIO::writeBytes(const QVariantList& data)
      {
      if (mSource.isEmpty())
            return false;

      QByteArray bytes;
      bytes.reserve(data.size());
      for (const QVariant& value : data) {
            bool ok = false;
            int byte = value.toInt(&ok);
            if (!ok) {
                  emit error("Invalid byte value");
                  return false;
                  }
            bytes.append(char(qBound(0, byte, 255)));
            }
      return writeFileData(mSource, bytes);
      }

//---------------------------------------------------------
//   remove
//---------------------------------------------------------

bool FileIO::remove()
      {
      if (mSource.isEmpty())
            return false;

      QFile file(fileIOPath(mSource));
      return file.remove();
      }

bool FileIO::exists()
      {
      QFile file(fileIOPath(mSource));
      return file.exists();
      }

int FileIO::modifiedTime()
      {
      if (mSource.isEmpty()) {
            emit error("source is empty");
            return 0;
            }
      QString source(fileIOPath(mSource));
      QFileInfo fileInfo(source);
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
      return int(fileInfo.lastModified().toSecsSinceEpoch());
#else
      return fileInfo.lastModified().toTime_t();
#endif
      }

//---------------------------------------------------------
//   setScore
//---------------------------------------------------------

void ScoreView::setScore(Ms::PluginAPI::Score* s)
      {
      Ms::Score* newScore = s ? s->score() : nullptr;
      setScore(newScore);
      }

void ScoreView::setScore(Ms::Score* s)
      {
      MuseScoreView::setScore(s);
      _currentPage = 0;
      score = s;

      if (score) {
            score->doLayout();

            Page* page = score->pages()[_currentPage];
            QRectF pr(page->abbox());
            qreal m1 = width()  / pr.width();
            qreal m2 = height() / pr.height();
            mag = qMax(m1, m2);

            _boundingRect = QRectF(0.0, 0.0, pr.width() * mag, pr.height() * mag);

            setWidth(pr.width() * mag);
            setHeight(pr.height() * mag);
            }
      update();
      }

//---------------------------------------------------------
//   paint
//---------------------------------------------------------

void ScoreView::paint(QPainter* p)
      {
      p->setRenderHint(QPainter::Antialiasing, true);
      p->setRenderHint(QPainter::TextAntialiasing, true);
      p->fillRect(QRect(0, 0, width(), height()), _color);
      if (!score)
            return;
      p->scale(mag, mag);

      Page* page = score->pages()[_currentPage];
      QList<const Element*> el;
      for (System* s : page->systems()) {
            for (MeasureBase* m : s->measures())
                  m->scanElements(&el, collectElements, false);
            }
      page->scanElements(&el, collectElements, false);

      foreach(const Element* e, el) {
            QPointF pos(e->pagePos());
            p->translate(pos);
            e->draw(p);
            p->translate(-pos);
            }
      }

//---------------------------------------------------------
//   setCurrentPage
//---------------------------------------------------------

void ScoreView::setCurrentPage(int n)
      {
      if (score == 0)
            return;
      if (n < 0)
            n = 0;
      int nn = score->pages().size();
      if (nn == 0)
            return;
      if (n >= nn)
            n = nn - 1;
      _currentPage = n;
      update();
      }

//---------------------------------------------------------
//   nextPage
//---------------------------------------------------------

void ScoreView::nextPage()
      {
      setCurrentPage(_currentPage + 1);
      }

//---------------------------------------------------------
//   prevPage
//---------------------------------------------------------

void ScoreView::prevPage()
      {
      setCurrentPage(_currentPage - 1);
      }
}
}
