extends RefCounted
## Domain ops: history (undo, redo, list_undo).

var ctrl
func _init(c):
	ctrl = c

func undo() -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var cells: Array[Vector2i] = d.undo_cells()
	ctrl._touch(cells)
	return ctrl.mcp._ok({"undone": cells.size()})



func redo() -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var cells: Array[Vector2i] = d.redo_cells()
	ctrl._touch(cells)
	return ctrl.mcp._ok({"redone": cells.size()})



func list_undo() -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var items: Array = []
	var stack: Array = d.get("_undo") if "_undo" in d else []
	for i in range(stack.size() - 1, maxi(stack.size() - 12, -1), -1):
		if i < 0:
			break
		var cmd: Dictionary = stack[i] if typeof(stack[i]) == TYPE_DICTIONARY else {}
		items.append({"t": str(cmd.get("t", "")), "cells": d._cmd_cells(cmd).size() if d.has_method("_cmd_cells") else 0})
	return ctrl.mcp._ok({"count": stack.size() if typeof(stack) == TYPE_ARRAY else 0, "items": items})


