extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Thumb=preload("res://scripts/world_editor/asset_thumbnails.gd")
const BASE="D:/code/rmmo_runtime"
const ART=BASE+"/art_sources/garden_boundary/height_150"
const OUT=BASE+"/review_artifacts/garden_boundary/material_review"
const LABELS=["写实石围墙·1.5米高·2.4米直墙","写实石围墙·1.5米高·1.2米直墙","写实石立柱·1.95米","写实石立柱·1.8米","写实石围墙·1.5米高·L形转角","写实石围墙·1.5米高·0.8米短墙"]
func run()->void:
	create_timer(600).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	DirAccess.make_dir_recursive_absolute(OUT)
	var specs=JSON.parse_string(FileAccess.get_file_as_string(ART+"/manifest.json")).assets
	var verified=JSON.parse_string(FileAccess.get_file_as_string(ART+"/validation.json"))
	if not verified.failures.is_empty() or specs.size()!=6:quit(1);return
	var directory=Paths.cache_directory("garden_boundary_%d"%Time.get_ticks_usec())
	var local=Library.new(directory+"/assets");var rows:Array=[]
	var vp=SubViewport.new();vp.size=Vector2i(800,600);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.25,.28,.26);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.8,.88,1);env.environment.ambient_light_energy=.65;vp.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);sun.shadow_enabled=true;sun.light_energy=1.5;vp.add_child(sun)
	var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;vp.add_child(cam)
	for i in specs.size():
		var spec=specs[i];var file=ART+"/models/"+spec.id+".glb"
		check(FileAccess.get_sha256(file)==spec.sha256,"approved file hash "+spec.id)
		var imported={"ok":true,"entry":{"asset_path":file}}
		if not imported.ok:quit(1);return
		var model=Library.instantiate_preview(imported.entry.asset_path);var meshes=Paint.meshes(model);var tri=0
		check(meshes.size()==1,"one mesh per module")
		for mesh in meshes:
			check(mesh.mesh.get_surface_count()==2,"stone and mortar surfaces")
			var materials=[]
			for surface in mesh.mesh.get_surface_count():materials.append(mesh.mesh.surface_get_material(surface))
			var candidates=materials.filter(func(m):return m is StandardMaterial3D and m.albedo_texture!=null)
			check(candidates.size()==1,"one textured stone material")
			var mat=candidates[0]
			check(mat is StandardMaterial3D and mat.albedo_texture!=null and mat.normal_enabled and mat.normal_texture!=null and mat.roughness_texture!=null,"runtime PBR channels")
			tri+=mesh.mesh.get_faces().size()/3
		check(tri==spec.game_triangles,"triangle count "+spec.id)
		vp.add_child(model);var bounds=Library.bounds_of(model);var center=bounds.get_center()
		check(absf(bounds.end.y-spec.recipe.height)<.005,"approved physical height")
		cam.size=maxf(bounds.size.y,maxf(bounds.size.x,bounds.size.z))*1.6;cam.position=center+Vector3(.3,2,3);cam.look_at(center)
		await create_timer(2.0).timeout
		for frame in 30:await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(OUT+"/"+spec.id+".png")
		rows.append({"id":spec.id,"label":LABELS[i],"entry":imported.entry,"source_sha256":spec.sha256,"triangles":tri})
		model.queue_free();await process_frame
	vp.queue_free();await settle()
	if failed:quit(1);return
	print("GARDEN_THUMB_FAILURES ",failed);quit(1 if failed else 0)
