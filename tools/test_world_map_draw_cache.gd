extends SceneTree
const View=preload("res://scripts/ui/world_map_view_3d.gd")
const Data=preload("res://scripts/world3d/world_map_data.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/radar_draw_cache_20261006"
class Player extends Node3D:
	var click_target:Variant=Vector3(12,0,8)
	var _route:Array=[]
class World extends Node:
	var _map_data=Data.new()
	var _player:=Player.new()
	var _combat:Dictionary={"actors":{}}
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
var active_view:Control
func settle()->void:
	for i in 3:await process_frame
	var frames:=0
	while is_instance_valid(active_view) and not active_view.terrain_is_prepared() and frames<600:
		await process_frame;frames+=1
	check(frames<600,"bounded terrain warmup finishes")
	await RenderingServer.frame_post_draw
func run()->void:
	root.size=Vector2i(320,240);root.content_scale_size=root.size;Engine.max_fps=60;DirAccess.make_dir_recursive_absolute(OUT)
	var world:=World.new();root.add_child(world);world.add_child(world._player)
	world._map_data.bounds=Rect2(-120,-120,240,240)
	for y in 12:
		for x in 12:
			var rect:=Rect2(-80+x*14,-80+y*14,11,12)
			var polygon:=PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y),rect.position])
			world._map_data.shapes.append({"bounds":rect,"polygon":polygon,"color":Color("68765b") if (x+y)%2==0 else Color("8c8374")})
	# Overlapping tilted convex footprints exercise painter order and alpha,
	# including subpixel edges that were absent from the original grid fixture.
	for i in 25:
		var points:=PackedVector2Array()
		for j in 6:points.append(Vector2(12*cos(j*TAU/6),7*sin(j*TAU/6)).rotated(i*.13)+Vector2(20+i*.37,8+i*.29))
		var polygon:=Geometry2D.convex_hull(points)
		var bounds:=Rect2(points[0],Vector2.ZERO)
		for point in points:bounds=bounds.expand(point)
		world._map_data.shapes.append({"bounds":bounds,"polygon":polygon,"color":Color(.2+i*.02,.5,.3,.6)})
	world._map_data.pins.append(Vector2(5,6))
	var view:=View.new();view.size=Vector2(280,200);view.position=Vector2(20,20);root.add_child(view);view.set_process(false);view.bind_world(world,true);view.set_meta("profile_frame",true)
	active_view=view
	check(view._terrain.commands_recorded==0,"bind defers footprint recording until layout has completed")
	await settle()
	check(view._terrain.commands_recorded==world._map_data.shapes.size(),"first layout records all footprints once at final width")
	check(view._terrain.shapes.size()>0 and world._map_data._indexed_shape_count==-1,"unindexed footprints prepare and display without missing draw IDs")
	var first:int=view._terrain.redraws
	var recorded:int=view._terrain.commands_recorded
	for i in 8:
		view.center+=Vector2(.1,.1);world._player.position+=Vector3(.1,0,.1);view.queue_redraw();await settle()
	check(view._terrain.redraws==first,"walking inside cached coverage translates without rebuilding static commands")
	view.center=Vector2(50,30);view.queue_redraw();await settle()
	check(view._terrain.commands_recorded==recorded,"crossing coverage reuses all prepared shape commands")
	check(view.to_world(view.to_screen(Vector2(8,3))).distance_to(Vector2(8,3))<.00001,"click coordinates retain original world projection")
	for sample in 3:
		if sample==1:view.center=Vector2(45,-28)
		if sample==2:view.radius=11;view.size=Vector2(200,180)
		for mode in [false,true]:
			View.terrain_cache_enabled=mode;view.queue_redraw();await settle()
			root.get_texture().get_image().save_png(OUT.path_join("%d_%s.png"%[sample,"cached" if mode else "original"]))
		check(view._coverage.encloses(Rect2(view.to_world(Vector2.ZERO),view.size/view.scale_factor())),"cache covers pan/zoom/resize viewport "+str(sample))
		var exact_width:=true
		for shape:Dictionary in view._terrain.shapes:
			if view._terrain._widths[shape.draw_id]!=1.0/view.scale_factor():exact_width=false
		check(exact_width,"pan/zoom/resize retains exact one-pixel outline width "+str(sample))
	var before:int=view._terrain.redraws
	world._map_data.shapes[0].color=Color.RED;world._map_data.rebuild_shape_index();view.queue_redraw();await settle()
	check(view._terrain.redraws==before+1,"same-count map revision rebuilds static commands")
	var other:=Data.new();other.bounds=world._map_data.bounds;other.shapes=world._map_data.shapes.duplicate();other.rebuild_shape_index();world._map_data=other
	view.queue_redraw();await settle()
	check(view._cached_data==other and view._terrain.redraws==before+2,"map replacement invalidates identical revision/count cache")
	check(view.get_draw_timing().get("terrain_ms",-1)>=0,"profile includes retained static layer work")
	check(view.get_draw_timing().ms==view.get_meta("draw_timing").ms,"profile counts synchronous terrain work once")
	var appended:Dictionary=other.shapes.back().duplicate();appended.erase("draw_id");other.shapes.append(appended)
	view.queue_redraw();await settle()
	check(view._terrain._items.size()==other.shapes.size() and appended.draw_id==other.shapes.size()-1,"appending an unindexed footprint rebuilds retained items")
	root.remove_child(view)
	check(view._terrain._items.is_empty(),"leaving tree releases all retained rendering items")
	root.add_child(view);view.queue_redraw();await settle()
	check(view._terrain._items.size()==other.shapes.size(),"reentering tree rebuilds released rendering items")
	view.free();world.free();print("WORLD_MAP_DRAW_CACHE_FINISHED failures=",failures);quit(1 if failures else 0)
