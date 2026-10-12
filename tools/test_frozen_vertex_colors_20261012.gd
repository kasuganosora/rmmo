extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/nonperformance_fixes_20261012"
var failures:=0
var camera:Camera3D
var host:Node3D
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func snap(label:String,eye:Vector3,target:Vector3)->void:
	camera.position=eye;camera.look_at(target)
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/color_"+label+".png")
func run()->void:
	create_timer(180).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1280,800);root.use_taa=false;root.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED;root.msaa_3d=Viewport.MSAA_DISABLED
	var read:=Doc.authoritative_extras("D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf")
	check(read.has("extras"),"hydrate current native map")
	if not read.has("extras"):quit(1);return
	var doc:=Doc.new();doc.records=read.extras.rmmo_records
	print("COLOR_DOCUMENT_OPEN records=",doc.records.size())
	var unique:Dictionary={};var records:=0;var enabled:=0;var disabled:=0;var bridge:Dictionary={};var nonwhite:=0
	for r:Dictionary in doc.records:
		if not r.has("house_prefab"):continue
		records+=1
		if r.has("bridge_mesh") and bridge.is_empty():bridge=r.duplicate(true)
		if "--photos-only" in OS.get_cmdline_user_args():continue
		var signature:String=r.house_prefab.sha256
		if unique.has(signature):continue
		unique[signature]=true
		print("COLOR_PAYLOAD ",r.uuid)
		var data:=House.decode(r.house_prefab);var geo:=House.geometry(r)
		var packed:=Cook.pack({["review"]:geo},"review","review")
		var restored:=Cook.restore(packed);var same:=not restored.is_empty()
		for field:String in ["mesh","source"]:
			var a:Mesh=geo[field];var b:Mesh=restored[["review"]][field]
			for i in a.get_surface_count():
				var am:Material=a.surface_get_material(i);var bm:Material=b.surface_get_material(i)
				if am is StandardMaterial3D and bm is StandardMaterial3D:
					same=same and am.vertex_color_use_as_albedo==bm.vertex_color_use_as_albedo
					if am.vertex_color_use_as_albedo:enabled+=1
					else:disabled+=1
				var ac:Variant=a.surface_get_arrays(i)[Mesh.ARRAY_COLOR];var bc:Variant=b.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
				same=same and var_to_bytes(ac)==var_to_bytes(bc)
		check(same,"render/collision cache preserves authored color arrays and policy "+r.uuid)
	check(not bridge.is_empty(),"formal bridge available")
	host=Node3D.new();root.add_child(host)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);light.shadow_enabled=true;host.add_child(light)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.42,.60,.76);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.65;host.add_child(env)
	camera=Camera3D.new();host.add_child(camera);camera.current=true
	var geometry:=House.geometry(bridge);var original:Mesh=geometry.mesh
	for i in original.get_surface_count():
		var colors:Variant=original.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
		if colors is PackedColorArray:
			for c:Color in colors:
				if c!=Color.WHITE:nonwhite+=1
	var packed:=Cook.pack({["review"]:geometry},"review","review");var restored:=Cook.restore(packed)
	var node:=MeshInstance3D.new();host.add_child(node)
	var bounds:=original.get_aabb();var center:=bounds.get_center();var length:=maxf(bounds.size.x,bounds.size.z)
	for mode in ["baseline","repeat","restored","forced"]:
		node.mesh=(restored[["review"]].mesh if mode=="restored" else original).restore()
		for i in node.mesh.get_surface_count():
			var material:StandardMaterial3D=node.mesh.surface_get_material(i).duplicate()
			if mode=="forced":material.vertex_color_use_as_albedo=true
			node.set_surface_override_material(i,material)
		await snap(mode+"_near",center+Vector3(0,3.5,5),center)
		await snap(mode+"_mid",center+Vector3(length*.4,8,length*.5),center)
		await snap(mode+"_far",center+Vector3(length,15,length),center)
	if not "--photos-only" in OS.get_cmdline_user_args():FileAccess.open(OUT+"/vertex_colors.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"records":records,"unique_payloads":unique.size(),"enabled_surface_checks":enabled,"disabled_surface_checks":disabled,"bridge_nonwhite_vertices":nonwhite,"policy":"preserve each frozen payload; no legacy implicit enablement"},"\t"))
	print("FROZEN_COLORS failures=",failures," records=",records," unique=",unique.size());host.free();quit(failures)
