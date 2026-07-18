//=============================================================================
//  MuseScore
//  Music Composition & Notation
//
//  Copyright (C) 2012 Werner Schweer
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 2
//  as published by the Free Software Foundation and appearing in
//  the file LICENCE.GPL
//=============================================================================

#include <QtTest/QtTest>
#include "mtest/testutils.h"
#include "libmscore/score.h"
#include "libmscore/mscore.h"
#include "libmscore/musescoreCore.h"
#include "libmscore/undo.h"
#include "mscore/plugin/qmlplugin.h"
#include "mscore/plugin/qmlpluginengine.h"

#define DIR QString("scripting/")

using namespace Ms;

//---------------------------------------------------------
//   TestScripting
//---------------------------------------------------------

class TestScripting : public QObject, public MTest
      {
      Q_OBJECT

      QQmlEngine* engine;

      QmlPlugin* loadPlugin(QString path);
      void runPlugin(QmlPlugin* p, Score* cs);

   private slots:
      void initTestCase();
      void plugins01();
      void plugins02();
      void invalidImportIsReported();
      void visualPluginKeepsSingleRoot();
      void processFileWithPlugin_data();
      void processFileWithPlugin();
      void testTextStyle();
      };

//---------------------------------------------------------
///   runPlugin
//---------------------------------------------------------

void TestScripting::runPlugin(QmlPlugin* p, Score* cs)
      {
      // don't call startCmd for non modal dialog
      if (cs && p->pluginType() != "dock")
            cs->startCmd();
      p->runPlugin();
      if (cs && p->pluginType() != "dock")
            cs->endCmd();
      }

//---------------------------------------------------------
///   loadPlugin
///   Loads the qml plugin located at path
///   Returns pointer to the plugin or nullptr upon failure
///   Note: ensure to cleanup the returned pointer
//---------------------------------------------------------

QmlPlugin* TestScripting::loadPlugin(QString path)
      {
      QQmlComponent component(engine);
      component.loadUrl(QUrl::fromLocalFile(path));
      QObject* obj = component.create();
      if (obj == 0) {
            foreach(QQmlError e, component.errors())
                  qDebug("   line %d: %s", e.line(), qPrintable(e.description()));
            return nullptr;
            }

      return qobject_cast<QmlPlugin*>(obj);
      }

//---------------------------------------------------------
//   initTestCase
//---------------------------------------------------------

void TestScripting::initTestCase()
      {
      initMTest();
//       qmlRegisterType<MScore>    ("MuseScore", 1, 0, "MScore");
      engine = new QmlPluginEngine(this);
      }

//---------------------------------------------------------
///   plugins01
///   Create a QML item and retrieve its coordinates
//---------------------------------------------------------

void TestScripting::plugins01()
      {
      QString path = root + "/" + DIR + "plugins01.qml";
      QQmlComponent component(engine, QUrl::fromLocalFile(path));
      QObject* object = component.create();
      if (object == 0) {
            qDebug("creating component <%s> failed", qPrintable(path));
            foreach(QQmlError e, component.errors())
                  qDebug("   line %d: %s", e.line(), qPrintable(e.description()));
            }
      else {
            qreal x = object->property("x").toDouble();
            qreal y = object->property("y").toDouble();
            QCOMPARE(x, 50.0);
            QCOMPARE(y, 60.0);
            }
      delete object;
      }

//---------------------------------------------------------
///   plugin02
///   Create a MuseScore plugin and get width and height of the dialog
//---------------------------------------------------------

void TestScripting::plugins02()
      {
      QString path = root + "/" + DIR + "plugins02.qml";
      QQmlComponent component(engine,
         QUrl::fromLocalFile(path));
      QObject* object = component.create();
      if (object == 0) {
            qDebug("creating component <%s> failed", qPrintable(path));
            foreach(QQmlError e, component.errors())
                  qDebug("   line %d: %s", e.line(), qPrintable(e.description()));
            }

      // This is the compatibility contract for legacy MuseScore 3 plugins:
      // importing MuseScore 3.0 must create the expected root type and expose
      // its metadata unchanged under both Qt 5 and Qt 6.
      QVERIFY(object);
      QmlPlugin* plugin = qobject_cast<QmlPlugin*>(object);
      QVERIFY(plugin);
      QCOMPARE(plugin->menuPath(), QString("Plugins.test3"));
      QCOMPARE(plugin->version(), QString("3.0"));
      QCOMPARE(plugin->description(), QString("Test Plugin"));
      QCOMPARE(object->property("width").toDouble(), 150.0);
      QCOMPARE(object->property("height").toDouble(), 75.0);
      delete object;
      }

//---------------------------------------------------------
///   invalidImportIsReported
///   A missing QML module must be reported as a component error instead of
///   producing a partially initialized plugin object.
//---------------------------------------------------------

void TestScripting::invalidImportIsReported()
      {
      QString path = root + "/" + DIR + "invalidImport.qml";
      QQmlComponent component(engine, QUrl::fromLocalFile(path));

      QVERIFY(component.isError());
      const QList<QQmlError> errors = component.errors();
      QVERIFY(!errors.isEmpty());

      bool missingImportReported = false;
      for (const QQmlError& error : errors) {
            if (error.description().contains("MuseScoreMigrationMissing")) {
                  missingImportReported = true;
                  break;
                  }
            }
      QVERIFY(missingImportReported);
      }

//---------------------------------------------------------
///   visualPluginKeepsSingleRoot
///   QQuickView must adopt the root created for plugin inspection instead of
///   loading the URL again and invoking Component.onCompleted twice.
//---------------------------------------------------------

void TestScripting::visualPluginKeepsSingleRoot()
      {
      const QString path = root + "/" + DIR + "visualPlugin.qml";
      const QUrl url = QUrl::fromLocalFile(path);
      QQuickView view(engine, nullptr);
      QQmlComponent* component = new QQmlComponent(engine, url, &view);
      QObject* object = component->create();

      QVERIFY2(object, qPrintable(component->errorString()));
      QmlPlugin* plugin = qobject_cast<QmlPlugin*>(object);
      QVERIFY(plugin);
      QCOMPARE(object->property("completedCount").toInt(), 1);

      view.setContent(url, component, object);

      QCOMPARE(view.status(), QQuickView::Ready);
      QCOMPARE(view.rootObject(), object);
      QCOMPARE(object->property("completedCount").toInt(), 1);
      }

//---------------------------------------------------------
//   processFileWithPlugin
//   read a score, apply script and compare script output with
//    reference
//---------------------------------------------------------

void TestScripting::processFileWithPlugin_data()
      {
      QTest::addColumn<QString>("file");
      QTest::addColumn<QString>("script");

      QTest::newRow("p1") << "s1" << "p1"; // scan note rest
      QTest::newRow("p2") << "s2" << "p2"; // scan segment attributes
      }

void TestScripting::processFileWithPlugin()
      {
      QFETCH(QString, file);
      QFETCH(QString, script);

      MasterScore* score = readScore(DIR + file + ".mscx");
      MuseScoreCore::mscoreCore->setCurrentScore(score);

      QVERIFY(score);
      score->doLayout();

      QString scriptPath = root + "/" + DIR + script + ".qml";

      QFileInfo fi(scriptPath);
      QVERIFY(fi.exists());

      QQmlComponent component(engine);
      component.loadUrl(QUrl::fromLocalFile(scriptPath));
      if (component.isError()) {
            qDebug("qml load error");
            for (QQmlError e : component.errors()) {
                  qDebug("qml error: %s", qPrintable(e.toString()));
                  }
            }

      QObject* obj = component.create();
      QVERIFY(obj);

      QmlPlugin* item = qobject_cast<QmlPlugin*>(obj);
      item->runPlugin();

      QVERIFY(compareFiles(script + ".log", DIR + script + ".log.ref"));
      delete score;
      }

//---------------------------------------------------------
///   testTextStyle
///   Reading and writing of a text style through the plugin framework
//---------------------------------------------------------

void TestScripting::testTextStyle()
      {
      QmlPlugin* item = loadPlugin(root + "/" + DIR + "testTextStyle.qml");
      QVERIFY(item != nullptr);

      Score* score = readScore(DIR + "testTextStyle.mscx");
      MuseScoreCore::mscoreCore->setCurrentScore(score);
      runPlugin(item, score);
      QVERIFY(saveCompareScore(score, "testTextStyle-test.mscx", DIR + "testTextStyle-ref.mscx"));
      score->undoRedo(/* undo */ true, /* EditData */ nullptr);
      QVERIFY(saveCompareScore(score, "testTextStyle-test2.mscx", DIR + "testTextStyle.mscx"));

      delete item;
      }

QTEST_MAIN(TestScripting)
#include "tst_scripting.moc"
