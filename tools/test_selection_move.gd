extends SceneTree
const Move=preload("res://scripts/editor/domain/selection_move.gd")
const Document=preload("res://scripts/editor/domain/map_document.gd")
var failures:=0
func check(ok: bool,label: String):
	if ok:print("PASS ",label)
	else:failures+=1;push_error(label)
func _init():call_deferred("run")
func run():
	var d=Document.new();d.setup_blank("Move","Move",40,40)
	for x in range(2,5):
		d.set_tile(x,3,0,2816);d.set_tile(x,3,1,100+x);d.set_tile(x,3,3,200+x)
		d.set_ext_tile("meta",x,3,4)
	var old=d.data.duplicate();var meta=d.ext_layers.meta.duplicate()
	var count: int=d._undo.size()
	var r:=Move.move(d,Rect2i(2,3,3,1),Vector2i(1,0),["1","3","meta"])
	check(r.ok and d.tile(3,3,1)==102 and d.tile(5,3,3)==204 and d.tile(2,3,1)==0,"overlap preserves every selected layer")
	check(d.tile(2,3,0)==2816 and d.ext_tile("meta",5,3)==4,"ground stays; collision moves")
	check(d._undo.size()==count+1,"whole move is one undo step")
	d.undo();check(d.data==old and d.ext_layers.meta==meta,"undo restores source and destination")
	d.redo();check(d.tile(5,3,1)==104,"redo repeats move")
	var changed=d.data.duplicate();count=d._undo.size()
	r=Move.move(d,Rect2i(3,3,3,1),Vector2i(40,0),["1"])
	check(not r.ok and d.data==changed and d._undo.size()==count,"out of bounds is atomic")
	d.set_tile(10,3,1,999)
	r=Move.move(d,Rect2i(3,3,3,1),Vector2i(7,0),["1"])
	check(not r.ok and d.tile(10,3,1)==999 and d.tile(3,3,1)==102,"occupied destination is not overwritten")
	check(not Move.move(d,Rect2i(3,3,1,1),Vector2i.ONE,["invalid"]).ok,"invalid layer rejected")
	# Exercise sparse chunk storage across a real chunk boundary.
	var sparse=Document.new();sparse.setup_blank("Sparse","Sparse",2048,2048)
	sparse.set_tile(15,15,2,125)
	r=Move.move(sparse,Rect2i(15,15,1,1),Vector2i.ONE,["2"])
	check(r.ok and sparse.tile(16,16,2)==125 and sparse.tile(15,15,2)==0,"move crosses sparse chunks")
	sparse.undo();check(sparse.tile(15,15,2)==125,"sparse undo")
	# Generated instances retain the data used by later regeneration.
	var kit={"id":"fixture","parts":{}}
	for name in ["wall","wall_left","wall_right","foundation","window","door","roof_red_left","roof_red_middle","roof_red_right"]:
		kit.parts[name]={"w":1,"h":1,"tiles":[500]}
	var generator=load("res://scripts/editor/domain/building_generator.gd")
	var house=Document.new();house.setup_blank("HouseMove","HouseMove",40,40)
	var args={"x":3,"y":4,"bays":1,"floors":2,"instance_id":"home"}
	check(generator.place(house,kit,args).ok,"fixture generated")
	check(not Move.move(house,Rect2i(3,4,5,8),Vector2i(10,0),["1","2","3"]).ok,"incomplete building layer selection rejected")
	r=Move.move(house,Rect2i(3,4,5,8),Vector2i(10,0),["1","2","3","meta"])
	check(r.ok and house.building_instances.home.x==13 and house.ext_tile("meta",3,4)==0,"building record and footprint move together")
	house.undo();check(house.building_instances.home.x==3,"building record undo")
	house.redo()
	var path:="user://test_selection_move_"+str(Time.get_ticks_usec())
	check(house.save_dir(path),"save moved map")
	var loaded=Document.new();check(loaded.load_dir(path),"reload moved map")
	args.x=13;args.floors=3
	check(generator.place(loaded,kit,args).ok and loaded.ext_tile("meta",3,4)==0,"regenerate at moved location after reload")
	# Real selection controller: idle hover no longer changes the box.
	var ed=load("res://scripts/editor/content_editor.gd").new()
	ed.paint=load("res://scripts/editor/domain/paint_tools.gd").new()
	ed.doc=d;ed._status=Label.new();ed._layer_tree=Tree.new();ed._layer_tree.columns=3
	ed._fill_layer_tree()
	ed.map_field=load("res://scripts/map/map_field.gd").new()
	ed.map_field.pack=load("res://scripts/map/tilemap_pack.gd").new()
	var selection=ed._selection_move
	check(selection.selected_layers()==["1","2","3","meta"],"UI exposes independent multi-layer move checkboxes")
	selection.press(Vector2i(3,3));selection.release(Vector2i(5,4))
	var rect: Rect2i=selection.rect();selection.motion(Vector2i(20,20))
	check(selection.rect()==rect,"released selection stays fixed on hover")
	selection.press(Vector2i(3,3));selection.motion(Vector2i(4,5));selection.cancel()
	check(selection.rect()==rect and not selection.dragging,"Escape cancels preview without modifying tiles")
	ed.map_field.free();ed._status.free();ed._layer_tree.free();ed.free()
	print("SELECTION MOVE failures=",failures)
	quit(1 if failures else 0)
