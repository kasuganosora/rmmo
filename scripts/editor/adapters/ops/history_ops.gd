extends RefCounted
## Domain ops: history (undo, redo, list_undo).

var _owner: WeakRef
var ctrl:
	get:
		return _owner.get_ref()
func _init(c):
	_owner = weakref(c)

func undo(_args := {}) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var cells: Array[Vector2i] = d.undo_cells()
	ctrl._touch(cells)
	return ctrl.mcp._ok({"undone": cells.size()})



func redo(_args := {}) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var cells: Array[Vector2i] = d.redo_cells()
	ctrl._touch(cells)
	return ctrl.mcp._ok({"redone": cells.size()})



func list_undo(_args := {}) -> Dictionary:
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

func op_names() -> Array:
	return ["undo", "redo", "list_undo", "move_selection"]

func move_selection(args: Dictionary) -> Dictionary:
	var d=ctrl.doc()
	if d==null:return ctrl.mcp._err("no map")
	var layers: Variant=args.get("layers",[])
	if typeof(layers)!=TYPE_ARRAY:return ctrl.mcp._err("layers must be an array")
	var result: Dictionary=load("res://scripts/editor/domain/selection_move.gd").move(d,Rect2i(int(args.get("x",0)),int(args.get("y",0)),int(args.get("w",0)),int(args.get("h",0))),Vector2i(int(args.get("dx",0)),int(args.get("dy",0))),layers)
	if not result.ok:return ctrl.mcp._err(result.error)
	var cells: Array[Vector2i]=[];cells.assign(result.dirty)
	ctrl._touch(cells)
	return ctrl.mcp._ok({"moved_cells":cells.size()})

func tools() -> Array:
	return [
		ctrl.mcp._tool("move_selection", "移动矩形内多个指定图层的非空内容；重叠安全、拒绝越界或覆盖已有内容，可一步撤销。生成住宅必须完整选中含 meta。", {
			"x":{"type":"integer"},"y":{"type":"integer"},"w":{"type":"integer"},"h":{"type":"integer"},
			"dx":{"type":"integer"},"dy":{"type":"integer"},"layers":{"type":"array","items":{"type":"string"},"description":"0..5 或扩展层名，如 meta"}},["x","y","w","h","dx","dy","layers"]),
		ctrl.mcp._tool("undo", "撤销上次绘制/写入。", {}),
		ctrl.mcp._tool("redo", "重做。", {}),
		ctrl.mcp._tool("list_undo", "查看撤销栈。", {}),
	]
