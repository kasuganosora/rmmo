extends SceneTree
const List=preload("res://scripts/world_editor/object_list.gd")
class Data extends RefCounted:
	var records:Array=[]
	func _find(uuid:String)->Dictionary:
		for record in records:
			if record.uuid==uuid:return record
		return {}
class Selection extends RefCounted:
	var ids:Array[String]=[]
class Authoring extends RefCounted:
	func includes(record:Dictionary)->bool:return not record.get("outside",false)
class Editor extends Node3D:
	var _doc:=Data.new()
	var _selection_tools:=Selection.new()
	var _authoring:=Authoring.new()
	func _record_editable(record:Dictionary)->bool:return not record.get("editor_hidden",false) and not record.get("editor_locked",false) and _authoring.includes(record)
var failed:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failed+=1
func row(uuid:String,label:String,group:String="")->Dictionary:
	var record:={"uuid":uuid,"kind":"box","editor_name":label}
	if not group.is_empty():record.editor_group=group;record.editor_group_name="Group"
	return record
func order(list:Control)->Array:
	return list.tree.get_root().get_children().map(func(item):return item.get_text(0))
func run()->void:
	var editor:=Editor.new();root.add_child(editor)
	var a:=row("a","A");var b:=row("b","NeedleB")
	editor._doc.records=[row("g1","Member1","g"),a,row("g2","NeedleMember2","g"),b]
	editor._selection_tools.ids=["b"]
	var list:=List.new();list.editor=editor;list.tree=Tree.new();list.tree.columns=3;list.tree.select_mode=Tree.SELECT_MULTI;list.add_child(list.tree);list.search=LineEdit.new();list.add_child(list.search);root.add_child(list);list.refresh()
	var group_id:int=list._group_items.g.get_instance_id();var b_id:int=list._items.b.get_instance_id()
	check(order(list)==["Group","A","NeedleB"] and list._items.b.is_selected(0),"initial grouped order and selection")
	editor._doc.records.erase(a);list.refresh_records(["a"])
	check(order(list)==["Group","NeedleB"] and list._items.b.get_instance_id()==b_id and list._items.b.is_selected(0),"deletion preserves other row and selection")
	editor._doc.records.insert(1,a);list.refresh_records(["a"])
	check(order(list)==["Group","A","NeedleB"] and list._group_items.g.get_instance_id()==group_id,"undo insertion between group members stays after group header")
	list.search.text="needle";list.refresh();b_id=list._items.b.get_instance_id()
	check(order(list)==["Group","NeedleB"] and not list._items.has("a"),"filter includes matching group and omits unmatched ordinary record")
	list.refresh_records(["a"])
	check(not list._items.has("a") and list._items.b.get_instance_id()==b_id,"unmatched incremental update does not add a filtered row")
	a.editor_name="NeedleA";a.editor_hidden=true;a.editor_locked=true;list.refresh_records(["a"])
	check(order(list)==["Group","NeedleA","NeedleB"] and not list._items.a.is_checked(1) and list._items.a.is_checked(2),"matching inserted row preserves hidden/locked checkboxes and grouped order")
	check(list._items.b.get_instance_id()==b_id and list._items.b.is_selected(0),"filtered insertion retains other selection and row identity")
	a.editor_name="A";list.refresh_records(["a"])
	check(not list._items.has("a") and order(list)==["Group","NeedleB"],"record leaving search filter removes its row")
	var member:Dictionary=editor._doc._find("g2");editor._doc.records.erase(member);list.refresh_records(["g2"])
	check(not list._group_items.has("g") and order(list)==["NeedleB"],"group-member removal recomputes group filter without stale child/header")
	list.free();editor.free()
	print("OBJECT_LIST_INCREMENTAL_FINISHED failures=",failed);quit(1 if failed else 0)
