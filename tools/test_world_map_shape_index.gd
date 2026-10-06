extends SceneTree
const Data=preload("res://scripts/world3d/world_map_data.gd")
const View=preload("res://scripts/ui/world_map_view_3d.gd")
var failed:=0
class TestPlayer extends Node3D:
	var click_target:Variant=Vector3(20,0,12)
	var _route:=PackedVector3Array([Vector3(24,0,17)])
class TestCombat extends RefCounted:
	var actors:Dictionary={}
class TestWorld extends Node:
	var _map_data:RefCounted
	var _player:Node3D
	var _combat:=TestCombat.new()
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failed+=1
func shape(rect:Rect2,id:int)->Dictionary:
	return {"bounds":rect,"polygon":PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y),rect.position]),"color":Color.from_hsv(fposmod(id*.037,1),.5,.8),"height":id/3,"id":id}
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	var data:=Data.new();var rng:=RandomNumberGenerator.new();rng.seed=972801
	for i in 1600:
		data.shapes.append(shape(Rect2(Vector2(rng.randf_range(-1600,1600),rng.randf_range(-1600,1600)),Vector2(rng.randf_range(2,120),rng.randf_range(2,120))),i))
	data.shapes.push_front(shape(Rect2(-100000,-100000,200000,200000),-1))
	for rect:Rect2 in [Rect2(-128,-64,64,64),Rect2(-64,-64,64,64),Rect2(0,0,64,64),Rect2(0,0,64,64),Rect2(-4000,-2,8000,4)]:
		data.shapes.append(shape(rect,data.shapes.size()))
	var started:=Time.get_ticks_usec();data.rebuild_shape_index()
	print("MAP_INDEX_BUILD ms=",(Time.get_ticks_usec()-started)/1000.0," cells=",data._shape_cells.size())
	var queries:Array[Rect2]=[Rect2(-64,-64,64,64),Rect2(64,64,64,64),Rect2(-1,-1,2,2),Rect2(-1000000,-1000000,2000000,2000000),Rect2(30000,30000,64,64)]
	for i in 1000:queries.append(Rect2(Vector2(rng.randf_range(-2000,2000),rng.randf_range(-2000,2000)),Vector2(rng.randf_range(1,400),rng.randf_range(1,400))))
	var mismatch:=0
	for rect in queries:
		var expected:Array=data.shapes.filter(func(s):return rect.intersects(s.bounds))
		if data.visible_shapes(rect)!=expected:mismatch+=1
	check(mismatch==0,"1005 queries exactly match original scan and painter order, including borders, duplicates, long and large shapes")
	data.visible_shapes(Rect2(-32,-32,64,64))
	check(data.last_query_indexed and data.last_query_candidates<data.shapes.size()/10,"local query examines fewer than 10% of shapes")
	check(data.visible_shapes(Rect2(0,0,0,0)).is_empty() and data.visible_shapes(Rect2(Vector2.INF,Vector2.ONE)).is_empty(),"empty and nonfinite viewports are safe")
	var world:=TestWorld.new();world._map_data=data;world._player=TestPlayer.new();world.add_child(world._player);root.add_child(world)
	var view:=View.new();world.add_child(view);view.set_process(false);view.world=world;view.size=Vector2(480,320)
	root.size=Vector2i(480,320);data.bounds=Rect2(-1800,-1800,3600,3600);data.pins=[Vector2(8,8)]
	if DisplayServer.get_name()!="headless":
		for mode in 3:
			view.radar=mode<2;view.center=Vector2(-12,8) if mode==0 else Vector2(-80,-64);view.radius=48 if mode==0 else 120;view.span=4000
			data._indexed_shape_count=-1;view.queue_redraw()
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var before:=root.get_texture().get_image()
			data.rebuild_shape_index();view.queue_redraw()
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			check(before.get_data()==root.get_texture().get_image().get_data(),"pixel-identical radar/overview mode "+str(mode))
	world.free()
	# Real document replacement rebuilds the index even when shape count matches.
	var host:=Node3D.new();var cube:=BoxMesh.new()
	host.set_meta("stream_library",[{"uuid":"replacement","mesh":cube,"transform":Transform3D(Basis.IDENTITY,Vector3(300,0,300))}])
	data.build(host);check(data.visible_shapes(Rect2(295,295,10,10)).size()==1 and data.visible_shapes(Rect2(-5,-5,10,10)).is_empty(),"map rebuild removes old index cells")
	host.set_meta("stream_library",[{"uuid":"moved","mesh":cube,"transform":Transform3D(Basis.IDENTITY,Vector3(-300,0,-300))}])
	data.build(host);check(data.visible_shapes(Rect2(295,295,10,10)).is_empty() and data.visible_shapes(Rect2(-305,-305,10,10)).size()==1,"same-size replacement refreshes spatial membership")
	host.free();print("WORLD_MAP_SHAPE_INDEX_FINISHED failures=",failed);quit(1 if failed else 0)
