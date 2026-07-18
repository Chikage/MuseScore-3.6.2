//=============================================================================
//  MuseScore
//  Music Composition & Notation
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 2
//  as published by the Free Software Foundation and appearing in
//  the file LICENCE.GPL
//=============================================================================

#include <QtTest/QtTest>

#include <QPointer>
#include <QDockWidget>
#include <QFile>
#include <QQmlEngine>
#include <QQuickView>
#include <QTemporaryDir>

#include "mtest/testutils.h"
#include "mscore/musescore.h"
#include "mscore/plugin/qmlpluginengine.h"

#define DIR QString("scripting/")

using namespace Ms;

//---------------------------------------------------------
//   TestPluginLifecycle
//---------------------------------------------------------

class TestPluginLifecycle : public QObject
      {
      Q_OBJECT

      std::unique_ptr<QTemporaryDir> configDir;
      QString root;

      QString fixturePath(const QString& fileName) const;
      QList<QQuickView*> fixtureViews() const;
      QQuickView* newFixtureView(const QList<QQuickView*>& previousViews) const;
      QList<QmlPluginEngine*> pluginEngines() const;
      QmlPluginEngine* newPluginEngine(const QList<QmlPluginEngine*>& previousEngines) const;
      QmlPluginEngine* pluginEngineForRoot(QObject* rootObject) const;
      void drainDeferredDeletes();
      void forceCloseFixtureViews();

   private slots:
      void initTestCase();
      void cleanupTestCase();
      void cleanup();

      void qtQuitIsIsolatedPerPluginInstance();
      void dockCloseDestroysEntirePluginInstance();
      void nonVisualQtQuitDisconnectsEndCmd();
      void unloadPluginsDestroysActiveInstances();
      void invalidMetadataReturnsFalse();
      };

//---------------------------------------------------------
//   fixturePath
//---------------------------------------------------------

QString TestPluginLifecycle::fixturePath(const QString& fileName) const
      {
      return root + "/" + DIR + fileName;
      }

//---------------------------------------------------------
//   fixtureViews
//---------------------------------------------------------

QList<QQuickView*> TestPluginLifecycle::fixtureViews() const
      {
      QList<QQuickView*> result;
      for (QWindow* window : QGuiApplication::allWindows()) {
            QQuickView* view = qobject_cast<QQuickView*>(window);
            if (!view || !view->rootObject())
                  continue;
            if (view->rootObject()->property("pluginLifecycleTestFixture").toBool())
                  result.append(view);
            }
      return result;
      }

//---------------------------------------------------------
//   newFixtureView
//---------------------------------------------------------

QQuickView* TestPluginLifecycle::newFixtureView(const QList<QQuickView*>& previousViews) const
      {
      for (QQuickView* view : fixtureViews()) {
            if (!previousViews.contains(view))
                  return view;
            }
      return nullptr;
      }

//---------------------------------------------------------
//   pluginEngines
//---------------------------------------------------------

QList<QmlPluginEngine*> TestPluginLifecycle::pluginEngines() const
      {
      return Ms::mscore->findChildren<QmlPluginEngine*>();
      }

//---------------------------------------------------------
//   newPluginEngine
//---------------------------------------------------------

QmlPluginEngine* TestPluginLifecycle::newPluginEngine(const QList<QmlPluginEngine*>& previousEngines) const
      {
      for (QmlPluginEngine* engine : pluginEngines()) {
            if (!previousEngines.contains(engine))
                  return engine;
            }
      return nullptr;
      }

//---------------------------------------------------------
//   pluginEngineForRoot
//---------------------------------------------------------

QmlPluginEngine* TestPluginLifecycle::pluginEngineForRoot(QObject* rootObject) const
      {
      return qobject_cast<QmlPluginEngine*>(qmlEngine(rootObject));
      }

//---------------------------------------------------------
//   drainDeferredDeletes
//---------------------------------------------------------

void TestPluginLifecycle::drainDeferredDeletes()
      {
      for (int i = 0; i < 3; ++i) {
            QCoreApplication::processEvents(QEventLoop::AllEvents);
            QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
            }
      }

//---------------------------------------------------------
//   forceCloseFixtureViews
//---------------------------------------------------------

void TestPluginLifecycle::forceCloseFixtureViews()
      {
      for (QQuickView* view : fixtureViews()) {
            view->close();
            view->deleteLater();
            }
      drainDeferredDeletes();
      }

//---------------------------------------------------------
//   initTestCase
//---------------------------------------------------------

void TestPluginLifecycle::initTestCase()
      {
      qputenv("QML_DISABLE_DISK_CACHE", "true");
      qSetMessagePattern("%{function}: %{message}");
      QSettings::setDefaultFormat(QSettings::IniFormat);
      MScore::noGui = true;
      MScore::testMode = true;

      configDir.reset(new QTemporaryDir);
      QVERIFY(configDir->isValid());
      QVERIFY(MuseScoreApplication::setCustomConfigFolder(configDir->path()));

      // A test executable is not laid out as a deployed macOS application,
      // so getSharePath() cannot see the generated workspace archives. Copy
      // the normal build outputs into the isolated user-data directory before
      // MuseScore constructs its workspace selector.
      const QDir generatedWorkspaces(
         QDir(QCoreApplication::applicationDirPath()).absoluteFilePath("../../share/workspaces"));
      const QString userWorkspacesPath = configDir->filePath("workspaces");
      QVERIFY(QDir().mkpath(userWorkspacesPath));
      for (const QString& workspace : { QString("Basic.workspace"), QString("Advanced.workspace") }) {
            const QString source = generatedWorkspaces.filePath(workspace);
            const QString destination = QDir(userWorkspacesPath).filePath(workspace);
            QVERIFY2(QFileInfo(source).exists(), qPrintable(source));
            QVERIFY2(QFile::copy(source, destination), qPrintable(destination));
            }

      initMuseScoreResources();
      QStringList args;
      MuseScore::init(args);
      QVERIFY(Ms::mscore);

      root = TESTROOT "/mtest";
      }

//---------------------------------------------------------
//   cleanupTestCase
//---------------------------------------------------------

void TestPluginLifecycle::cleanupTestCase()
      {
      cleanup();
      delete Ms::mscore;
      Ms::mscore = nullptr;
      configDir.reset();
      }

//---------------------------------------------------------
//   cleanup
//---------------------------------------------------------

void TestPluginLifecycle::cleanup()
      {
      if (Ms::mscore)
            Ms::mscore->unloadPlugins();
      drainDeferredDeletes();

      // Keep later test cases isolated even when an unload assertion fails.
      forceCloseFixtureViews();
      }

//---------------------------------------------------------
//   qtQuitIsIsolatedPerPluginInstance
//---------------------------------------------------------

void TestPluginLifecycle::qtQuitIsIsolatedPerPluginInstance()
      {
      const QString path = fixturePath("lifecyclePlugin.qml");
      QVERIFY(QFileInfo(path).exists());

      QList<QQuickView*> previousViews = fixtureViews();
      Ms::mscore->pluginTriggered(path);
      QTRY_VERIFY(fixtureViews().size() > previousViews.size());
      QQuickView* first = newFixtureView(previousViews);
      QVERIFY(first);

      previousViews = fixtureViews();
      Ms::mscore->pluginTriggered(path);
      QTRY_VERIFY(fixtureViews().size() > previousViews.size());
      QQuickView* second = newFixtureView(previousViews);
      QVERIFY(second);
      QVERIFY(first != second);

      QPointer<QQuickView> firstView(first);
      QPointer<QObject> firstRoot(first->rootObject());
      QPointer<QQuickView> secondView(second);
      QPointer<QObject> secondRoot(second->rootObject());
      QPointer<QmlPluginEngine> firstEngine(pluginEngineForRoot(firstRoot.data()));
      QPointer<QmlPluginEngine> secondEngine(pluginEngineForRoot(secondRoot.data()));
      QVERIFY(firstEngine);
      QVERIFY(secondEngine);
      QPointer<QObject> firstInstance(firstEngine->parent());
      QPointer<QObject> secondInstance(secondEngine->parent());

      QVERIFY(QMetaObject::invokeMethod(firstRoot.data(), "requestQuit", Qt::DirectConnection));

      QTRY_VERIFY(firstView.isNull());
      QTRY_VERIFY(firstRoot.isNull());
      QTRY_VERIFY(firstEngine.isNull());
      QTRY_VERIFY(firstInstance.isNull());
      QVERIFY(!secondView.isNull());
      QVERIFY(!secondRoot.isNull());
      QVERIFY(!secondEngine.isNull());
      QVERIFY(!secondInstance.isNull());
      QVERIFY(secondView->isVisible());
      }

//---------------------------------------------------------
//   dockCloseDestroysEntirePluginInstance
//---------------------------------------------------------

void TestPluginLifecycle::dockCloseDestroysEntirePluginInstance()
      {
      const QString path = fixturePath("lifecycleDockPlugin.qml");
      QVERIFY(QFileInfo(path).exists());

      const QList<QQuickView*> previousViews = fixtureViews();
      Ms::mscore->pluginTriggered(path);
      QTRY_VERIFY(fixtureViews().size() > previousViews.size());
      QQuickView* view = newFixtureView(previousViews);
      QVERIFY(view);

      QDockWidget* dock = nullptr;
      for (QDockWidget* candidate : Ms::mscore->findChildren<QDockWidget*>()) {
            if (candidate->windowTitle() == QString("lifecycleDockTest")) {
                  dock = candidate;
                  break;
                  }
            }
      QVERIFY(dock);

      QPointer<QDockWidget> dockPointer(dock);
      QPointer<QQuickView> viewPointer(view);
      QPointer<QObject> rootPointer(view->rootObject());
      QPointer<QmlPluginEngine> enginePointer(pluginEngineForRoot(rootPointer.data()));
      QVERIFY(enginePointer);
      QPointer<QObject> instancePointer(enginePointer->parent());
      QVERIFY(instancePointer);

      dock->close();

      QTRY_VERIFY(dockPointer.isNull());
      QTRY_VERIFY(viewPointer.isNull());
      QTRY_VERIFY(rootPointer.isNull());
      QTRY_VERIFY(enginePointer.isNull());
      QTRY_VERIFY(instancePointer.isNull());
      }

//---------------------------------------------------------
//   nonVisualQtQuitDisconnectsEndCmd
//---------------------------------------------------------

void TestPluginLifecycle::nonVisualQtQuitDisconnectsEndCmd()
      {
      const QString fixture = fixturePath("nonVisualLifecyclePlugin.qml");
      const QString pluginPath = configDir->filePath("nonVisualLifecyclePlugin.qml");
      const QString logPath = configDir->filePath("nonVisualLifecyclePlugin.log");
      QVERIFY(QFileInfo(fixture).exists());
      QFile::remove(pluginPath);
      QFile::remove(logPath);
      QVERIFY(QFile::copy(fixture, pluginPath));

      QmlPluginEngine* centralEngine = Ms::mscore->getPluginEngine();
      QVERIFY(centralEngine);
      const QList<QmlPluginEngine*> previousEngines = pluginEngines();

      Ms::mscore->pluginTriggered(pluginPath);
      QmlPluginEngine* runtimeEngine = newPluginEngine(previousEngines);
      QVERIFY(runtimeEngine);
      QPointer<QmlPluginEngine> runtimeEnginePointer(runtimeEngine);
      QPointer<QObject> instancePointer(runtimeEngine->parent());
      QVERIFY(instancePointer);

      // Qt.quit() is queued by PluginInstance. Emit one score-state update
      // before processing that queue, then verify that no update is delivered
      // after the non-visual root and its runtime engine have been destroyed.
      QVariantMap state;
      state.insert("selectionChanged", true);
      centralEngine->endCmd(state);

      QTRY_VERIFY(runtimeEnginePointer.isNull());
      QTRY_VERIFY(instancePointer.isNull());

      QFile logFile(logPath);
      QVERIFY(logFile.open(QIODevice::ReadOnly));
      const QByteArray logAfterQuit = logFile.readAll();
      logFile.close();
      QCOMPARE(logAfterQuit, QByteArray("run\nendCmd\ndestroyed\n"));

      centralEngine->endCmd(state);
      drainDeferredDeletes();

      QVERIFY(logFile.open(QIODevice::ReadOnly));
      QCOMPARE(logFile.readAll(), logAfterQuit);
      }

//---------------------------------------------------------
//   unloadPluginsDestroysActiveInstances
//---------------------------------------------------------

void TestPluginLifecycle::unloadPluginsDestroysActiveInstances()
      {
      const QString path = fixturePath("lifecyclePlugin.qml");

      QList<QQuickView*> previousViews = fixtureViews();
      Ms::mscore->pluginTriggered(path);
      QTRY_VERIFY(fixtureViews().size() > previousViews.size());
      QQuickView* first = newFixtureView(previousViews);
      QVERIFY(first);

      previousViews = fixtureViews();
      Ms::mscore->pluginTriggered(path);
      QTRY_VERIFY(fixtureViews().size() > previousViews.size());
      QQuickView* second = newFixtureView(previousViews);
      QVERIFY(second);

      QPointer<QQuickView> firstView(first);
      QPointer<QObject> firstRoot(first->rootObject());
      QPointer<QQuickView> secondView(second);
      QPointer<QObject> secondRoot(second->rootObject());
      QPointer<QmlPluginEngine> firstEngine(pluginEngineForRoot(firstRoot.data()));
      QPointer<QmlPluginEngine> secondEngine(pluginEngineForRoot(secondRoot.data()));
      QVERIFY(firstEngine);
      QVERIFY(secondEngine);
      QPointer<QObject> firstInstance(firstEngine->parent());
      QPointer<QObject> secondInstance(secondEngine->parent());

      Ms::mscore->unloadPlugins();

      // unloadPlugins() is used during application teardown, so ownership
      // must be resolved before it returns rather than through deleteLater().
      QVERIFY(firstView.isNull());
      QVERIFY(secondView.isNull());
      QVERIFY(firstRoot.isNull());
      QVERIFY(secondRoot.isNull());
      QVERIFY(firstEngine.isNull());
      QVERIFY(secondEngine.isNull());
      QVERIFY(firstInstance.isNull());
      QVERIFY(secondInstance.isNull());
      QVERIFY(fixtureViews().isEmpty());
      }

//---------------------------------------------------------
//   invalidMetadataReturnsFalse
//---------------------------------------------------------

void TestPluginLifecycle::invalidMetadataReturnsFalse()
      {
      const QString validPath = fixturePath("lifecyclePlugin.qml");
      const QString path = fixturePath("invalidMetadataPlugin.qml");
      QVERIFY(QFileInfo(validPath).exists());
      QVERIFY(QFileInfo(path).exists());

      // The valid control ensures this exercises metadata validation rather
      // than merely returning false because the absolute path was not found.
      QVERIFY(Ms::mscore->loadPlugin(validPath));
      Ms::mscore->unloadPlugins();
      QVERIFY(!Ms::mscore->loadPlugin(path));
      }

QTEST_MAIN(TestPluginLifecycle)
#include "tst_pluginlifecycle.moc"
