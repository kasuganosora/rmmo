extends SceneTree
const Data=preload("res://scripts/world3d/world_map_data.gd")
const View=preload("res://scripts/ui/world_map_view_3d.gd")
class Player extends Node3D:
	var input_locked:=false
	var click_target:Variant=null
	var _route:Array=[]
class World extends Node:
	var _map_data:RefCounted
	var _player:=Player.new()
	var _combat:Dictionary={"actors":{}}
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func spec(id:String,at:Vector3,size:Vector3,extra:Dictionary={},order:int=-1)->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=size
	var result:={"uuid":id,"transform":Transform3D(Basis(Vector3.UP,.27),at),"mesh":mesh,"extras":extra}
	if order>=0:result.map_draw_order=order
	return result
func built(items:Array)->RefCounted:
	var node:=Node.new();node.set_meta("stream_library",items);node.set_meta("extras",{"map_name":"Append fixture"})
	var data:=Data.new();data.build(node);node.free();return data
func footprints(data:RefCounted)->Array:
	var values:Array=data.visible_shapes(Rect2(-10000,-10000,20000,20000)).duplicate(true)
	for shape:Dictionary in values:
		shape.erase("draw_id");shape.erase("draw_order");shape.erase("source_order")
	return values
func finish(view:Control)->void:
	var slices:=0
	while not view._terrain.is_prepared() and slices<10000:
		view._terrain._process(0);slices+=1
	check(view._terrain.is_prepared(),"budgeted layer reaches full preparation")
func run()->void:
	root.size=Vector2i(320,240);root.content_scale_size=root.size
	var initial:Array=[spec("high",Vector3(0,1,0),Vector3(14,2,12),{},40),spec("ground",Vector3.ZERO,Vector3(30,.2,20),{},0)]
	var additions:Array=[spec("low_water",Vector3(0,.2,0),Vector3(18,.3,14),{"kind":"water"},10),
		spec("tie_before",Vector3(2,1,1),Vector3(9,2,10),{"kind":"water"},30),spec("tie_after",Vector3(-2,1,-1),Vector3(9,2,10),{},50),
		spec("upper_floor",Vector3(0,15,0),Vector3(8,2,8),{"building":{"role":"floor","floor":1}},60),
		spec("npc",Vector3(14,0,0),Vector3(1,2,1),{"kind":"npc","name":"Target"},70)]
	var data=built(initial);var replacement:int=data.shape_revision
	data.pins.append(Vector2(2,3));var title:String=data.title
	var world:=World.new();world._map_data=data;root.add_child(world);world.add_child(world._player)
	var view:=View.new();view.size=Vector2(280,200);view.position=Vector2(20,20);root.add_child(view);view.set_process(false);view.bind_world(world,true)
	finish(view)
	var old_items:Array[RID]=view._terrain._items.duplicate();var recorded:int=view._terrain.commands_recorded
	var old_ids:Array=[]
	for shape:Dictionary in data.shapes:old_ids.append(shape.draw_id)
	var appended:Dictionary=data.append_specs(additions)
	check(appended.ok and appended.added_shapes==3 and appended.added_markers==1,"append shares full-build floor filtering, markers and projection")
	check(data.shape_revision==replacement and data.title==title and data.pins==[Vector2(2,3)],"append preserves replacement generation title and pins")
	for i in old_ids.size():check(data.shapes[i].draw_id==old_ids[i],"old storage draw ID remains stable "+str(i))
	view._prepare_terrain()
	check(view._terrain.commands_recorded==recorded,"growing and reordering slots does not rerecord existing commands")
	for i in old_items.size():check(view._terrain._items[i]==old_items[i],"old rendering RID remains alive "+str(i))
	view._terrain.show_shapes(data.visible_shapes(data.bounds),1./view.scale_factor())
	check(view._terrain.commands_recorded==recorded and view._terrain._priority.size()==3,"new visible footprints enqueue instead of bypassing slice budget")
	finish(view)
	check(view._terrain.commands_recorded==recorded+3,"each new footprint is recorded once")
	var expected=built(initial+additions)
	check(footprints(data)==footprints(expected) and data.markers==expected.markers and data.bounds==expected.bounds,"mixed height and equal-height append equals complete build")
	check(data.bounds==expected.bounds,"bounds padding applies once")
	var before:Rect2=data.bounds;var count:int=data.shapes.size()
	check(not data.append_specs(additions).ok and data.bounds==before and data.shapes.size()==count,"duplicate footprint batch fails without side effects")
	var revision:int=data.order_revision
	check(data.append_specs([]).ok and data.order_revision==revision and data.bounds==before,"empty append does not regrow bounds or invalidate order")
	var extra:Array=[spec("far",Vector3(100,0,100),Vector3(8,1,8),{},80)]
	check(data.append_specs(extra).ok,"second lazy batch appends")
	view.size=Vector2(250,180);view.set_view_radius(8);view.center=Vector2(3,2);view._prepare_terrain();finish(view)
	check(footprints(data)==footprints(built(initial+additions+extra)),"repeated append retains complete-build order")
	for i in old_items.size():check(view._terrain._items[i]==old_items[i],"resize after append preserves prior RID "+str(i))
	if DisplayServer.get_name()!="headless":
		var prefix:="D:/code/rmmo_runtime/review_artifacts/world_map_append_20261008"
		view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		var incremental:Image=root.get_texture().get_image();incremental.save_png(prefix+"_incremental.png")
		world._map_data=built(initial+additions+extra);world._map_data.pins.assign(data.pins)
		view._prepare_terrain();finish(view);view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		var complete:Image=root.get_texture().get_image();complete.save_png(prefix+"_complete.png")
		check(incremental.get_data()==complete.get_data(),"incremental and complete build render identical pixels after pan/resize")
	# Remove with another unfinished batch: queued indices and RIDs must retire.
	world._map_data=data;data.append_specs([spec("pending",Vector3.ZERO,Vector3.ONE)]);view._prepare_terrain()
	root.remove_child(view)
	check(view._terrain._items.is_empty() and view._terrain._priority.is_empty(),"exiting with pending work releases RIDs and queues")
	view.free();world.free()
	print("WORLD_MAP_APPEND_FINISHED failures=",failures);quit(1 if failures else 0)
