class_name UndoStack
extends RefCounted
## Snapshot-based undo/redo. Callers capture an opaque state snapshot BEFORE
## a mutation via push(), then undo()/redo() return snapshots to restore.
## Generic on purpose — the workshop stores serialized recipe drafts, but any
## Variant works.

signal history_changed

const MAX_DEPTH: int = 64

var _undo: Array = []
var _redo: Array = []


## Record the state as it was before a mutation.
func push(snapshot: Variant) -> void:
	_undo.append(snapshot)
	if _undo.size() > MAX_DEPTH:
		_undo.pop_front()
	_redo.clear()
	history_changed.emit()


## Returns the snapshot to restore, or null when nothing to undo.
## current is the present state, stored for redo.
func undo(current: Variant) -> Variant:
	if _undo.is_empty():
		return null
	_redo.append(current)
	var snapshot: Variant = _undo.pop_back()
	history_changed.emit()
	return snapshot


func redo(current: Variant) -> Variant:
	if _redo.is_empty():
		return null
	_undo.append(current)
	var snapshot: Variant = _redo.pop_back()
	history_changed.emit()
	return snapshot


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func clear() -> void:
	_undo.clear()
	_redo.clear()
	history_changed.emit()
