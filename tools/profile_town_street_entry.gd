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
var preparation_report_at:=0
var expect_shadow_gating:=false
var force_legacy_shadows:=false
var shadow_comparison:Array=[]
class PhysicsMeter extends Node:
	var began:=0
	var ended:=0
	var total_ms:=0.0
	var max_ms:=0.0
	var steps:=0
	func _physics_process(_delta:float)->void:
		ended=Time.get_ticks_usec()
		var elapsed:float=(ended-began)/1000.0
		total_ms+=elapsed;max_ms=maxf(max_ms,elapsed);steps+=1
var physics_meter:PhysicsMeter
func compare_shadow_work()->void:
	# Stationary ABBA in the same loaded scene removes route/residency differences.
	# Keep graphics settings and all geometry/lights; only restore the old unused
	# directional shadow flags during legacy samples. Never used by the game.
	for hour in [12.,0.]:
		for legacy in [true,false,false,true]:
			force_legacy_shadows=legacy
			world._request_environment({"time_hours":hour,"time_speed":0.0})
			world._weather._apply()
			for i in 30:await process_frame
			var rows:Array=[];var previous:=Time.get_ticks_usec()
			for i in 60:
				await process_frame
				var now:=Time.get_ticks_usec()
				rows.append({"ms":(now-previous)/1000.0,"view":viewport_stats(root),"cpu":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"gpu":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())})
				previous=now
			shadow_comparison.append({"hour":hour,"legacy":legacy,"position":world._player.position,"samples":rows})
	force_legacy_shadows=false
	world._request_environment({"time_hours":0.0 if night else 12.0,"time_speed":0.0})
	world._weather._apply()
func report_preparation(stage:String)->void:
	if Time.get_ticks_msec()<preparation_report_at:return
	preparation_report_at=Time.get_ticks_msec()+10000
	var batches=world._map_root.get_node_or_null("GroundRenderBatches") if is_instance_valid(world._map_root) else null
	print("PROFILE_PREP ",stage," stages=",world.loading_profile," nav=",world._navigation.loading_profile if is_instance_valid(world._navigation) else {}," batches_pending=",batches.pending.size() if batches!=null else -1," batch_workers=",batches._workers.size() if batches!=null else -1)
func viewport_stats(view:Viewport)->Dictionary:
	return {"visible_calls":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"shadow_calls":view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"visible_objects":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME),"shadow_objects":view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_OBJECTS_IN_FRAME)}
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
	if expect_shadow_gating:
		for light:DirectionalLight3D in [world._weather.sun,world._weather.moon]:
			if light.shadow_enabled!=(bool(world._weather.values.sun_shadows) and light.light_energy>0):failures+=1;print("FAIL celestial shadow state ",toggle_count)
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
	r["physics_work"]={"script_ms":physics_meter.total_ms,"max_step_ms":physics_meter.max_ms,"steps":physics_meter.steps,"tail_ms":(now-physics_meter.ended)/1000.0,"frame":Engine.get_physics_frames()}
	r["motion"]=world._player.get_meta("motion_timing",{})
	physics_meter.total_ms=0;physics_meter.max_ms=0;physics_meter.steps=0
	r["nav_background"]=world._navigation.get_meta("background_timing",{})
	r["nav_publication"]=world._navigation.get_meta("publication_timing",{})
	r["nav_full"]=world._navigation.fully_ready
	r["tiles_remaining"]=world._navigation.loading_profile.get("tiles_remaining",-1)
	r["surface_query"]=world._navigation.get_meta("surface_query_timing",{})
	r["body_count"]=world._map_root.get_meta("stream_bodies",{}).size()
	r["residency"]={"meshes":world._map_root.get_meta("stream_meshes",{}).size(),"fort_sources":world._map_root.get_meta("fortification_collision_sources",{}).size(),"cursor":world._map_root.get_meta("stream_cursor",0),"jobs":world._map_root.get_meta("stream_jobs",[]).size(),"settled":world._map_root.has_meta("stream_chunk")}
	var fort=world._map_root.get_node_or_null("FortificationCollisionBatches")
	if fort!=null:r["fort_collision"]={"frame":fort.last_sync_frame,"ms":fort.last_sync_ms,"syncs":fort.sync_count,"rebuilds":fort.rebuild_count,"groups":fort.groups.size(),"profile":fort.profile.duplicate()}
	r["nodes"]=Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	r["memory_mib"]=Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0
	r["weather"]=world._weather.get_meta("frame_timing",{})
	r["lamps"]=world._weather.streetlamps.get_meta("frame_timing",{})
	r["toggles"]=toggle_count
	r["engine"]=engine_frame
	r["render_cpu"]=RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
	r["render_setup_cpu"]=RenderingServer.get_frame_setup_time_cpu()
	r["pipelines"]={"mesh":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),"surface":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),"draw":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),"specialization":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)}
	r["draw_calls"]=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	r["radar"]=world._hud._radar.get_meta("draw_timing",{})
	r["main_view"]=viewport_stats(root)
	r["outline_view"]=viewport_stats(world._outline.mask)
	r["outline_active"]=world._outline.occluded
	r["outline_cpu"]=RenderingServer.viewport_get_measured_render_time_cpu(world._outline.mask.get_viewport_rid())
	r["outline_gpu"]=RenderingServer.viewport_get_measured_render_time_gpu(world._outline.mask.get_viewport_rid())
	r["celestial_lights"]={"sun_energy":world._weather.sun.light_energy,"moon_energy":world._weather.moon.light_energy,"sun_visible":world._weather.sun.visible,"moon_visible":world._weather.moon.visible,"sun_shadow":world._weather.sun.shadow_enabled,"moon_shadow":world._weather.moon.shadow_enabled}
	# Keep the hot path free of synchronous console/JSON output. Printing a
	# large hitch record here would itself inflate the following frame.
	return now
func probe_collision_candidates()->void:
	# Isolate each resident collision candidate using a temporary physics bit.
	# No map records are edited; restore every body layer before returning.
	var player:CharacterBody3D=world._player
	var pose:=player.global_transform;pose.origin=Vector3(-336.487,.90083,15.96885)
	var old_mask:=player.collision_mask
	var baseline:=Time.get_ticks_usec()
	for i in 30:player.test_move(pose,Vector3(.015,-.003,.06))
	print("COLLISION_ALL_MS ",(Time.get_ticks_usec()-baseline)/30000.0)
	player.collision_mask=1<<19
	var rows:Array=[]
	var bodies:Dictionary=world._map_root.get_meta("stream_bodies",{})
	for spec:Dictionary in world._map_root.get_meta("stream_library",[]):
		var body:StaticBody3D=bodies.get(str(spec.uuid))
		if body==null:continue
		var source:Mesh=spec.get("collision_mesh",spec.get("mesh"))
		if source==null or not source.get_aabb().grow(1).has_point(body.global_transform.affine_inverse()*pose.origin):continue
		var layer:=body.collision_layer;body.collision_layer=1<<19
		var began:=Time.get_ticks_usec()
		for i in 30:player.test_move(pose,Vector3(.015,-.003,.06))
		var elapsed:float=(Time.get_ticks_usec()-began)/30000.0
		body.collision_layer=layer
		rows.append({"uuid":spec.uuid,"ms":elapsed,"shapes":body.get_children().map(func(n):return n.shape.get_class() if n is CollisionShape3D else n.get_class())})
	player.collision_mask=old_mask
	rows.sort_custom(func(a,b):return a.ms>b.ms)
	print("COLLISION_CANDIDATES ",JSON.stringify(rows))
	FileAccess.open(OUT.path_join(label_+"_collision_candidates.json"),FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
func run()->void:
	expect_shadow_gating="--expect-shadow-gating" in OS.get_cmdline_user_args()
	preload("res://scripts/world3d/stream_collision_preparer.gd").terrain_slicing_enabled=not "--legacy-collision" in OS.get_cmdline_user_args()
	create_timer(1200 if "--soak" in OS.get_cmdline_user_args() else 540).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1280,800)
	if "--no-vsync" in OS.get_cmdline_user_args():DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):label_=arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(OUT)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession");session.world3d_map_path=MAP;session.world3d_spawn=Vector3(-114.9,.9,-1.7)
	if "--street-end" in OS.get_cmdline_user_args():session.world3d_spawn=Vector3(-333,.9,-24)
	if "--fortifications" in OS.get_cmdline_user_args():session.world3d_spawn=Vector3(-575,.9,-96)
	if "--native" in OS.get_cmdline_user_args():
		var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(MAP)
		var loaded:Array=await loader.finished
		check(loaded[0]!=null,"native async loader prepared map")
		if loaded[0]==null:quit(1);return
		session.prepared_world3d=loaded[0];session.world3d_loading=true
	world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	if "--unshared-budget" in OS.get_cmdline_user_args():world.set_meta("profile_unshared_stream_budget",true)
	while not world.is_world_ready():
		report_preparation("world");await process_frame
	var flat_live:=0
	for spec:Dictionary in world._map_root.get_meta("stream_library",[]):
		var body:Node=world._map_root.get_meta("stream_bodies",{}).get(str(spec.uuid))
		if body==null:continue
		var flat:Dictionary=preload("res://scripts/world3d/flat_terrain_collision.gd").descriptor(spec)
		if not flat.is_empty():
			flat_live+=1
			check(body.get_child_count()==1 and body.get_child(0) is CollisionShape3D and body.get_child(0).shape is BoxShape3D,"resident flat terrain primitive "+str(spec.uuid))
		if str(spec.uuid)=="town_terrain_1_3":print("HOTSPOT_COLLISION ",{"flat":not flat.is_empty(),"record":spec.get("ground_batch_record",{}).keys(),"shapes":body.get_children().map(func(n):return n.shape.get_class() if n is CollisionShape3D else n.get_class())})
	print("FLAT_TERRAIN_RESIDENT ",flat_live)
	if "--collision-probe" in OS.get_cmdline_user_args():
		probe_collision_candidates();world.free();quit(1 if failures else 0);return
	if "--slice-resident" in OS.get_cmdline_user_args():
		# Diagnostic replacement of the measured hotspot's initially loaded body.
		# Keep exact triangles and leave the old collider active until ready.
		var spec:Dictionary=world._map_root.get_meta("stream_library").filter(func(s):return str(s.uuid)=="town_terrain_1_3")[0]
		var bodies:Dictionary=world._map_root.get_meta("stream_bodies")
		var old:Node=bodies[spec.uuid]
		var preparer=preload("res://scripts/world3d/stream_collision_preparer.gd").new();world._map_root.add_child(preparer)
		while not preparer.prepare(spec,world):await process_frame
		bodies[spec.uuid]=preload("res://scripts/world3d/world_stream.gd")._make_body(world,spec)
		old.free()
		await physics_frame;await physics_frame
		print("PASS diagnostic resident exact slices ",bodies[spec.uuid].get_child_count())
	if "--wait-nav" in OS.get_cmdline_user_args():
		while not world._navigation.fully_ready or world._navigation._surface_index==null:
			report_preparation("navigation");await process_frame
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
	world._player.set_meta("profile_frame",true)
	world._navigation.set_meta("profile_frame",true)
	world._weather.set_meta("profile_frame",true)
	world._weather.streetlamps.set_meta("profile_frame",true)
	world._map_root.set_meta("profile_frame",true)
	world._hud._radar.set_meta("profile_frame",true)
	world._map_root.get_node("GroundRenderBatches").set_meta("profile_frame",true)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	RenderingServer.viewport_set_measure_render_time(world._outline.mask.get_viewport_rid(),true)
	process_frame.connect(func():script_frame_start=Time.get_ticks_usec())
	physics_meter=PhysicsMeter.new();physics_meter.process_physics_priority=1000000;root.add_child(physics_meter)
	physics_frame.connect(func():physics_meter.began=Time.get_ticks_usec())
	RenderingServer.frame_pre_draw.connect(func():
		if force_legacy_shadows:
			world._weather.sun.shadow_enabled=bool(world._weather.values.sun_shadows)
			world._weather.moon.shadow_enabled=bool(world._weather.values.sun_shadows)
		draw_frame_start=Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func():engine_frame={"frame":Engine.get_process_frames(),"process_to_draw_ms":(draw_frame_start-script_frame_start)/1000.0,"draw_ms":(Time.get_ticks_usec()-draw_frame_start)/1000.0})
	world._request_environment({"time_hours":12.0,"time_speed":0.0})
	for i in 40:await process_frame
	physics_meter.total_ms=0;physics_meter.max_ms=0;physics_meter.steps=0
	var paths:Array=[Vector3(-144,0,-9),Vector3(-175,0,-16),Vector3(-206,0,-24),Vector3(-238,0,-32),Vector3(-269,0,-40),Vector3(-300,0,-47),Vector3(-329,0,-54.6),Vector3(-333,0,-24),Vector3(-333,0,8),Vector3(-327,0,40)]
	if "--street-end" in OS.get_cmdline_user_args():paths=[Vector3(-333,0,8),Vector3(-327,0,40),Vector3(-333,0,8),Vector3(-333,0,-24)]
	if "--fortifications" in OS.get_cmdline_user_args():paths=[Vector3(-584,0,-64),Vector3(-590,0,-32),Vector3(-591,0,0),Vector3(-591,0,32),Vector3(-587,0,64),Vector3(-582,0,96),Vector3(-574,0,128),Vector3(-566,0,160)]
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
			if "--shadow-ab" in OS.get_cmdline_user_args() and pass_==0 and target==Vector3(-333,0,8):await compare_shadow_work()
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
	report["script_debugger_active"]=EngineDebugger.is_active()
	report["surface_query_frame_domain"]="physics" # Other instrumented frame IDs use process frames.
	report["route"]="fortifications" if "--fortifications" in OS.get_cmdline_user_args() else ("street_end" if "--street-end" in OS.get_cmdline_user_args() else "streets")
	report["resident_slice_probe"]="--slice-resident" in OS.get_cmdline_user_args()
	report["terrain_slicing"]=not "--legacy-collision" in OS.get_cmdline_user_args()
	report["shared_stream_budget"]=not "--unshared-budget" in OS.get_cmdline_user_args()
	report["checked_shadow_gating"]=expect_shadow_gating
	report["shadow_comparison"]=shadow_comparison
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
	report.erase("samples");report.erase("worst");report.erase("toggle_timings");report.erase("click_timings");report.erase("shadow_comparison");print("ENTRY_PROFILE ",JSON.stringify(report));world.free();quit(1 if failures else 0)
