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
#include "libmscore/undo.h"
#include "libmscore/excerpt.h"
#include "libmscore/part.h"
#include "libmscore/staff.h"
#include "libmscore/key.h"
#include "libmscore/utils.h"
#include "libmscore/measure.h"
#include "libmscore/segment.h"
#include "libmscore/chordrest.h"
#include "libmscore/harmony.h"
#include "libmscore/duration.h"
#include "libmscore/durationtype.h"
#include "libmscore/synthesizerstate.h"
#include "audio/midi/event.h"

#define DIR QString("libmscore/chordsymbol/")

using namespace Ms;

//---------------------------------------------------------
//   TestChordSymbol
//---------------------------------------------------------

class TestChordSymbol : public QObject, public MTest {
      Q_OBJECT

      MasterScore* test_pre(const char* p);
      void test_post(MasterScore* score, const char* p);

      void selectAllChordSymbols(MasterScore* score);
      void realizeSelectionVoiced(MasterScore* score, Voicing voicing);

   private slots:
      void initTestCase();
      void testExtend();
      void testClear();
      void testAddLink();
      void testAddPart();
      void testNoSystem();
      void testTranspose();
      void testTransposePart();
      void testRealizeClose();
      void testRealizeDrop2();
      void testRealize3Note();
      void testRealize4Note();
      void testRealize6Note();
      void testRealizeConcertPitch();
      void testRealizeTransposed();
      void testRealizeOverride();
      void testRealizeTriplet();
      void testRealizeDuration();
      void testRealizeJazz();
      void testRealizeSeparateStaff();
      void testRealizeSeparateStaffConcertPitch();
      void testRealizeSeparateStaffMultiSource();
      };

//---------------------------------------------------------
//   initTestCase
//---------------------------------------------------------

void TestChordSymbol::initTestCase()
      {
      initMTest();
      }

//---------------------------------------------------------
//   chordsymbol
//---------------------------------------------------------

MasterScore* TestChordSymbol::test_pre(const char* p)
      {
      QString p1 = DIR + p + ".mscx";
      MasterScore* score = readScore(p1);
      score->doLayout();
      return score;
      }

void TestChordSymbol::test_post(MasterScore* score, const char* p)
      {
      QString p1 = p;
      p1 += "-test.mscx";
      QString p2 = DIR + p + "-ref.mscx";
      QVERIFY(saveCompareScore(score, p1, p2));
      delete score;
      }

//---------------------------------------------------------
//   TestChordSymbol
///   select all chord symbols within the specified score
//---------------------------------------------------------
void TestChordSymbol::selectAllChordSymbols(MasterScore* score)
      {
      //find a chord symbol
      Segment* seg = score->firstSegment(SegmentType::ChordRest);
      Element* e = 0;
      while (seg) {
            e = seg->findAnnotation(ElementType::HARMONY,
                                              0, score->ntracks());
            if (e)
                  break;
            seg = seg->next1();
            }
      score->selectSimilar(e, false);
      }

//---------------------------------------------------------
//   realizeSelectionVoiced
///   realize the current selection of the score using
///   the specified voicing
//---------------------------------------------------------
void TestChordSymbol::realizeSelectionVoiced(MasterScore* score, Voicing voicing)
      {
      for (Element* e : score->selection().elements()) {
            if (e->isHarmony())
                  e->setProperty(Pid::HARMONY_VOICING, int(voicing));
            }
      score->startCmd();
      score->cmdRealizeChordSymbols();
      score->endCmd();
      }

void TestChordSymbol::testExtend()
      {
      MasterScore* score = test_pre("extend");
      Measure* m = score->firstMeasure();
      Segment* s = m->first(SegmentType::ChordRest);
      ChordRest* cr = s->cr(0);
      score->changeCRlen(cr, TDuration::DurationType::V_WHOLE);
      score->doLayout();
      test_post(score, "extend");
      }

void TestChordSymbol::testClear()
      {
      MasterScore* score = test_pre("clear");
      Measure* m = score->firstMeasure();
      score->select(m, SelectType::SINGLE, 0);
      score->cmdDeleteSelection();
      score->doLayout();
      test_post(score, "clear");
      }

void TestChordSymbol::testAddLink()
      {
      MasterScore* score = test_pre("add-link");
      Segment* seg = score->firstSegment(SegmentType::ChordRest);
      ChordRest* cr = seg->cr(0);
      Harmony* harmony = new Harmony(score);
      harmony->setHarmony("C7");
      harmony->setTrack(cr->track());
      harmony->setParent(cr->segment());
      score->undoAddElement(harmony);
      score->doLayout();
      test_post(score, "add-link");
      }

void TestChordSymbol::testAddPart()
      {
      MasterScore* score = test_pre("add-part");
      Segment* seg = score->firstSegment(SegmentType::ChordRest);
      ChordRest* cr = seg->cr(0);
      Harmony* harmony = new Harmony(score);
      harmony->setHarmony("C7");
      harmony->setTrack(cr->track());
      harmony->setParent(cr->segment());
      score->undoAddElement(harmony);
      score->doLayout();
      test_post(score, "add-part");
      }

void TestChordSymbol::testNoSystem()
      {
      MasterScore* score = test_pre("no-system");

      //
      // create first part
      //
      QList<Part*> parts;
      parts.append(score->parts().at(0));
      Score* nscore = new Score(score);

      Excerpt* ex = new Excerpt(score);
      ex->setPartScore(nscore);
      nscore->setExcerpt(ex);
      score->excerpts().append(ex);
      ex->setTitle(parts.front()->longName());
      ex->setParts(parts);
      Excerpt::createExcerpt(ex);
      QVERIFY(nscore);

//      nscore->setTitle(parts.front()->partName());
      nscore->style().set(Sid::createMultiMeasureRests, true);

      //
      // create second part
      //
      parts.clear();
      parts.append(score->parts().at(1));
      nscore = new Score(score);

      ex = new Excerpt(score);
      ex->setPartScore(nscore);
      nscore->setExcerpt(ex);
      score->excerpts().append(ex);
      ex->setTitle(parts.front()->longName());
      ex->setParts(parts);
      Excerpt::createExcerpt(ex);
      QVERIFY(nscore);

//      nscore->setTitle(parts.front()->partName());
      nscore->style().set(Sid::createMultiMeasureRests, true);

      score->setExcerptsChanged(true);
      score->doLayout();
      test_post(score, "no-system");
      }

void TestChordSymbol::testTranspose()
      {
      MasterScore* score = test_pre("transpose");
      score->startCmd();
      score->cmdSelectAll();
      score->transpose(TransposeMode::BY_INTERVAL, TransposeDirection::UP, Key::C, 4, false, true, true);
      score->endCmd();
      test_post(score, "transpose");
      }

void TestChordSymbol::testTransposePart()
      {
      MasterScore* score = test_pre("transpose-part");
      score->startCmd();
      score->cmdSelectAll();
      score->transpose(TransposeMode::BY_INTERVAL, TransposeDirection::UP, Key::C, 4, false, true, true);
      score->endCmd();
      test_post(score, "transpose-part");
      }

//---------------------------------------------------------
//   testRealizeClose
///   check close voicing algorithm
//---------------------------------------------------------
void TestChordSymbol::testRealizeClose()
      {
      MasterScore* score = test_pre("realize");
      selectAllChordSymbols(score);
      realizeSelectionVoiced(score, Voicing::CLOSE);
      test_post(score, "realize-close");
      }

//---------------------------------------------------------
//   testRealizeDrop2
///   check Drop 2 voicing algorithm
//---------------------------------------------------------
void TestChordSymbol::testRealizeDrop2()
      {
      MasterScore* score = test_pre("realize");
      selectAllChordSymbols(score);
      realizeSelectionVoiced(score, Voicing::DROP_2);
      test_post(score, "realize-drop2");
      }

//---------------------------------------------------------
//   testRealize3Note
///   check 3 note voicing algorithm
//---------------------------------------------------------
void TestChordSymbol::testRealize3Note()
      {
      MasterScore* score = test_pre("realize");
      selectAllChordSymbols(score);
      realizeSelectionVoiced(score, Voicing::THREE_NOTE);
      test_post(score, "realize-3note");
      }

//---------------------------------------------------------
//   testRealize4Note
///   check 4 note voicing algorithm
//---------------------------------------------------------
void TestChordSymbol::testRealize4Note()
      {
      MasterScore* score = test_pre("realize");
      selectAllChordSymbols(score);
      realizeSelectionVoiced(score, Voicing::FOUR_NOTE);
      test_post(score, "realize-4note");
      }

//---------------------------------------------------------
//   testRealize6Note
///   check 6 note voicing algorithm
//---------------------------------------------------------
void TestChordSymbol::testRealize6Note()
      {
      MasterScore* score = test_pre("realize");
      selectAllChordSymbols(score);
      realizeSelectionVoiced(score, Voicing::SIX_NOTE);
      test_post(score, "realize-6note");
      }

//---------------------------------------------------------
//   testRealizeConcertPitch
///   Check if the note pitches and tpcs are correct after realizing
///   chord symbols on transposed instruments.
//---------------------------------------------------------
void TestChordSymbol::testRealizeConcertPitch()
      {
      MasterScore* score = test_pre("realize-concert-pitch");
      //concert pitch off
      score->startCmd();
      score->cmdConcertPitchChanged(false, true);
      score->endCmd();

      //realize all chord symbols
      selectAllChordSymbols(score);
      score->startCmd();
      score->cmdRealizeChordSymbols();
      score->endCmd();
      test_post(score, "realize-concert-pitch");
      }

//---------------------------------------------------------
//   testRealizeTransposed
///   Check if the note pitches and tpcs are correct after
///   transposing the score
//---------------------------------------------------------
void TestChordSymbol::testRealizeTransposed()
      {
      MasterScore* score = test_pre("transpose");
      //transpose
      score->cmdSelectAll();
      score->transpose(TransposeMode::BY_INTERVAL, TransposeDirection::UP, Key::C, 4, false, true, true);

      //realize all chord symbols
      selectAllChordSymbols(score);
      score->startCmd();
      score->cmdRealizeChordSymbols();
      score->endCmd();
      test_post(score, "realize-transpose");
      }

//---------------------------------------------------------
//   testRealizeOverride
///   Check for correctness when using the override
///   feature for realizing chord symbols
//---------------------------------------------------------
void TestChordSymbol::testRealizeOverride()
      {
      MasterScore* score = test_pre("realize-override");
      //realize all chord symbols
      selectAllChordSymbols(score);
      score->startCmd();
      score->cmdRealizeChordSymbols(true, Voicing::ROOT_ONLY, HDuration::SEGMENT_DURATION);
      score->endCmd();
      test_post(score, "realize-override");
      }

//---------------------------------------------------------
//   testRealizeTriplet
///   Check for correctness when realizing chord symbols on triplets
//---------------------------------------------------------
void TestChordSymbol::testRealizeTriplet()
      {
      MasterScore* score = test_pre("realize-triplet");
      //realize all chord symbols
      selectAllChordSymbols(score);
      score->startCmd();
      score->cmdRealizeChordSymbols();
      score->endCmd();
      test_post(score, "realize-triplet");
      }

//---------------------------------------------------------
//   testRealizeDuration
///   Check for correctness when realizing chord symbols
///   with different durations
//---------------------------------------------------------
void TestChordSymbol::testRealizeDuration()
      {
      MasterScore* score = test_pre("realize-duration");
      //realize all chord symbols
      selectAllChordSymbols(score);
      score->startCmd();
      score->cmdRealizeChordSymbols();
      score->endCmd();
      test_post(score, "realize-duration");
      }

//---------------------------------------------------------
//   testRealizeJazz
///   Check for correctness when realizing chord symbols
///   with jazz mode
//---------------------------------------------------------
void TestChordSymbol::testRealizeJazz()
      {
      MasterScore* score = test_pre("realize-jazz");
      //realize all chord symbols
      selectAllChordSymbols(score);
      score->startCmd();
      score->cmdRealizeChordSymbols();
      score->endCmd();
      test_post(score, "realize-jazz");
      }

//---------------------------------------------------------
//   testRealizeSeparateStaff
//---------------------------------------------------------

void TestChordSymbol::testRealizeSeparateStaff()
      {
      MasterScore* score = test_pre("realize");
      const int originalPartCount = score->parts().size();
      const int originalStaffCount = score->nstaves();
      const int originalHarmonyCount = score->harmonyCount();

      selectAllChordSymbols(score);
      QList<Harmony*> harmonies;
      for (Element* e : score->selection().elements()) {
            if (e->isHarmony() && toHarmony(e)->isRealizable())
                  harmonies.append(toHarmony(e));
            }
      QVERIFY(harmonies.size() > 1);
      harmonies.front()->setProperty(Pid::VELOCITY, 96);
      Harmony* dynamicHarmony = harmonies.at(1);
      QCOMPARE(dynamicHarmony->velocity(), 0);
      const int expectedDynamicVelocity = qBound(
                  1, dynamicHarmony->staff()->velocities().val(dynamicHarmony->tick()), 127);

      EventMap events;
      SynthesizerState synthState;
      score->renderMidi(&events, synthState);
      bool foundHarmonyNoteOn = false;
      for (const auto& event : events) {
            if (event.second.harmony() == harmonies.front() && event.second.velo() > 0) {
                  QCOMPARE(event.second.velo(), 96);
                  foundHarmonyNoteOn = true;
                  }
            }
      QVERIFY(foundHarmonyNoteOn);

      score->startCmd();
      score->cmdRealizeChordSymbols(true, Voicing::ROOT_ONLY,
                                    HDuration::SEGMENT_DURATION, true);
      score->endCmd();

      QCOMPARE(score->parts().size(), originalPartCount + 1);
      QCOMPARE(score->nstaves(), originalStaffCount + 1);
      QCOMPARE(score->harmonyCount(), originalHarmonyCount);

      Part* realizationPart = score->parts().back();
      QCOMPARE(realizationPart->nstaves(), 1);
      QCOMPARE(realizationPart->partName(), QString("Chord Realization"));
      const int targetTrack = originalStaffCount * VOICES;

      for (Harmony* harmony : qAsConst(harmonies)) {
            Segment* segment = harmony->getParentSeg();
            QVERIFY(segment);
            Element* element = segment->element(targetTrack);
            QVERIFY(element);
            QVERIFY(element->isChord());

            Chord* chord = toChord(element);
            QCOMPARE(chord->notes().size(), 1);
            QCOMPARE(chord->upNote()->pitch(),
                     harmony->getRealizedHarmony().generateNotes(
                        harmony->rootTpc(), harmony->baseTpc(), true,
                        Voicing::ROOT_ONLY, 0).firstKey());
            }

      Note* firstNote = toChord(harmonies.front()->getParentSeg()->element(targetTrack))->upNote();
      QCOMPARE(firstNote->veloType(), Note::ValueType::USER_VAL);
      QCOMPARE(firstNote->veloOffset(), 96);

      Note* dynamicNote = toChord(dynamicHarmony->getParentSeg()->element(targetTrack))->upNote();
      QCOMPARE(dynamicNote->veloType(), Note::ValueType::USER_VAL);
      QCOMPARE(dynamicNote->veloOffset(), expectedDynamicVelocity);

      QTemporaryDir temporaryDir;
      QVERIFY(temporaryDir.isValid());
      const QString savedPath = temporaryDir.filePath("realized-chords.mscx");
      QVERIFY(saveScore(score, savedPath));

      MasterScore* reloadedScore = readCreatedScore(savedPath);
      QVERIFY(reloadedScore);
      QCOMPARE(reloadedScore->parts().size(), originalPartCount + 1);
      QCOMPARE(reloadedScore->nstaves(), originalStaffCount + 1);
      QCOMPARE(reloadedScore->harmonyCount(), originalHarmonyCount);

      selectAllChordSymbols(reloadedScore);
      Harmony* reloadedHarmony = nullptr;
      for (Element* e : reloadedScore->selection().elements()) {
            if (e->isHarmony() && toHarmony(e)->velocity() == 96) {
                  reloadedHarmony = toHarmony(e);
                  break;
                  }
            }
      QVERIFY(reloadedHarmony);
      Chord* reloadedChord = toChord(reloadedHarmony->getParentSeg()->element(targetTrack));
      QVERIFY(reloadedChord);
      QCOMPARE(reloadedChord->upNote()->veloType(), Note::ValueType::USER_VAL);
      QCOMPARE(reloadedChord->upNote()->veloOffset(), 96);
      delete reloadedScore;

      score->undoRedo(true, nullptr);
      QCOMPARE(score->parts().size(), originalPartCount);
      QCOMPARE(score->nstaves(), originalStaffCount);
      QCOMPARE(score->harmonyCount(), originalHarmonyCount);

      score->undoRedo(false, nullptr);
      QCOMPARE(score->parts().size(), originalPartCount + 1);
      QCOMPARE(score->nstaves(), originalStaffCount + 1);

      delete score;
      }

//---------------------------------------------------------
//   testRealizeSeparateStaffConcertPitch
//---------------------------------------------------------

void TestChordSymbol::testRealizeSeparateStaffConcertPitch()
      {
      MasterScore* score = test_pre("realize-concert-pitch");
      const int originalPartCount = score->parts().size();
      const int originalStaffCount = score->nstaves();

      score->startCmd();
      score->cmdConcertPitchChanged(false, true);
      score->endCmd();

      Staff* sourceStaff = score->staff(0);
      QVERIFY(sourceStaff);
      QCOMPARE(sourceStaff->key(Fraction(0, 1)), Key::B_B);

      selectAllChordSymbols(score);
      Harmony* firstHarmony = nullptr;
      for (Element* e : score->selection().elements()) {
            if (e->isHarmony() && e->tick() == Fraction(0, 1)) {
                  firstHarmony = toHarmony(e);
                  break;
                  }
            }
      QVERIFY(firstHarmony);

      score->startCmd();
      score->cmdRealizeChordSymbols(true, Voicing::ROOT_ONLY,
                                    HDuration::SEGMENT_DURATION, true);
      score->endCmd();

      QCOMPARE(score->parts().size(), originalPartCount + 1);
      QCOMPARE(score->nstaves(), originalStaffCount + 1);

      Part* realizationPart = score->parts().back();
      QCOMPARE(realizationPart->nstaves(), 1);
      Staff* targetStaff = realizationPart->staff(0);
      QVERIFY(targetStaff);
      QVERIFY(targetStaff->part()->instrument(Fraction(0, 1))->transpose().isZero());
      QCOMPARE(targetStaff->key(Fraction(0, 1)), Key::A_B);

      Segment* segment = firstHarmony->getParentSeg();
      QVERIFY(segment);
      Element* element = segment->element(targetStaff->idx() * VOICES + firstHarmony->voice());
      QVERIFY(element);
      QVERIFY(element->isChord());

      Chord* chord = toChord(element);
      QCOMPARE(chord->notes().size(), 1);
      QCOMPARE(chord->upNote()->pitch(), 41);
      QCOMPARE(chord->upNote()->tpc1(), int(Tpc::TPC_F));
      QCOMPARE(chord->upNote()->tpc2(), int(Tpc::TPC_F));

      delete score;
      }

//---------------------------------------------------------
//   testRealizeSeparateStaffMultiSource
//---------------------------------------------------------

void TestChordSymbol::testRealizeSeparateStaffMultiSource()
      {
      MasterScore* score = test_pre("no-system");

      const int originalPartCount = score->parts().size();
      const int originalStaffCount = score->nstaves();
      QCOMPARE(originalStaffCount, 2);

      Segment* segment = score->firstSegment(SegmentType::ChordRest);
      QVERIFY(segment);
      QCOMPARE(segment->tick(), Fraction(0, 1));

      Harmony* secondHarmony = nullptr;
      for (Element* e : segment->annotations()) {
            if (e->isHarmony()) {
                  secondHarmony = toHarmony(e);
                  break;
                  }
            }
      QVERIFY(secondHarmony);
      QCOMPARE(secondHarmony->staffIdx(), 1);

      Harmony* firstHarmony = secondHarmony->clone();
      firstHarmony->setTrack(0);
      firstHarmony->setParent(segment);
      firstHarmony->setHarmony("Cb");
      score->staff(0)->part()->instrument()->setTranspose(Ms::Interval(-1, -2));
      score->startCmd();
      score->undoAddElement(firstHarmony);
      score->endCmd();

      QCOMPARE(firstHarmony->staffIdx(), 0);
      QCOMPARE(firstHarmony->getParentSeg(), secondHarmony->getParentSeg());
      QCOMPARE(firstHarmony->rootTpc(), int(Tpc::TPC_C_B));
      QCOMPARE(firstHarmony->velocity(), 0);
      QCOMPARE(secondHarmony->velocity(), 0);
      QVERIFY(score->staff(0)->keyList()->empty());
      QCOMPARE(score->staff(1)->key(Fraction(0, 1)), Key::A);

      QList<Harmony*> sourceHarmonies { firstHarmony, secondHarmony };
      QList<int> expectedPitches;
      QList<int> expectedTpcs;
      QList<int> expectedVelocities;
      for (Harmony* harmony : qAsConst(sourceHarmonies)) {
            const auto transpose = harmony->staff()->part()->instrument(harmony->tick())->transpose();
            const int offset = score->styleB(Sid::concertPitch) ? 0 : transpose.chromatic;
            expectedPitches.append(harmony->getRealizedHarmony().generateNotes(
                        harmony->rootTpc(), harmony->baseTpc(), true,
                        Voicing::ROOT_ONLY, offset).firstKey());
            expectedTpcs.append(score->styleB(Sid::concertPitch)
                        ? harmony->rootTpc()
                        : transposeTpc(harmony->rootTpc(), transpose, true));
            expectedVelocities.append(qBound(
                        1, harmony->staff()->velocities().val(harmony->tick()), 127));
            }

      score->select(firstHarmony, SelectType::SINGLE, 0);
      score->select(secondHarmony, SelectType::ADD, 0);

      score->startCmd();
      score->cmdRealizeChordSymbols(true, Voicing::ROOT_ONLY,
                                    HDuration::SEGMENT_DURATION, true);
      score->endCmd();

      QCOMPARE(score->parts().size(), originalPartCount + 1);
      QCOMPARE(score->nstaves(), originalStaffCount + 2);

      Part* realizationPart = score->parts().back();
      QCOMPARE(realizationPart->nstaves(), 2);

      const QList<Key> expectedKeys { Key::B_B, Key::C };
      QList<Element*> realizedElements;
      for (int i = 0; i < sourceHarmonies.size(); ++i) {
            Harmony* sourceHarmony = sourceHarmonies.at(i);
            Staff* targetStaff = realizationPart->staff(i);
            QVERIFY(targetStaff);
            QCOMPARE(targetStaff->key(Fraction(0, 1)), expectedKeys.at(i));

            Element* element = segment->element(targetStaff->idx() * VOICES + sourceHarmony->voice());
            QVERIFY(element);
            QVERIFY(element->isChord());
            realizedElements.append(element);

            Chord* chord = toChord(element);
            QCOMPARE(chord->notes().size(), 1);
            QCOMPARE(chord->upNote()->pitch(), expectedPitches.at(i));
            QCOMPARE(chord->upNote()->tpc1(), expectedTpcs.at(i));
            QCOMPARE(chord->upNote()->tpc2(), expectedTpcs.at(i));
            QCOMPARE(chord->upNote()->veloType(), Note::ValueType::USER_VAL);
            QCOMPARE(chord->upNote()->veloOffset(), expectedVelocities.at(i));
            }
      QCOMPARE(realizedElements.size(), 2);
      QVERIFY(realizedElements.at(0) != realizedElements.at(1));

      delete score;
      }


QTEST_MAIN(TestChordSymbol)
#include "tst_chordsymbol.moc"
