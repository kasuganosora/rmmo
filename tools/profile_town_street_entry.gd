extends SceneTree
const MAP="D:/code/rmmo_runtime/cache/world3d/town_second_street_20261005/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/town_street_entry_20261005"
var world:Node
var samples:Array=[]
var failures:=0
var label_:="baseline"
var pass_index:=0
var night:=false
var toggle_at:=0
var toggle_count:=0
var toggle_timings:Array=[]
var click_timings:Array=[]
var drain_frames:=0
var support_probes:Dictionary={}
var script_frame_start:=0
var draw_frame_start:=0
var engine_frame:Dictionary={}
func stress_toggle()->void:
	if not "--toggle" in OS.get_cmdline_user_args() or Time.get_ticks_msec()<toggle_at:return
	night=not night;var began:=Time.get_ticks_usec()
	var result:Dictionary=world._request_environment({"time_hours":0.0 if night else 12.0,"time_speed":0.0})
	var duration:=(Time.get_ticks_usec()-began)/1000.0
	toggle_count+=1;toggle_at=Time.get_ticks_msec()+100
	toggle_timings.append({"frame":Engine.get_process_frames(),"ms":duration,"night":night,"environment":world.get_meta("environment_timing",{}),"weather":world._weather.get_meta("frame_timing",{}),"lamps":world._weather.streetlamps.get_meta("frame_timing",{})})
	if not result.get("ok",false):failures+=1
	var lights:Array=world._weather.streetlamps.lights
	if lights.size()!=33 or not lights.all(func(light):return light.visible==night):failures+=1;print("FAIL toggle lights ",toggle_count)
func tour()->Array:
	var graph:Dictionary=world._map_root.get_meta("extras").editor_layout.roads
	var nodes:Dictionary={}
	for node:Dictionary in graph.nodes:nodes[node.id]=Vector3(node.position[0],node.position[1],node.position[2])
	var chain:=["n_405_495","n_475_501","n_468_445","n_475_501","n_532_476","n_475_501","n_405_495"]
	var result:Array=[nodes[chain[0]]]
	for i in chain.size()-1:
		var matches:Array=graph.edges.filter(func(edge):return (edge.from==chain[i] and edge.to==chain[i+1]) or (edge.to==chain[i] and edge.from==chain[i+1]))
		assert(matches.size()==1,"tour follows an existing authored road")
		var edge:Dictionary=matches[0];var a:Vector3=nodes[edge.from];var b:Vector3=nodes[edge.to]
		var c0:Vector3=a.lerp(b,1./3);var c1:Vector3=a.lerp(b,2./3)
		if edge.has("controls"):
			c0=Vector3(edge.controls[0][0],edge.controls[0][1],edge.controls[0][2]);c1=Vector3(edge.controls[1][0],edge.controls[1][1],edge.controls[1][2])
		var steps:=ceili((a.distance_to(c0)+c0.distance_to(c1)+c1.distance_to(b))/25.)
		for step in range(1,steps+1):
			var t:=float(step)/steps
			if edge.from!=chain[i]:t=1.-t
			result.append(a.bezier_interpolate(c0,c1,b,t))
	return result
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func sample(previous:int)->int:
	var now:=Time.get_ticks_usec();var batcher=world._map_root.get_node("GroundRenderBatches")
	var r:Dictionary={"ms":(now-previous)/1000.0,"position":world._player.position,"gpu":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"process":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"parts":world.get_meta("frame_timings",{}),"batch_count":batcher.sync_count,"batch_ms":batcher.last_sync_ms,"batch_profile":batcher.sync_profile.duplicate(),"batch_slice":batcher.last_prepare_slice_ms,"batch_commit":batcher.last_commit_ms,"nav":world._navigation.loading_profile.get("nearby_refreshes",0)}
	samples.append(r)
	r["pass"]=pass_index;r["night"]=night
	r["nav_background"]=world._navigation.get_meta("background_timing",{})
	r["nav_publication"]=world._navigation.get_meta("publication_timing",{})
	r["nav_full"]=world._navigation.fully_ready
	r["tiles_remaining"]=world._navigation.loading_profile.get("tiles_remaining",-1)
	r["surface_query"]=world._navigation.get_meta("surface_query_timing",{})
	r["body_count"]=world._map_root.get_meta("stream_bodies",{}).size()
	r["nodes"]=Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	r["memory_mib"]=Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0
	r["weather"]=world._weather.get_meta("frame_timing",{})
	r["lamps"]=world._weather.streetlamps.get_meta("frame_timing",{})
	r["toggles"]=toggle_count
	r["engine"]=engine_frame
	r["render_cpu"]=RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
	# Keep the hot path free of synchronous console/JSON output. Printing a
	# large hitch record here would itself inflate the following frame.
	return now
func run()->void:
	create_timer(1200 if "--soak" in OS.get_cmdline_user_args() else 540).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1280,800)
	if "--no-vsync" in OS.get_cmdline_user_args():DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):label_=arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(OUT)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession");session.world3d_map_path=MAP;session.world3d_spawn=Vector3(-114.9,.9,-1.7)
	if "--native" in OS.get_cmdline_user_args():
		var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(MAP)
		var loaded:Array=await loader.finished
		check(loaded[0]!=null,"native async loader prepared map")
		if loaded[0]==null:quit(1);return
		session.prepared_world3d=loaded[0];session.world3d_loading=true
	world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	if "--wait-nav" in OS.get_cmdline_user_args():
		while not world._navigation.fully_ready or world._navigation._surface_index==null:await process_frame
		print("PASS premeasurement full navigation and support index ready")
	if "--validate-index" in OS.get_cmdline_user_args():
		var nav=world._navigation;var rng:=RandomNumberGenerator.new();rng.seed=910237
		var vertices:PackedVector3Array=nav.mesh.get_vertices();var accepted:=0;var mismatches:=0
		for i in 2000:
			var poly:PackedInt32Array=nav.mesh.get_polygon(rng.randi_range(0,nav.mesh.get_polygon_count()-1));var point:=Vector3.ZERO
			for index in poly:point+=vertices[index]
			point/=poly.size();point+=Vector3(rng.randf_range(-.5,.5),rng.randf_range(-.2,.2),rng.randf_range(-.5,.5))
			if i%10==0:point.y+=2
			var support:Vector3=nav._surface_index.support(point,.18)
			if support.is_finite():
				accepted+=1;var nearest:=NavigationServer3D.map_get_closest_point(nav.map,point)
				if Vector2(point.x-nearest.x,point.z-nearest.z).length()>.18 or absf(point.y-nearest.y)>.4:mismatches+=1
			if i%8==0:await process_frame
		support_probes={"samples":2000,"accepted":accepted,"false_positives":mismatches}
		check(mismatches==0 and accepted>0,"actual town surface certificates agree with engine: "+str(support_probes))
	if "--pause-nav" in OS.get_cmdline_user_args():world._navigation.set_process(false)
	world.set_meta("profile_frame",true)
	world._navigation.set_meta("profile_frame",true)
	world._weather.set_meta("profile_frame",true)
	world._weather.streetlamps.set_meta("profile_frame",true)
	world._map_root.set_meta("profile_frame",true)
	world._map_root.get_node("GroundRenderBatches").set_meta("profile_frame",true)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	process_frame.connect(func():script_frame_start=Time.get_ticks_usec())
	RenderingServer.frame_pre_draw.connect(func():draw_frame_start=Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func():engine_frame={"frame":Engine.get_process_frames(),"process_to_draw_ms":(draw_frame_start-script_frame_start)/1000.0,"draw_ms":(Time.get_ticks_usec()-draw_frame_start)/1000.0})
	world._request_environment({"time_hours":12.0,"time_speed":0.0})
	for i in 40:await process_frame
	var paths:Array=[Vector3(-144,0,-9),Vector3(-175,0,-16),Vector3(-206,0,-24),Vector3(-238,0,-32),Vector3(-269,0,-40),Vector3(-300,0,-47),Vector3(-329,0,-54.6),Vector3(-333,0,-24),Vector3(-333,0,8),Vector3(-327,0,40)]
	if "--short" in OS.get_cmdline_user_args():paths=paths.slice(0,2)
	var passes:=10 if "--explore" in OS.get_cmdline_user_args() else (8 if "--soak" in OS.get_cmdline_user_args() else (1 if "--short" in OS.get_cmdline_user_args() else 2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--passes="):passes=clampi(arg.trim_prefix("--passes=").to_int(),1,20)
	for pass_ in passes:
		pass_index=pass_;night="--night" in OS.get_cmdline_user_args() or (pass_>=4 and pass_!=8)
		world._request_environment({"time_hours":0.0 if night else 12.0,"time_speed":0.0})
		if pass_==8:paths=tour()
		elif pass_>0:paths.reverse()
		print("PROFILE_PASS ",pass_," night=",night," full_navigation=",world._navigation.fully_ready)
		for target:Vector3 in paths:
			var previous:=Time.get_ticks_usec()
			world._player.set_click_target(target,"ground")
			click_timings.append({"pass":pass_,"target":target,"ms":(Time.get_ticks_usec()-previous)/1000.0})
			var deadline:=Time.get_ticks_msec()+20000
			while Time.get_ticks_msec()<deadline:
				stress_toggle()
				await process_frame;previous=sample(previous)
				if Vector2(world._player.position.x-target.x,world._player.position.z-target.z).length()<.45:break
			check(Vector2(world._player.position.x-target.x,world._player.position.z-target.z).length()<.5,"walk "+str(pass_)+" to "+str(target))
	if "--drain-nav" in OS.get_cmdline_user_args():
		var previous:=Time.get_ticks_usec()
		while not world._navigation.fully_ready:
			stress_toggle();await process_frame;previous=sample(previous);drain_frames+=1
		print("PASS navigation drain frames=",drain_frames)
	var sorted:Array=samples.map(func(r):return r.ms);sorted.sort()
	var worst:Array=samples.duplicate();worst.sort_custom(func(a,b):return a.ms>b.ms)
	var report:={"loader":"native" if "--native" in OS.get_cmdline_user_args() else "direct_gltf","short_route":"--short" in OS.get_cmdline_user_args(),"navigation_paused":"--pause-nav" in OS.get_cmdline_user_args(),"failures":failures,"samples":samples,"median":sorted[sorted.size()/2],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over50":sorted.filter(func(x):return x>50).size(),"worst":worst.slice(0,20),"map":FileAccess.get_sha256(MAP)}
	report["navigation_fully_ready"]=world._navigation.fully_ready
	report["vsync_disabled"]="--no-vsync" in OS.get_cmdline_user_args()
	report["navigation_drain_frames"]=drain_frames
	report["navigation_profile"]=world._navigation.loading_profile.duplicate(true)
	report["surface_queries"]=world._navigation.surface_query_count
	report["surface_cache_hits"]=world._navigation.surface_cache_hits
	report["surface_index_hits"]=world._navigation.surface_index_hits
	report["support_probes"]=support_probes
	report["waited_for_navigation"]="--wait-nav" in OS.get_cmdline_user_args()
	report["toggle_count"]=toggle_count
	report["toggle_timings"]=toggle_timings
	report["click_timings"]=click_timings
	report["material_builds"]=world._weather.streetlamps.material_builds
	report["passes"]=pass_index+1
	var pass_reports:Array=[]
	for index in pass_index+1:
		var values:Array=samples.filter(func(r):return r["pass"]==index).map(func(r):return r.ms);values.sort()
		pass_reports.append({"pass":index,"night":"--night" in OS.get_cmdline_user_args() or (index>=4 and index!=8),"median":values[values.size()/2],"p95":values[int(values.size()*.95)],"p99":values[int(values.size()*.99)],"max":values.back(),"over50":values.filter(func(ms):return ms>50).size()})
	report["per_pass"]=pass_reports
	if "--soak" in OS.get_cmdline_user_args():check(world._navigation.fully_ready,"soak includes complete background navigation publication")
	report["failures"]=failures
	var f:=FileAccess.open(OUT+"/"+label_+".json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	var hitches:=FileAccess.open(OUT+"/"+label_+"_hitches.jsonl",FileAccess.WRITE)
	for row:Dictionary in samples:
		if row.ms>50:hitches.store_line(JSON.stringify(row))
	hitches.close()
	report.erase("samples");report.erase("worst");report.erase("toggle_timings");report.erase("click_timings");print("ENTRY_PROFILE ",JSON.stringify(report));world.free();quit(1 if failures else 0)
