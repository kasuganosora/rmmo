extends SceneTree
const OUT = "D:/code/rmmo/review_artifacts/alarm_tower_game_20261011"
const SOURCE = "D:/code/rmmo/review_artifacts/alarm_tower_materials_v3_20261011/guild_alarm_tower.glb"
const Visibility = preload("res://scripts/world3d/asset_visibility_range.gd")
var errors: Array = []
var report := {}
var camera: Camera3D
var scenes: Array[Node3D] = []
var prepared := {}
func _initialize() -> void:
	create_timer(100).timeout.connect(func(): quit(124))
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)
func load_asset(path: String) -> Node3D:
	var doc := GLTFDocument.new(); var state := GLTFState.new()
	check(doc.append_from_file(path,state)==OK,"import: "+path)
	var scene := doc.generate_scene(state) as Node3D
	root.add_child(scene)
	Visibility.apply(scene)
	var mats := {}
	for node in scene.find_children("*","MeshInstance3D",true,false):
		for surface in node.mesh.get_surface_count():
			var mat := node.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat==null or mats.has(mat.get_instance_id()): continue
			mats[mat.get_instance_id()]=true
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO,BaseMaterial3D.TEXTURE_NORMAL,BaseMaterial3D.TEXTURE_ROUGHNESS]:
				var tex := mat.get_texture(slot)
				if tex==null: continue
				if not prepared.has(tex.get_instance_id()):
					var pixels := tex.get_image()
					if not pixels.has_mipmaps(): pixels.generate_mipmaps()
					prepared[tex.get_instance_id()]=ImageTexture.create_from_image(pixels)
				mat.set_texture(slot,prepared[tex.get_instance_id()])
			mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	scene.visible=false
	return scene
func stats() -> Dictionary:
	var rid := root.get_viewport_rid()
	return {"draw_calls":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"rendered_primitives":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"rendered_objects":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)}
func settle() -> void:
	for i in range(24): await process_frame
	await RenderingServer.frame_post_draw
func shot(scene: Node3D, label: String, eye: Vector3, aim: Vector3) -> Dictionary:
	for s in scenes:s.visible=s==scene
	camera.position=eye;camera.look_at(aim)
	await settle()
	check(root.get_texture().get_image().save_png(OUT+"/"+label+".png")==OK,"capture "+label)
	return stats()
func run() -> void:
	root.size=Vector2i(1400,1100);root.content_scale_size=Vector2i.ZERO
	root.msaa_3d=Viewport.MSAA_4X;root.use_taa=false
	var env := Environment.new();env.background_mode=Environment.BG_SKY
	var sky := Sky.new();var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color=Color(.22,.34,.52);sm.sky_horizon_color=Color(.7,.75,.8)
	sm.ground_bottom_color=Color(.18,.15,.11);sm.ground_horizon_color=Color(.7,.75,.8)
	sky.sky_material=sm;env.sky=sky;env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy=.7;env.tonemap_mode=Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new();world.environment=env;root.add_child(world)
	var sun := DirectionalLight3D.new();root.add_child(sun);sun.rotation_degrees=Vector3(-45,-25,0)
	sun.light_energy=1.5;sun.shadow_enabled=true
	camera=Camera3D.new();root.add_child(camera);camera.current=true;camera.fov=50;camera.far=800
	var master := load_asset(SOURCE)
	var game := load_asset(OUT+"/guild_alarm_tower_game.glb")
	scenes=[master,game]
	var groups := [0,0,0];var triangles := [0,0,0];var surfaces := [0,0,0]
	var collision_nodes := 0
	var common_center := Vector3(0,16.685,0)
	for node in game.find_children("*","MeshInstance3D",true,false):
		var extra: Dictionary=node.get_meta("extras",{})
		var level: int=int(extra.get("lod_level",-1));check(level in [0,1,2],"valid LOD level")
		if level not in [0,1,2]:continue
		groups[level]+=1;surfaces[level]+=node.mesh.get_surface_count()
		for slot in node.mesh.get_surface_count():triangles[level]+=node.mesh.surface_get_array_index_len(slot)/3
		check((node.global_transform*node.custom_aabb.get_center()).distance_to(common_center)<.002,"common tower LOD centre")
		if extra.get("rmmo_collision","")=="block":
			collision_nodes+=1;check(level==0,"one permanent collision representation")
		if extra.get("source_part","")=="shaft":
			check(extra.get("shooting_slit_count",0)==16,"slits retained at every level")
	check(groups==[12,12,12],"12 independently grouped components per level")
	check(triangles[0]<230064 and triangles[1]<triangles[0] and triangles[2]<triangles[1],"decreasing actual triangle counts")
	check(collision_nodes==3,"only shaft/crown/roof create collision once")
	report["lod_triangles"]=triangles;report["lod_surfaces"]=surfaces
	report["independent_component_counts"]=groups;report["collision_nodes"]=collision_nodes
	var shots := {"near":[Vector3(14,32,18),Vector3(0,27.3,0)],
		"horn_close":[Vector3(10,28,6),Vector3(4.8,25.9,0)],
		"medium":[Vector3(45,35,60),common_center],"far":[Vector3(90,65,135),common_center]}
	var views := {}
	for name in shots:
		views[name]={"master":await shot(master,"master_"+name,shots[name][0],shots[name][1]),
			"game":await shot(game,"game_"+name,shots[name][0],shots[name][1])}
	report["views"]=views
	# Compare actual automatic culling with exactly one forced LOD at both sides
	# of each switch. This detects accidental all-LOD rendering and empty ranges.
	var transitions := []
	for distance in [38.,42.,108.,112.,250.]:
		master.visible=false;game.visible=true
		camera.position=common_center+Vector3(1,.12,1).normalized()*distance;camera.look_at(common_center)
		for node in game.find_children("*","MeshInstance3D",true,false):node.visible=true;Visibility.register(node)
		await settle();var automatic := stats()
		if distance in [42.,112.]:root.get_texture().get_image().save_png(OUT+"/switch_"+str(int(distance))+"_automatic.png")
		var expected := 0 if distance<40 else (1 if distance<110 else 2)
		for node in game.find_children("*","MeshInstance3D",true,false):
			node.visible=int(node.get_meta("extras",{}).get("lod_level",-1))==expected
			node.visibility_range_begin=0;node.visibility_range_end=0
		await settle();var forced := stats()
		check(automatic.rendered_primitives==forced.rendered_primitives and automatic.rendered_primitives>0,"actual LOD switch at "+str(distance))
		transitions.append({"distance":distance,"level":expected,"automatic":automatic,"forced":forced})
		if distance in [42.,112.]:
			for node in game.find_children("*","MeshInstance3D",true,false):
				node.visible=int(node.get_meta("extras",{}).get("lod_level",-1))==expected-1
			await settle()
			root.get_texture().get_image().save_png(OUT+"/switch_"+str(int(distance))+"_previous.png")
	report["transitions"]=transitions
	for node in game.find_children("*","MeshInstance3D",true,false):node.visible=true;Visibility.register(node)
	var save_doc := GLTFDocument.new();var save_state := GLTFState.new()
	check(save_doc.append_from_scene(game,save_state)==OK,"roundtrip append")
	check(save_doc.write_to_filesystem(save_state,OUT+"/review_roundtrip.glb")==OK,"roundtrip save")
	var reopened_doc := GLTFDocument.new();var reopened_state := GLTFState.new()
	check(reopened_doc.append_from_file(OUT+"/review_roundtrip.glb",reopened_state)==OK,"roundtrip reopen")
	var reopened := reopened_doc.generate_scene(reopened_state)
	root.add_child(reopened);Visibility.apply(reopened)
	var roundtrip_nodes := 0
	for node in reopened.find_children("*","MeshInstance3D",true,false):
		var extra: Dictionary=node.get_meta("extras",{})
		var level: int=int(extra.get("lod_level",-1))
		check(level in [0,1,2],"roundtrip LOD metadata")
		if level not in [0,1,2]:continue
		check(node.visibility_range_begin==[0.,40.,110.][level] and node.visibility_range_end==[40.,110.,0.][level],"roundtrip distances")
		roundtrip_nodes+=1
	check(roundtrip_nodes==36,"all 36 LOD nodes persisted")
	reopened.queue_free();report["roundtrip_lod_nodes"]=roundtrip_nodes
	report["passed"]=errors.is_empty();report["errors"]=errors
	report["sha256"]=FileAccess.get_sha256(OUT+"/guild_alarm_tower_game.glb")
	report["scope"]="Single isolated tower; actual shared visibility-range adapter; draw counters exclude shadow passes; no city FPS claim or editor publication"
	var file := FileAccess.open(OUT+"/game_review.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"))
	print("ALARM_GAME_REVIEW ",JSON.stringify(report));quit(0 if errors.is_empty() else 1)
