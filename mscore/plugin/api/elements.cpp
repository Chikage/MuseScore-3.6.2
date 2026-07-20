//=============================================================================
//  MuseScore
//  Music Composition & Notation
//
//  Copyright (C) 2019 Werner Schweer
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 2
//  as published by the Free Software Foundation and appearing in
//  the file LICENCE.GPL
//=============================================================================

#include "elements.h"
#include "fraction.h"
#include "part.h"
#include "libmscore/pitchspelling.h"
#include "libmscore/property.h"
#include "libmscore/tie.h"
#include "libmscore/undo.h"
#include "libmscore/utils.h"

namespace Ms {
namespace PluginAPI {

//---------------------------------------------------------
//   symbolIdFromVariant
//---------------------------------------------------------

static bool symbolIdFromVariant(const QVariant& value, SymId* symId)
      {
      if (value.type() == QVariant::String) {
            bool ok = false;
            const int numericId = value.toString().toInt(&ok);
            if (ok) {
                  if (numericId > int(SymId::noSym) && numericId <= int(SymId::lastSym)) {
                        *symId = SymId(numericId);
                        return true;
                        }
                  return false;
                  }

            const SymId id = Sym::name2id(value.toString());
            if (id != SymId::noSym) {
                  *symId = id;
                  return true;
                  }
            return false;
            }

      bool ok = false;
      const int numericId = value.toInt(&ok);
      if (ok && numericId > int(SymId::noSym) && numericId <= int(SymId::lastSym)) {
            *symId = SymId(numericId);
            return true;
            }

      return false;
      }

//---------------------------------------------------------
//   keySymFromVariant
//---------------------------------------------------------

static bool keySymFromVariant(const QVariant& value, KeySym* keySym)
      {
      QVariant symbolValue;
      qreal x = 0.0;
      qreal y = 0.0;

      const QVariantMap map = value.toMap();
      if (!map.isEmpty()) {
            if (map.contains("symbol"))
                  symbolValue = map.value("symbol");
            else if (map.contains("sym"))
                  symbolValue = map.value("sym");
            else if (map.contains("symId"))
                  symbolValue = map.value("symId");

            x = map.value("x", 0.0).toReal();
            y = map.value("y", 0.0).toReal();

            if (map.contains("pos")) {
                  const QVariant posValue = map.value("pos");
                  if (posValue.canConvert<QPointF>()) {
                        const QPointF pos = posValue.toPointF();
                        x = pos.x();
                        y = pos.y();
                        }
                  else {
                        const QVariantMap posMap = posValue.toMap();
                        if (!posMap.isEmpty()) {
                              x = posMap.value("x", x).toReal();
                              y = posMap.value("y", y).toReal();
                              }
                        }
                  }
            }
      else {
            const QVariantList list = value.toList();
            if (list.size() >= 3) {
                  symbolValue = list.at(0);
                  x = list.at(1).toReal();
                  y = list.at(2).toReal();
                  }
            else {
                  symbolValue = value;
                  }
            }

      SymId sym = SymId::noSym;
      if (!symbolIdFromVariant(symbolValue, &sym))
            return false;

      keySym->sym = sym;
      keySym->spos = QPointF(x, y);
      keySym->pos = QPointF();
      return true;
      }

//---------------------------------------------------------
//   Element::setOffsetX
//---------------------------------------------------------

void Element::setOffsetX(qreal offX)
      {
      const qreal offY = element()->offset().y() / element()->spatium();
      set(Ms::Pid::OFFSET, QPointF(offX, offY));
      }

//---------------------------------------------------------
//   Element::setOffsetY
//---------------------------------------------------------

void Element::setOffsetY(qreal offY)
      {
      const qreal offX = element()->offset().x() / element()->spatium();
      set(Ms::Pid::OFFSET, QPointF(offX, offY));
      }

//---------------------------------------------------------
//   Element::bbox
//   return the element bbox in spatium units, rather than in raster units as stored internally
//---------------------------------------------------------

QRectF Element::bbox() const
      {
      QRectF bbox       = element()->bbox();
      qreal  spatium    = element()->spatium();
      return QRectF(bbox.x() / spatium, bbox.y() / spatium, bbox.width() / spatium, bbox.height() / spatium);
      }

//---------------------------------------------------------
//   Segment::elementAt
//---------------------------------------------------------

Element* Segment::elementAt(int track)
      {
      Ms::Element* el = segment()->elementAt(track);
      if (!el)
            return nullptr;
      return wrap(el, Ownership::SCORE);
      }

//---------------------------------------------------------
//   Note::setTpc
//---------------------------------------------------------

void Note::setTpc(int val)
      {
      if (!tpcIsValid(val)) {
            qWarning("PluginAPI::Note::setTpc: invalid tpc: %d", val);
            return;
            }

      if (note()->concertPitch())
            set(Pid::TPC1, val);
      else
            set(Pid::TPC2, val);
      }

//---------------------------------------------------------
//   Note::accidentalSymbolName
//---------------------------------------------------------

QString Note::accidentalSymbolName() const
      {
      const SymId id = Accidental::subtype2symbol(note()->accidentalType());
      return id == SymId::noSym ? QString() : QString(Sym::id2name(id));
      }

//---------------------------------------------------------
//   Note::accidentalSymbolId
//---------------------------------------------------------

int Note::accidentalSymbolId() const
      {
      return int(Accidental::subtype2symbol(note()->accidentalType()));
      }

//---------------------------------------------------------
//   Note::setAccidentalSymbol
//---------------------------------------------------------

static bool accidentalTypeFromSymbol(const QVariant& symbol, AccidentalType* accidentalType)
      {
      SymId id = SymId::noSym;
      if (!symbolIdFromVariant(symbol, &id))
            return false;

      for (int i = int(AccidentalType::NONE) + 1; i < int(AccidentalType::END); ++i) {
            const AccidentalType type = AccidentalType(i);
            if (Accidental::subtype2symbol(type) == id) {
                  *accidentalType = type;
                  return true;
                  }
            }

      return false;
      }

struct TpcCarrierNoteState {
      Ms::Note* note;
      int pitch;
      int rawLine;
      Ms::Tie* tieBack;
      Ms::Tie* tieFor;
      bool needsAccidental;

      TpcCarrierNoteState(Ms::Note* n, bool needsCarrier)
         : note(n),
           pitch(n->pitch()),
           rawLine(n->getProperty(Pid::LINE).toInt()),
           tieBack(n->tieBack()),
           tieFor(n->tieFor()),
           needsAccidental(needsCarrier)
            {
            }
      };

static bool appendTpcCarrierNoteState(QList<TpcCarrierNoteState>* states,
                                      Ms::Note* note, bool needsAccidental)
      {
      for (TpcCarrierNoteState& state : *states) {
            if (state.note == note) {
                  state.needsAccidental = state.needsAccidental || needsAccidental;
                  return false;
                  }
            }

      states->append(TpcCarrierNoteState(note, needsAccidental));
      return true;
      }

static QList<TpcCarrierNoteState> tpcCarrierNoteStates(Ms::Note* note)
      {
      QList<TpcCarrierNoteState> states;

      // changeAccidental() propagates pitch/TPC to linked heads, but propagates
      // ties only within linked scores that use the same concert-pitch mode.
      // Work on the complete closure so excerpts cannot retain stale tied TPCs.
      for (Ms::ScoreElement* scoreElement : note->linkList()) {
            Ms::Note* tiedNote = toNote(scoreElement)->firstTiedNote();
            bool isLinkedHead = true;

            while (tiedNote) {
                  const bool inserted = appendTpcCarrierNoteState(
                     &states, tiedNote, isLinkedHead || tiedNote->accidental());
                  if (!inserted)
                        break;

                  isLinkedHead = false;
                  Ms::Tie* tie = tiedNote->tieFor();
                  tiedNote = tie ? tie->endNote() : nullptr;
                  }
            }

      return states;
      }

static bool tpcCarrierPitchAndTpcs(Ms::Note* note, AccidentalType type,
                                   int* pitch, int* tpc1, int* tpc2)
      {
      if (Accidental::isMicrotonal(type))
            return false;

      Ms::Chord* chord = note->chord();
      if (!chord || !chord->segment())
            return false;

      Ms::Score* score = note->score();
      Ms::Staff* effectiveStaff = score->staff(
         chord->staffIdx() + chord->staffMove());
      if (!effectiveStaff)
            return false;

      const ClefType clef = effectiveStaff->clef(chord->tick());
      int step = ClefInfo::pitchOffset(clef) - note->line();
      while (step < 0)
            step += 7;
      step %= 7;

      const AccidentalVal alteration = Accidental::subtype2value(type);
      *pitch = line2pitch(note->line(), clef, Key::C) + int(alteration);
      if (!note->concertPitch())
            *pitch += note->transposition();

      const int displayedTpc = step2tpc(step, alteration);
      if (!tpcIsValid(displayedTpc))
            return false;

      const int otherTpc = note->transposeTpc(displayedTpc);
      if (!tpcIsValid(otherTpc))
            return false;

      if (note->concertPitch()) {
            *tpc1 = displayedTpc;
            *tpc2 = otherTpc;
            }
      else {
            *tpc1 = otherTpc;
            *tpc2 = displayedTpc;
            }

      return true;
      }

static AccidentalType tpcCarrierAccidentalType(int tpc)
      {
      AccidentalType type = Accidental::value2subtype(tpc2alter(tpc));
      return type == AccidentalType::NONE ? AccidentalType::NATURAL : type;
      }

static void addTpcCarrierAccidental(Ms::Note* note, AccidentalType type,
                                    int markerZ)
      {
      Ms::Score* score = note->score();
      if (Ms::Accidental* oldAccidental = note->accidental())
            score->undoRemoveElement(oldAccidental);

      Ms::Accidental* accidental = new Ms::Accidental(score);
      accidental->setParent(note);
      accidental->setAccidentalType(type);
      accidental->setRole(AccidentalRole::USER);
      accidental->setZ(markerZ);
      accidental->setVisible(false);
      score->undoAddElement(accidental);
      }

bool Note::setAccidentalSymbol(const QVariant& symbol)
      {
      AccidentalType type = AccidentalType::NONE;
      if (!accidentalTypeFromSymbol(symbol, &type))
            return false;

      setAccidentalType(type);
      return true;
      }

//---------------------------------------------------------
//   Note::markAccidentalAsTpcCarrier
//---------------------------------------------------------

bool Note::markAccidentalAsTpcCarrier(int markerZ)
      {
      QList<Ms::Accidental*> accidentals;
      bool hasCurrentAccidental = false;

      for (Ms::ScoreElement* scoreElement : note()->linkList()) {
            Ms::Note* linkedNote = toNote(scoreElement);
            Ms::Accidental* accidental = linkedNote->accidental();
            if (!accidental)
                  continue;

            accidentals.append(accidental);
            if (linkedNote == note())
                  hasCurrentAccidental = true;
            }

      // Validate before writing so false never leaves another linked score
      // partially marked.
      if (!hasCurrentAccidental)
            return false;

      for (Ms::Accidental* accidental : accidentals) {
            accidental->undoChangeProperty(Pid::Z, markerZ);
            accidental->undoChangeProperty(Pid::VISIBLE, false);
            }

      return true;
      }

//---------------------------------------------------------
//   Note::setAccidentalSymbolAsTpcCarrier
//---------------------------------------------------------

bool Note::setAccidentalSymbolAsTpcCarrier(const QVariant& symbol, int markerZ)
      {
      AccidentalType type = AccidentalType::NONE;
      if (!accidentalTypeFromSymbol(symbol, &type))
            return false;

      int targetPitch = 0;
      int targetTpc1 = Tpc::TPC_INVALID;
      int targetTpc2 = Tpc::TPC_INVALID;
      if (!tpcCarrierPitchAndTpcs(note(), type, &targetPitch,
                                 &targetTpc1, &targetTpc2))
            return false;

      QList<TpcCarrierNoteState> states = tpcCarrierNoteStates(note());
      if (states.isEmpty())
            return false;

      // Complete every compatibility check before the first undo command. A
      // false result is therefore an API-level no-op, not a partially applied
      // accidental change that depends on the QML caller rolling back.
      for (const TpcCarrierNoteState& state : states) {
            if (state.pitch != targetPitch)
                  return false;

            if (state.needsAccidental) {
                  const int displayedTpc = state.note->concertPitch()
                     ? targetTpc1 : targetTpc2;
                  const AccidentalType carrierType =
                     tpcCarrierAccidentalType(displayedTpc);
                  if (Accidental::subtype2symbol(carrierType) == SymId::noSym)
                        return false;
                  }
            }

      // Set TPC directly while reusing each note's exact original pitch. This
      // avoids changeAccidental(), whose pitch-recalculation path can remove
      // ties, and also covers tied continuations in every linked score mode.
      for (const TpcCarrierNoteState& state : states) {
            if (state.note->tpc1() != targetTpc1 ||
                state.note->tpc2() != targetTpc2) {
                  state.note->score()->undo(new ChangePitch(
                     state.note, state.pitch, targetTpc1, targetTpc2));
                  }
            }

      // LINE is derived from pitch/TPC, but ChangePitch does not include it in
      // its undo state. Calculate it now, restore the old raw value, then apply
      // the result through the undo stack so linked excerpts also undo cleanly.
      for (const TpcCarrierNoteState& state : states) {
            state.note->updateLine();
            const int targetLine = state.note->getProperty(Pid::LINE).toInt();
            state.note->setLine(state.rawLine);
            if (targetLine != state.rawLine)
                  state.note->undoChangeProperty(Pid::LINE, targetLine);
            }

      for (const TpcCarrierNoteState& state : states) {
            if (!state.needsAccidental)
                  continue;

            const int displayedTpc = state.note->tpc();
            addTpcCarrierAccidental(
               state.note, tpcCarrierAccidentalType(displayedTpc), markerZ);
            }

#ifndef QT_NO_DEBUG
      for (const TpcCarrierNoteState& state : states) {
            Q_ASSERT(state.note->pitch() == state.pitch);
            Q_ASSERT(state.note->tieBack() == state.tieBack);
            Q_ASSERT(state.note->tieFor() == state.tieFor);
            }
#endif

      return true;
      }

//---------------------------------------------------------
//   Note::isChildAllowed
///   Check if element type can be a child of note.
///   \since MuseScore 3.3.3
//---------------------------------------------------------

bool Note::isChildAllowed(Ms::ElementType elementType)
      {
      switch(elementType) {
            case ElementType::NOTEHEAD:
            case ElementType::NOTEDOT:
            case ElementType::FINGERING:
            case ElementType::SYMBOL:
            case ElementType::IMAGE:
            case ElementType::TEXT:
            case ElementType::BEND:
            case ElementType::TIE:
            case ElementType::ACCIDENTAL:
            case ElementType::TEXTLINE:
            case ElementType::GLISSANDO:
                  return true;
            default:
                  return false;
            }
      }


//---------------------------------------------------------
//   Note::add
///   \since MuseScore 3.3.3
//---------------------------------------------------------

void Note::add(Ms::PluginAPI::Element* wrapped)
      {
      Ms::Element* s = wrapped ? wrapped->element() : nullptr;
      if (s)
            {
            // Ensure that the object has the expected ownership
            if (wrapped->ownership() == Ownership::SCORE) {
                  qWarning("Note::add: Cannot add this element. The element is already part of the score.");
                  return;        // Don't allow operation.
                  }
            // Score now owns the object.
            wrapped->setOwnership(Ownership::SCORE);

            addInternal(note(), s);
            }
      }

//---------------------------------------------------------
//   Note::addInternal
///   \since MuseScore 3.3.3
//---------------------------------------------------------

void Note::addInternal(Ms::Note* note, Ms::Element* s)
      {
      // Provide parentage for element.
      s->setScore(note->score());
      s->setParent(note);
      s->setTrack(note->track());

      if (s && isChildAllowed(s->type())) {
            // Create undo op and add the element.
            toScore(note->score())->undoAddElement(s);
            }
      else if (s) {
            qDebug("Note::add() not impl. %s", s->name());
            }
      }

//---------------------------------------------------------
//   Note::remove
///   \since MuseScore 3.3.3
//---------------------------------------------------------

void Note::remove(Ms::PluginAPI::Element* wrapped)
      {
      Ms::Element* s = wrapped->element();
      if (!s)
            qWarning("PluginAPI::Note::remove: Unable to retrieve element. %s", qPrintable(wrapped->name()));
      else if (s->parent() != note())
            qWarning("PluginAPI::Note::remove: The element is not a child of this note. Use removeElement() instead.");
      else if (isChildAllowed(s->type()))
            note()->score()->deleteItem(s); // Create undo op and remove the element.
      else
            qDebug("Note::remove() not impl. %s", s->name());
      }

//---------------------------------------------------------
//   DurationElement::globalDuration
//---------------------------------------------------------

FractionWrapper* DurationElement::globalDuration() const
      {
      return wrap(durationElement()->globalTicks());
      }

//---------------------------------------------------------
//   DurationElement::actualDuration
//---------------------------------------------------------

FractionWrapper* DurationElement::actualDuration() const
      {
      return wrap(durationElement()->actualTicks());
      }

//---------------------------------------------------------
//   DurationElement::parentTuplet
//---------------------------------------------------------

Tuplet* DurationElement::parentTuplet()
      {
      return wrap<Tuplet>(durationElement()->tuplet());
      }

//---------------------------------------------------------
//   KeySig::setKey
//---------------------------------------------------------

void KeySig::setKey(int key)
      {
      KeySigEvent event = keySig()->keySigEvent();
      event.setKey(Ms::Key(key));
      applyKeySigEvent(event);
      }

//---------------------------------------------------------
//   KeySig::customSymbols
//---------------------------------------------------------

QVariantList KeySig::customSymbols() const
      {
      QVariantList result;
      const QList<KeySym>& keySymbols = keySig()->keySigEvent().keySymbols();
      for (const KeySym& keySymbol : keySymbols) {
            QVariantMap item;
            item.insert("symbol", QString(Sym::id2name(keySymbol.sym)));
            item.insert("sym", int(keySymbol.sym));
            item.insert("x", keySymbol.spos.x());
            item.insert("y", keySymbol.spos.y());
            result.append(item);
            }
      return result;
      }

//---------------------------------------------------------
//   KeySig::setCustomKeySymbols
//---------------------------------------------------------

bool KeySig::setCustomKeySymbols(const QVariantList& symbols)
      {
      KeySigEvent event = keySig()->keySigEvent();
      QList<KeySym> keySymbols;
      for (const QVariant& symbolValue : symbols) {
            KeySym keySymbol;
            if (!keySymFromVariant(symbolValue, &keySymbol)) {
                  qWarning("PluginAPI::KeySig::setCustomKeySymbols: invalid symbol entry");
                  return false;
                  }
            keySymbols.append(keySymbol);
            }

      event.setCustom(true);
      event.keySymbols().clear();
      event.keySymbols() = keySymbols;
      applyKeySigEvent(event);
      return true;
      }

//---------------------------------------------------------
//   KeySig::applyKeySigEvent
//---------------------------------------------------------

void KeySig::applyKeySigEvent(const KeySigEvent& event)
      {
      Ms::KeySig* ks = keySig();
      if (ownership() == Ownership::SCORE && ks->score() && ks->segment() && ks->staff()) {
            ks->undoChangeProperty(Pid::GENERATED, false);
            ks->score()->undo(new ChangeKeySig(ks, event, ks->showCourtesy()));
            }
      else {
            ks->setKeySigEvent(event);
            ks->setGenerated(false);
            ks->triggerLayout();
            }
      }

//---------------------------------------------------------
//   Chord::setPlayEventType
//---------------------------------------------------------

void Chord::setPlayEventType(Ms::PlayEventType v)
      {
      // Only create undo operation if the value has changed.
      if (v != chord()->playEventType())
            {
            chord()->score()->setPlaylistDirty();
            chord()->score()->undo(new ChangeChordPlayEventType(chord(), v));
            }
      }

//---------------------------------------------------------
//   Chord::add
//---------------------------------------------------------

void Chord::add(Ms::PluginAPI::Element* wrapped)
      {
      Ms::Element* s = wrapped ? wrapped->element() : nullptr;
      if (s)
            {
            // Ensure that the object has the expected ownership
            if (wrapped->ownership() == Ownership::SCORE) {
                  qWarning("Chord::add: Cannot add this element. The element is already part of the score.");
                  return;        // Don't allow operation.
                  }
            // Score now owns the object.
            wrapped->setOwnership(Ownership::SCORE);

            addInternal(chord(), s);
            }
      }

//---------------------------------------------------------
//   Chord::addInternal
//---------------------------------------------------------

void Chord::addInternal(Ms::Chord* chord, Ms::Element* s)
      {
      // Provide parentage for element.
      s->setScore(chord->score());
      s->setParent(chord);
      // If a note, ensure the element has proper Tpc values. (Will crash otherwise)
      if (s->isNote()) {
            s->setTrack(chord->track());
            toNote(s)->setTpcFromPitch();
            }
      // Create undo op and add the element.
      chord->score()->undoAddElement(s);
      }

//---------------------------------------------------------
//   Page::pagenumber
//---------------------------------------------------------

int Page::pagenumber() const
      {
      return page()->no();
      }

//---------------------------------------------------------
//   Chord::remove
//---------------------------------------------------------

void Chord::remove(Ms::PluginAPI::Element* wrapped)
      {
      Ms::Element* s = wrapped->element();
      if (!s)
            qWarning("PluginAPI::Chord::remove: Unable to retrieve element. %s", qPrintable(wrapped->name()));
      else if (s->parent() != chord())
            qWarning("PluginAPI::Chord::remove: The element is not a child of this chord. Use removeElement() instead.");
      else if (chord()->notes().size() <= 1 && s->type() == ElementType::NOTE)
            qWarning("PluginAPI::Chord::remove: Removal of final note is not allowed.");
      else
            chord()->score()->deleteItem(s); // Create undo op and remove the element.
      }

//---------------------------------------------------------
//   Staff::part
//---------------------------------------------------------

Part* Staff::part()
      {
      return wrap<Part>(staff()->part());
      }

//---------------------------------------------------------
//   wrap
///   \cond PLUGIN_API \private \endcond
///   Wraps Ms::Element choosing the correct wrapper type
///   at runtime based on the actual element type.
//---------------------------------------------------------

Element* wrap(Ms::Element* e, Ownership own)
      {
      if (!e)
            return nullptr;

      using Ms::ElementType;
      switch(e->type()) {
            case ElementType::NOTE:
                  return wrap<Note>(toNote(e), own);
            case ElementType::CHORD:
                  return wrap<Chord>(toChord(e), own);
            case ElementType::TUPLET:
                  return wrap<Tuplet>(toTuplet(e), own);
            case ElementType::SEGMENT:
                  return wrap<Segment>(toSegment(e), own);
            case ElementType::MEASURE:
                  return wrap<Measure>(toMeasure(e), own);
            case ElementType::PAGE:
                  return wrap<Page>(toPage(e), own);
            case ElementType::KEYSIG:
                  return wrap<KeySig>(toKeySig(e), own);
            default:
                  if (e->isDurationElement()) {
                        if (e->isChordRest())
                              return wrap<ChordRest>(toChordRest(e), own);
                        return wrap<DurationElement>(toDurationElement(e), own);
                        }
                  break;
            }
      return wrap<Element>(e, own);
      }
}
}
