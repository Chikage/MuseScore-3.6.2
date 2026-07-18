//=============================================================================
//  MuseScore
//  Music Composition & Notation
//
//  Copyright (C) 2019 MuseScore BVBA
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

#ifndef __QML_NATIVEMENU_H__
#define __QML_NATIVEMENU_H__

namespace Ms {

//---------------------------------------------------------
//   QmlNativeMenu
//---------------------------------------------------------

class QmlNativeMenu : public QQuickItem {
      Q_OBJECT

      QList<QObject*> _contentData;
      QPoint _popupPos;

      bool _menuVisible = false;

      Q_PROPERTY(QQmlListProperty<QObject> contentData READ contentData CONSTANT)
      Q_CLASSINFO("DefaultProperty", "contentData")

      // QQuickItem::x, QQuickItem::y and QQuickItem::visible are final in Qt 6.
      // Use menu-specific names instead of shadowing those base properties.
      Q_PROPERTY(int popupX READ popupX WRITE setPopupX)
      Q_PROPERTY(int popupY READ popupY WRITE setPopupY)
      Q_PROPERTY(bool menuVisible READ menuVisible WRITE setMenuVisible NOTIFY menuVisibleChanged)

      QQmlListProperty<QObject> contentData() { return QQmlListProperty<QObject>(this, &_contentData); }

      QMenu* createMenu() const;
      void showMenu(QPoint p);

   signals:
      void menuVisibleChanged();

   public:
      QmlNativeMenu(QQuickItem* parent = nullptr);

      int popupX() const { return _popupPos.x(); }
      int popupY() const { return _popupPos.y(); }
      void setPopupX(int val) { _popupPos.setX(val); }
      void setPopupY(int val) { _popupPos.setY(val); }

      bool menuVisible() const { return _menuVisible; }
      void setMenuVisible(bool val);

      Q_INVOKABLE void open();
      Q_INVOKABLE void popup();
      };

//---------------------------------------------------------
//   QmlMenuSeparator
//---------------------------------------------------------

class QmlMenuSeparator : public QObject {
      Q_OBJECT
   public:
      QmlMenuSeparator(QObject* parent = nullptr) : QObject(parent) {}
      };

//---------------------------------------------------------
//   QmlMenuItem
//---------------------------------------------------------

class QmlMenuItem : public QObject {
      Q_OBJECT

      QString _text;
      bool _checkable = false;
      bool _checked = false;
      bool _enabled = true;

      Q_PROPERTY(QString text MEMBER _text)
      Q_PROPERTY(bool checkable MEMBER _checkable)
      Q_PROPERTY(bool checked MEMBER _checked)
      Q_PROPERTY(bool enabled MEMBER _enabled)

   signals:
      void triggered(bool checked);

   public:
      QmlMenuItem(QObject* parent = nullptr) : QObject(parent) {}

      const QString& text() const { return _text; }
      bool checkable() const { return _checkable; }
      bool checked() const { return _checked; }
      bool enabled() const { return _enabled; }
      };

} // namespace Ms
#endif
