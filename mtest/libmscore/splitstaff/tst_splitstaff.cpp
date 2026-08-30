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
#include "libmscore/measure.h"
#include "libmscore/segment.h"
#include "libmscore/chordrest.h"
#include "libmscore/chord.h"
#include "libmscore/clef.h"
#include "libmscore/staff.h"
#include "libmscore/harmony.h"

#define DIR QString("libmscore/splitstaff/")

using namespace Ms;

//---------------------------------------------------------
//   TestSplitStaff
//---------------------------------------------------------

class TestSplitStaff : public QObject, public MTest
      {
      Q_OBJECT

      void splitstaff(int, int);

   private slots:
      void initTestCase();
      void splitstaff01() { splitstaff(1, 0); } //single notes
      void splitstaff02() { splitstaff(2, 0); } //chord
      void splitstaff03() { splitstaff(3, 1); } //non-top staff
      void splitstaff04() { splitstaff(4, 0); } //slur up
      void splitstaff05() { splitstaff(5, 0); } //slur down
      void splitstaff06() { splitstaff(6, 0); } //tuplet
      void splitSelectedChord();
      };

//---------------------------------------------------------
//   initTestCase
//---------------------------------------------------------

void TestSplitStaff::initTestCase()
      {
      initMTest();
      }

//---------------------------------------------------------
///   splitstaff
//---------------------------------------------------------

void TestSplitStaff::splitstaff(int idx, int staffIdx)
      {
      MasterScore* score = readScore(DIR + QString("splitstaff0%1.mscx").arg(idx));
      score->startCmd();
      score->splitStaff(staffIdx, 60);
      score->endCmd();

      QVERIFY(saveCompareScore(score, QString("splitstaff0%1.mscx").arg(idx),
         DIR + QString("splitstaff0%1-ref.mscx").arg(idx)));
      delete score;
      }

//---------------------------------------------------------
//   splitSelectedChord
//---------------------------------------------------------

void TestSplitStaff::splitSelectedChord()
      {
      MasterScore* score = readScore(DIR + "splitstaff02.mscx");
      QVERIFY(score);

      Measure* measure = score->firstMeasure();
      QVERIFY(measure);
      Chord* source = measure->findChord(Fraction(0, 1), 0);
      QVERIFY(source);
      QCOMPARE(source->notes().size(), size_t(5));

      // Keep an explicit harmony symbol so the test verifies theoretical
      // root matching rather than only the lowest-note fallback.
      score->startCmd();
      Harmony* harmony = new Harmony(score);
      harmony->setTrack(0);
      harmony->setRootTpc(Tpc::TPC_C);
      harmony->setParent(source->segment());
      score->undoAddElement(harmony);
      score->endCmd();

      // A range selection over the chord identifies all of its notes.
      score->select(source, SelectType::RANGE, 0);
      score->startCmd();
      QVERIFY(score->splitStaffRootsFromSelection());
      score->endCmd();

      source = measure->findChord(Fraction(0, 1), 0);
      Chord* destination = measure->findChord(Fraction(0, 1), VOICES);
      QVERIFY(source);
      QVERIFY(destination);
      QCOMPARE(score->nstaves(), 2);
      QCOMPARE(source->notes().size(), size_t(4));
      QCOMPARE(destination->notes().size(), size_t(1));
      QCOMPARE(source->notes().front()->pitch(), 52);
      QCOMPARE(source->notes().back()->pitch(), 64);
      QCOMPARE(destination->notes().front()->pitch(), 48);

      score->undoRedo(true, nullptr);
      score->undoRedo(false, nullptr);
      QCOMPARE(score->nstaves(), 2);
      QCOMPARE(measure->findChord(Fraction(0, 1), 0)->notes().size(), size_t(4));
      QCOMPARE(measure->findChord(Fraction(0, 1), VOICES)->notes().size(), size_t(1));

      delete score;

      // A chord without a harmony symbol falls back to moving its lowest note.
      score = readScore(DIR + "splitstaff02.mscx");
      QVERIFY(score);
      measure = score->firstMeasure();
      source = measure->findChord(Fraction(0, 1), 0);
      QVERIFY(source);
      score->startCmd();
      score->undoChangeClef(score->staff(0), measure, ClefType::F);
      score->endCmd();
      score->select(source->notes().front(), SelectType::SINGLE, 0);
      score->startCmd();
      QVERIFY(score->splitStaffRootsFromSelection());
      score->endCmd();
      QCOMPARE(score->staff(0)->clef(Fraction(0, 1)), ClefType::G);
      QVERIFY(measure->findChord(Fraction(0, 1), 0));
      QCOMPARE(measure->findChord(Fraction(0, 1), 0)->notes().size(), size_t(4));
      QCOMPARE(measure->findChord(Fraction(0, 1), VOICES)->notes().size(), size_t(1));

      score->undoRedo(true, nullptr);
      QCOMPARE(score->nstaves(), 1);
      QCOMPARE(measure->findChord(Fraction(0, 1), 0)->notes().size(), size_t(5));
      delete score;
      }

QTEST_MAIN(TestSplitStaff)
#include "tst_splitstaff.moc"
