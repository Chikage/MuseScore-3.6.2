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
#include <QPaintEngine>
#include "mtest/testutils.h"
#include "libmscore/score.h"
#include "libmscore/measure.h"
#include "libmscore/chordrest.h"

#define DIR QString("libmscore/beam/")

using namespace Ms;

namespace {

class PolygonCountPaintEngine : public QPaintEngine {
      int _polygonCount = 0;

   public:
      PolygonCountPaintEngine() : QPaintEngine(QPaintEngine::AllFeatures) {}

      bool begin(QPaintDevice*) override { return true; }
      bool end() override { return true; }
      Type type() const override { return QPaintEngine::User; }
      void updateState(const QPaintEngineState&) override {}
      void drawPixmap(const QRectF&, const QPixmap&, const QRectF&) override {}
      void drawPolygon(const QPointF*, int, PolygonDrawMode) override { ++_polygonCount; }

      int polygonCount() const { return _polygonCount; }
      };

class PolygonCountPaintDevice : public QPaintDevice {
      mutable PolygonCountPaintEngine _engine;

   protected:
      int metric(PaintDeviceMetric metric) const override
            {
            switch (metric) {
                  case PdmWidth:
                  case PdmHeight:
                        return 1000;
                  case PdmWidthMM:
                  case PdmHeightMM:
                        return 264;
                  case PdmNumColors:
                        return 16777216;
                  case PdmDepth:
                        return 32;
                  case PdmDpiX:
                  case PdmDpiY:
                  case PdmPhysicalDpiX:
                  case PdmPhysicalDpiY:
                        return 96;
                  case PdmDevicePixelRatio:
                        return 1;
                  case PdmDevicePixelRatioScaled:
                        return int(devicePixelRatioFScale());
                  }
            return 0;
            }

   public:
      QPaintEngine* paintEngine() const override { return &_engine; }
      int polygonCount() const { return _engine.polygonCount(); }
      };

int beamPolygonCount(const Beam* beam)
      {
      PolygonCountPaintDevice device;
      QPainter painter(&device);
      beam->draw(&painter);
      painter.end();
      return device.polygonCount();
      }

}

//---------------------------------------------------------
//   TestBeam
//---------------------------------------------------------

class TestBeam : public QObject, public MTest
      {
      Q_OBJECT

      void beam(const char* path);

   private slots:
      void initTestCase();
      void beamA()   { beam("Beam-A.mscx"); }
      void beamB()   { beam("Beam-B.mscx"); }
      void beamC()   { beam("Beam-C.mscx"); }
      void beamD()   { beam("Beam-D.mscx"); }
      void beamE()   { beam("Beam-E.mscx"); }
      void beamF()   { beam("Beam-F.mscx"); }
      void beamG()   { beam("Beam-G.mscx"); }
      void beam2()   { beam("Beam-2.mscx"); }
      void beam23()  { beam("Beam-23.mscx"); }
      void beamS0()  { beam("Beam-S0.mscx"); }
      void beamDir() { beam("Beam-dir.mscx"); }
      void beamCrossMeasure1();
      void beamCrossMeasure2() { beam("Beam-CrossM2.mscx"); }
      void beamCrossMeasure3() { beam("Beam-CrossM3.mscx"); }
      void beamCrossMeasure4() { beam("Beam-CrossM4.mscx"); }
      void beamLayoutDoesNotAccumulateSegments();
      };

//---------------------------------------------------------
//   initTestCase
//---------------------------------------------------------

void TestBeam::initTestCase()
      {
      initMTest();
      }

//---------------------------------------------------------
//   beam
//---------------------------------------------------------

void TestBeam::beam(const char* path)
      {
      MasterScore* score = readScore(DIR + path);
      QVERIFY(score);
      QVERIFY(saveCompareScore(score, path, DIR + path));
      delete score;
      }

//---------------------------------------------------------
//   beamCrossMeasure1
//   This method simulates following operations:
//   - Update the score
//   - Check if the beam has been recreated. If yes, this is wrong behaviour
//---------------------------------------------------------
void TestBeam::beamCrossMeasure1()
      {
      MasterScore* score = readScore(DIR + "Beam-CrossM1.mscx");
      QVERIFY(score);
      Measure* first_measure = score->firstMeasure();
      // find the first segment that has a chord
      Segment* s = first_measure->first(SegmentType::ChordRest);
      while (s && !s->element(0)->isChord())
            s = s->next(SegmentType::ChordRest);
      // locate the first beam
      ChordRest* first_note = toChordRest(s->element(0));
      Beam* b = first_note->beam();
      score->update();
      // locate the beam again, and check if it is still b
      Beam* new_b = first_note->beam();
      QCOMPARE(new_b, b);
      delete score;
      }

//---------------------------------------------------------
//   beamLayoutDoesNotAccumulateSegments
//---------------------------------------------------------

void TestBeam::beamLayoutDoesNotAccumulateSegments()
      {
      MasterScore* score = readScore(DIR + "../../testoves/bdat/note-cross-staff.ove-ref.mscx");
      QVERIFY(score);

      Measure* measure = score->firstMeasure()->nextMeasure();
      QVERIFY(measure);
      Segment* segment = measure->first(SegmentType::ChordRest);
      QVERIFY(segment);
      Element* element = segment->element(0);
      QVERIFY(element && element->isChordRest());
      Beam* beam = toChordRest(element)->beam();
      QVERIFY(beam);

      beam->layout1();
      QVERIFY(beam->cross());
      beam->layout();
      QCOMPARE(beamPolygonCount(beam), 1);
      beam->layout();
      QCOMPARE(beamPolygonCount(beam), 1);

      delete score;
      }
QTEST_MAIN(TestBeam)
#include "tst_beam.moc"
