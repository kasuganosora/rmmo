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
func settle()->void:
	for i in 3:await process_frame
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
	world._map_data.pins.append(Vector2(5,6));world._map_data.rebuild_shape_index()
	var view:=View.new();view.size=Vector2(280,200);view.position=Vector2(20,20);root.add_child(view);view.set_process(false);view.bind_world(world,true);view.set_meta("profile_frame",true)
	await settle()
	var first:int=view._terrain.redraws
	for i in 8:
		view.center+=Vector2(.1,.1);world._player.position+=Vector3(.1,0,.1);view.queue_redraw();await settle()
	check(view._terrain.redraws==first,"walking inside cached coverage translates without rebuilding static commands")
	check(view.to_world(view.to_screen(Vector2(8,3))).distance_to(Vector2(8,3))<.00001,"click coordinates retain original world projection")
	for sample in 3:
		if sample==1:view.center=Vector2(45,-28)
		if sample==2:view.radius=11;view.size=Vector2(200,180)
		for mode in [false,true]:
			View.terrain_cache_enabled=mode;view.queue_redraw();await settle()
			root.get_texture().get_image().save_png(OUT.path_join("%d_%s.png"%[sample,"cached" if mode else "original"]))
		check(view._coverage.encloses(Rect2(view.to_world(Vector2.ZERO),view.size/view.scale_factor())),"cache covers pan/zoom/resize viewport "+str(sample))
	var before:int=view._terrain.redraws
	world._map_data.shapes[0].color=Color.RED;world._map_data.rebuild_shape_index();view.queue_redraw();await settle()
	check(view._terrain.redraws==before+1,"same-count map revision rebuilds static commands")
	var other:=Data.new();other.bounds=world._map_data.bounds;other.shapes=world._map_data.shapes.duplicate();other.rebuild_shape_index();world._map_data=other
	view.queue_redraw();await settle()
	check(view._cached_data==other and view._terrain.redraws==before+2,"map replacement invalidates identical revision/count cache")
	check(view.get_draw_timing().get("terrain_ms",-1)>=0,"profile includes deferred static layer work")
	view.free();world.free();print("WORLD_MAP_DRAW_CACHE_FINISHED failures=",failures);quit(1 if failures else 0)
