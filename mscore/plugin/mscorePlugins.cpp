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

#include "musescore.h"
#include "config.h"
#include "preferences.h"
#include "qmlplugin.h"
#include "qmlpluginengine.h"
#include "pluginManager.h"

namespace Ms {

namespace {

void logPluginComponentErrors(const QString& pluginPath, const QList<QQmlError>& errors)
      {
      if (errors.isEmpty()) {
            qWarning("Loading plugin <%s> failed without a QML diagnostic", qPrintable(pluginPath));
            return;
            }

      for (const QQmlError& error : errors)
            qWarning("Plugin <%s>: %s", qPrintable(pluginPath), qPrintable(error.toString()));
      }

//---------------------------------------------------------
//   PluginInstance
//   Owns one running plugin and keeps its QML engine isolated from all other
//   plugins. The visual owner (if any) is destroyed before the engine so QML
//   objects never outlive the engine which created them.
//---------------------------------------------------------

class PluginInstance : public QObject {
      QmlPluginEngine* _engine;
      QPointer<QmlPlugin> _root;
      QPointer<QObject> _visualOwner;

   public:
      explicit PluginInstance(QObject* parent)
         : QObject(parent), _engine(new QmlPluginEngine(this))
            {
            connect(_engine, &QQmlEngine::quit, this, [this]() {
                  if (QWidget* widget = qobject_cast<QWidget*>(_visualOwner.data())) {
                        widget->close();
                        return;
                        }
                  if (QWindow* window = qobject_cast<QWindow*>(_visualOwner.data())) {
                        window->close();
                        return;
                        }
                  deleteLater();
                  }, Qt::QueuedConnection);
            }

      ~PluginInstance() override
            {
            QObject* visualOwner = _visualOwner.data();
            if (visualOwner) {
                  disconnect(visualOwner, nullptr, this, nullptr);
                  delete visualOwner;
                  }
            if (_root)
                  delete _root.data();
            }

      QmlPluginEngine* engine() const { return _engine; }
      void setRoot(QmlPlugin* root) { _root = root; }

      void setVisualOwner(QObject* visualOwner)
            {
            _visualOwner = visualOwner;
            connect(visualOwner, &QObject::destroyed, this, &QObject::deleteLater);
            }
      };

}

//---------------------------------------------------------
//   registerPlugin
//---------------------------------------------------------

void MuseScore::registerPlugin(PluginDescription* plugin)
      {
      QString _pluginPath = plugin->path;
      QFileInfo np(_pluginPath);
      if (np.suffix() != "qml")
            return;
      QString baseName = np.completeBaseName();

      foreach(QString s, plugins) {
            QFileInfo fi(s);
            if (fi.completeBaseName() == baseName) {
                  if (MScore::debugMode)
                        qDebug("  Plugin <%s> already registered", qPrintable(_pluginPath));
                  return;
                  }
            }

      QFile f(_pluginPath);
      if (!f.open(QIODevice::ReadOnly)) {
            if (MScore::debugMode)
                  qDebug("Loading Plugin <%s> failed", qPrintable(_pluginPath));
            return;
            }
      if (MScore::debugMode)
            qDebug("Register Plugin <%s>", qPrintable(_pluginPath));
      f.close();
      QObject* obj = 0;
      QQmlComponent component(getPluginEngine(), QUrl::fromLocalFile(_pluginPath));
      obj = component.create();
      if (obj == 0) {
            qDebug("creating component <%s> failed", qPrintable(_pluginPath));
            logPluginComponentErrors(_pluginPath, component.errors());
            return;
            }
      QmlPlugin* item = qobject_cast<QmlPlugin*>(obj);
      if (!item) {
            qWarning("Plugin <%s> has an invalid QML root object; expected a MuseScore plugin",
                     qPrintable(_pluginPath));
            delete obj;
            return;
            }
      //
      // load translation
      //
      QLocale locale;
      QString t = np.absolutePath() + "/translations/locale_" + MuseScore::getLocaleISOCode().left(2) + ".qm";
      QTranslator* translator = new QTranslator;
      if (!translator->load(t)) {
//            qDebug("cannot load qml translations <%s>", qPrintable(t));
            delete translator;
            }
      else {
//            qDebug("load qml translations <%s>", qPrintable(t));
            qApp->installTranslator(translator);
            }

      QString menuPath = item->menuPath();
      plugin->menuPath = menuPath;
      plugins.append(_pluginPath);
      createMenuEntry(plugin);

      QAction* a = plugin->shortcut.action();
      pluginActions.append(a);
      connect(a, &QAction::triggered, mscore, [_pluginPath]() { mscore->pluginTriggered(_pluginPath); });

      delete obj;
      }

void MuseScore::unregisterPlugin(PluginDescription* plugin)
      {
      QString _pluginPath = plugin->path;
      QFileInfo np(_pluginPath);
      if (np.suffix() != "qml")
            return;
      QString baseName = np.completeBaseName();

      bool found = false;
      foreach(QString s, plugins) {
            QFileInfo fi(s);
            if (fi.completeBaseName() == baseName) {
                  found = true;
                  break;
                  }
            }
      if (!found) {
            if (MScore::debugMode)
                  qDebug("  Plugin <%s> not registered", qPrintable(_pluginPath));
            return;
            }
      plugins.removeAll(_pluginPath);


      removeMenuEntry(plugin);
      QAction* a = plugin->shortcut.action();
      pluginActions.removeAll(a);

      disconnect(a, 0, mscore, 0);
      }

//---------------------------------------------------------
//   createMenuEntry
//    syntax: "entry.entry.entry"
//---------------------------------------------------------

void MuseScore::createMenuEntry(PluginDescription* plugin)
      {
      QString menu = plugin->menuPath;
      QStringList ml;
      QString s;
      bool escape = false;
      foreach (QChar c, menu) {
            if (escape) {
                  escape = false;
                  s += c;
                  }
            else {
                  if (c == '\\')
                        escape = true;
                  else {
                        if (c == '.') {
                              ml += s;
                              s = "";
                              }
                        else {
                              s += c;
                              }
                        }
                  }
            }
      if (!s.isEmpty())
            ml += s;

      int n            = ml.size();
      QWidget* curMenu = menuBar();

      for(int i = 0; i < n; ++i) {
            QString m  = ml[i];
            bool found = false;
            QList<QObject*> ol = curMenu->children();
            foreach(QObject* o, ol) {
                  QMenu* cmenu = qobject_cast<QMenu*>(o);
                  if (!cmenu)
                        continue;
                  if (cmenu->objectName() == m || cmenu->title() == m) {
                        curMenu = cmenu;
                        found = true;
                        break;
                        }
                  }
            if (!found) {
                  if (i == 0) {
                        curMenu = new QMenu(m, menuBar());
                        curMenu->setObjectName(m);
                        menuBar()->insertMenu(menuBar()->actions().back(), (QMenu*)curMenu);
                        if (MScore::debugMode)
                              qDebug("add Menu <%s>", qPrintable(m));
                        }
                  else if (i + 1 == n) {
                        QStringList sl = m.split(":");
                        QAction* a = plugin->shortcut.action();
                        QMenu* cm = static_cast<QMenu*>(curMenu);
                        if (sl.size() == 2) {
                              QList<QAction*> al = cm->actions();
                              QAction* ba = 0;
                              foreach(QAction* ia, al) {
                                    if (ia->text() == sl[0]) {
                                          ba = ia;
                                          break;
                                          }
                                    }
                              a->setText(sl[1]);
                              cm->insertAction(ba, a);
                              }
                        else {
                              a->setText(m);
                              cm->addAction(a);
                              }

                        if (MScore::debugMode)
                              qDebug("plugins: add action <%s>", qPrintable(m));
                        }
                  else {
                        curMenu = ((QMenu*)curMenu)->addMenu(m);
                        if (MScore::debugMode)
                              qDebug("add menu <%s>", qPrintable(m));
                        }
                  }
            }
      }

//---------------------------------------------------------
//   addPluginMenuEntries
//---------------------------------------------------------

void MuseScore::addPluginMenuEntries()
      {
      for (int i = 0; i < pluginManager->pluginCount(); ++i) {
            PluginDescription* d = pluginManager->getPluginDescription(i);
            if (d->load)
                  createMenuEntry(d);
            }
      }

void MuseScore::removeMenuEntry(PluginDescription* plugin)
      {
      QString menu = plugin->menuPath;
      QStringList ml;
      QString s;
      bool escape = false;
      foreach (QChar c, menu) {
            if (escape) {
                  escape = false;
                  s += c;
                  }
            else {
                  if (c == '\\')
                        escape = true;
                  else {
                        if (c == '.') {
                              ml += s;
                              s = "";
                              }
                        else {
                              s += c;
                              }
                        }
                  }
            }
      if (!s.isEmpty())
            ml += s;

      if(ml.isEmpty())
            return;

      int n            = ml.size();
      QWidget* curMenu = menuBar();

      for(int i = 0; i < n-1; ++i) {
            QString m  = ml[i];
            QList<QObject*> ol = curMenu->children();
            foreach(QObject* o, ol) {
                  QMenu* cmenu = qobject_cast<QMenu*>(o);
                  if (!cmenu)
                        continue;
                  if (cmenu->objectName() == m || cmenu->title() == m) {
                        curMenu = cmenu;
                        break;
                        }
                  }
            }
      QString m  = ml[n-1];
      QStringList sl = m.split(":");
      QAction* a = plugin->shortcut.action();
      QMenu* cm = static_cast<QMenu*>(curMenu);
      cm->removeAction(a);
      for(int i = n-2; i >= 0; --i) {

            QMenu* cmenu = qobject_cast<QMenu*>(cm->parent());
            if (cm->isEmpty())
                  delete cm;

            cm = cmenu;
            }
      }

//---------------------------------------------------------
//   pluginIdxFromPath
//---------------------------------------------------------

int MuseScore::pluginIdxFromPath(QString _pluginPath) {
      QFileInfo np(_pluginPath);
      QString baseName = np.completeBaseName();
      int idx = 0;
      foreach(QString s, plugins) {
            QFileInfo fi(s);
            if (fi.completeBaseName() == baseName)
                  return idx;
            idx++;
            }
      return -1;
      }

//---------------------------------------------------------
//   loadPlugins
//---------------------------------------------------------

void MuseScore::loadPlugins()
      {
      for (int i = 0; i < pluginManager->pluginCount(); ++i) {
            PluginDescription* d = pluginManager->getPluginDescription(i);
            if (d->load)
                  registerPlugin(d);
            }
      }

//---------------------------------------------------------
//   unloadPlugins
//---------------------------------------------------------

void MuseScore::unloadPlugins()
      {
      const QList<QPointer<QObject>> instances = _pluginInstances;
      _pluginInstances.clear();
      for (const QPointer<QObject>& instance : instances) {
            if (instance)
                  delete instance.data();
            }

      const QList<PluginDescription*> descriptions = _transientPluginDescriptions;
      _transientPluginDescriptions.clear();
      for (PluginDescription* description : descriptions) {
            QAction* action = description->shortcut.action();
            unregisterPlugin(description);
            delete action;
            delete description;
            }
      }

//---------------------------------------------------------
//   loadPlugin
//---------------------------------------------------------

bool MuseScore::loadPlugin(const QString& filename)
      {
      QDir pluginDir(mscoreGlobalShare + "plugins");
      if (MScore::debugMode)
            qDebug("Plugin Path <%s>", qPrintable(mscoreGlobalShare + "plugins"));

      if (filename.endsWith(".qml")) {
            QFileInfo fi(pluginDir, filename);
            if (!fi.exists())
                  fi = QFileInfo(preferences.getString(PREF_APP_PATHS_MYPLUGINS), filename);
            if (fi.exists()) {
                  QString path(fi.filePath());
                  PluginDescription* p = new PluginDescription;
                  p->path = path;
                  p->load = false;
                  if (!collectPluginMetaInformation(p)) {
                        delete p;
                        return false;
                        }

                  const int pluginCountBefore = plugins.size();
                  registerPlugin(p);
                  if (plugins.size() == pluginCountBefore) {
                        delete p;
                        return false;
                        }

                  _transientPluginDescriptions.append(p);
                  return true;
                  }
            }
      return false;
      }

//---------------------------------------------------------
//   pluginTriggered
//---------------------------------------------------------

void MuseScore::pluginTriggered(int idx)
      {
      if (idx >= 0 && idx < plugins.size())
            pluginTriggered(plugins[idx]);
      }

void MuseScore::pluginTriggered(QString pp)
      {
      PluginInstance* instance = new PluginInstance(this);
      QmlPluginEngine* engine = instance->engine();
      const QUrl pluginUrl = QUrl::fromLocalFile(pp);

      // Keep the component alive for visual plugins: QQuickView::setContent()
      // adopts the already-created root object instead of loading the URL a
      // second time and running Component.onCompleted twice.
      QQmlComponent* component = new QQmlComponent(engine, pluginUrl);
      QObject* obj = component->create();
      if (obj == 0) {
            logPluginComponentErrors(pp, component->errors());
            delete component;
            delete instance;
            return;
            }

      QmlPlugin* p = qobject_cast<QmlPlugin*>(obj);
      if (!p) {
            qWarning("Plugin <%s> has an invalid QML root object; expected a MuseScore plugin",
                     qPrintable(pp));
            delete obj;
            delete component;
            delete instance;
            return;
            }
      instance->setRoot(p);
      if(MuseScoreCore::mscoreCore->currentScore() == nullptr && p->requiresScore() == true) {
            QMessageBox::information(0,
                  QMessageBox::tr("MuseScore"),
                  QMessageBox::tr("No score open.\n"
                  "This plugin requires an open score to run.\n"),
                  QMessageBox::Ok, QMessageBox::NoButton);
            delete component;
            delete instance;
            return;
            }

      const QString pluginType = p->pluginType();
      if (pluginType == "dock" || pluginType == "dialog") {
            QQuickView* view = new QQuickView(engine, 0);
            component->setParent(view);
            view->setContent(pluginUrl, component, p);
            if (view->rootObject() != p || view->status() == QQuickView::Error) {
                  qWarning("Plugin view <%s> has an invalid QML root object; expected a MuseScore plugin",
                           qPrintable(pp));
                  logPluginComponentErrors(pp, view->errors());
                  delete view;
                  delete instance;
                  return;
                  }
            view->setTitle(p->menuPath().mid(p->menuPath().lastIndexOf(".") + 1));
            view->setColor(QApplication::palette().color(QPalette::Window));
            //p->setParentItem(view->contentItem());
            //view->setWidth(p->width());
            //view->setHeight(p->height());
            view->setResizeMode(QQuickView::SizeRootObjectToView);
            if (pluginType == "dock") {
                  QDockWidget* dock = new QDockWidget(view->title(), this);
                  dock->setAttribute(Qt::WA_DeleteOnClose);
                  Qt::DockWidgetArea area = Qt::RightDockWidgetArea;
                  if (p->dockArea() == "left")
                        area = Qt::LeftDockWidgetArea;
                  else if (p->dockArea() == "top")
                        area = Qt::TopDockWidgetArea;
                  else if (p->dockArea() == "bottom")
                        area = Qt::BottomDockWidgetArea;
                  QWidget* w = QWidget::createWindowContainer(view, dock);
                  dock->setWidget(w);
                  addDockWidget(area, dock);
                  const Qt::Orientation orientation =
                     (area == Qt::RightDockWidgetArea || area == Qt::LeftDockWidgetArea)
                     ? Qt::Vertical
                     : Qt::Horizontal;
                  const int size = (orientation == Qt::Vertical) ? view->initialSize().height() : view->initialSize().width();
                  resizeDocks({ dock }, { size }, orientation);
                  instance->setVisualOwner(dock);
                  dock->show();
                  }
            else {
                  // QQuickCloseEvent is incomplete in the public Qt 5 headers,
                  // so a string-based connection is required for dual Qt 5/6 builds.
                  connect(view, SIGNAL(closing(QQuickCloseEvent*)), view, SLOT(deleteLater()));
                  instance->setVisualOwner(view);
                  view->show();
                  }
            }
      else {
            delete component;
            }

      // Command state is maintained by the central engine. Keep this direct
      // connection so scoreStateChanged handlers run while its command state is
      // active, but isolate Qt.quit() on the per-plugin runtime engine above.
      connect(getPluginEngine(), &QmlPluginEngine::endCmd, p, &QmlPlugin::endCmd);

      p->setFilePath(QFileInfo(pp).absolutePath());

      for (int idx = _pluginInstances.size() - 1; idx >= 0; --idx) {
            if (_pluginInstances.at(idx).isNull())
                  _pluginInstances.removeAt(idx);
            }
      _pluginInstances.append(instance);

      // don’t call startCmd for non modal dialog
      if (cs && pluginType != "dock")
            cs->startCmd();
      p->runPlugin();
      if (cs && pluginType != "dock")
            cs->endCmd();
//      endCmd();
      }

//---------------------------------------------------------
//   collectPluginMetaInformation
///   returns false if loading a plugin for the given
///   description has failed
//---------------------------------------------------------

bool collectPluginMetaInformation(PluginDescription* d)
      {
      qDebug("Collect meta for <%s>", qPrintable(d->path));

      QQmlComponent component(mscore->getPluginEngine(), QUrl::fromLocalFile(d->path));
      QObject* obj = component.create();
      if (obj == 0) {
            qDebug("creating component <%s> failed", qPrintable(d->path));
            logPluginComponentErrors(d->path, component.errors());
            return false;
            }
      QmlPlugin* item = qobject_cast<QmlPlugin*>(obj);
      const bool isQmlPlugin = bool(item);
      if (item) {
            d->version      = item->version();
            d->description  = item->description();
            }
      delete obj;
      return isQmlPlugin;
      }
}
