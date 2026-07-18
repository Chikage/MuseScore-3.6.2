#include "enableplayforwidget.h"
#include "musescore.h"

namespace Ms {


EnablePlayForWidget::EnablePlayForWidget(QWidget* target)
      {
      _globalPlayAction = getAction("play");
      _target = target;
      _localPlayAction = new QAction(_target);
      _localPlayAction->setData(_globalPlayAction->data());
      _localPlayAction->setCheckable(_globalPlayAction->isCheckable());
      _localPlayAction->setChecked(_globalPlayAction->isChecked());
      _localPlayAction->setShortcuts(_globalPlayAction->shortcuts());
      _localPlayAction->setShortcutContext(Qt::WidgetShortcut);
      _target->addAction(_localPlayAction);
      qApp->installEventFilter(_target);
      QObject::connect(_localPlayAction, SIGNAL(triggered()), mscore->playButton(), SLOT(click()));
      }

void EnablePlayForWidget::showEvent(QShowEvent*)
      {
      _target->setFocus();
      }

//--------------------------------------------------------------------------------------------------
// eventFilter
//
// If any child of the target widget has focus when Escape Key is pressed it loses the focus
// and the target gains focus
// Also, it makes sure that the global play action and _localPlayAction always have the same shortcut
//--------------------------------------------------------------------------------------------------
bool EnablePlayForWidget::eventFilter(QObject* obj, QEvent* e)
      {
      // macOS may continue dispatching events while process-wide static
      // objects are being destroyed. Do not look up the action through the
      // static Shortcut hash here; cache it while the application is live.
      if (obj == _globalPlayAction) {
            _localPlayAction->setShortcuts(_globalPlayAction->shortcuts());
            }

      if (obj->isWidgetType() &&
          e->type() == QEvent::KeyPress &&
          obj != _target && // if obj == target, it means that the target has the focus. this case is handled by target::keyPressEvent
          _target->isAncestorOf(static_cast<QWidget*>(obj))) {
            QKeyEvent* ev = static_cast<QKeyEvent*>(e);
            if (ev->key() == Qt::Key_Escape && ev->modifiers() == Qt::NoModifier) {
                  _target->setFocus();
                  return true;
                  }
            }
      return false;
      }

//-----------------------------------------------------------------------
// connectLocalPlayToDifferentSlot
//
// Note: the _localPlayAction will always be connected to only one slot
// in order not to trigger the global play action twice
// By default it's set to click the play button from the main window
//-----------------------------------------------------------------------

void EnablePlayForWidget::connectLocalPlayToDifferentSlot(QObject *obj, const char *id)
      {
      _localPlayAction->disconnect();
      QObject::connect(_localPlayAction, SIGNAL(triggered()), obj, id);
      }
}
