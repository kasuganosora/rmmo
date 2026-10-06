extends SceneTree
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const BASE="D:/code/rmmo_runtime"
func _initialize()->void:run.call_deferred()
func run()->void:
	var out:=BASE+"/review_artifacts/town_props_20261006"
	var id:="town_market_stalls_03_potion_vendor"
	var library:=Library.new(BASE+"/cache/world3d/potion_glass_final/assets")
	var imported:=library.import_file(BASE+"/assets/town_props_20261006/"+id+".glb")
	if not imported.ok:quit(1);return
	var model:=Library.instantiate_preview(imported.entry.asset_path);var meshes:=Paint.meshes(model);var count:=0;var triangles:=0
	for mesh in meshes:
		for s in mesh.mesh.get_surface_count():
			var material:Material=mesh.mesh.surface_get_material(s)
			if material is StandardMaterial3D and material.resource_name.contains("alchemist glass") and material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:count+=1
			var arrays:=mesh.mesh.surface_get_arrays(s);triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
	if count<3:push_error("Potion glass must remain three transparent glass materials");quit(1);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(1200,900);viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_4X;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport);viewport.add_child(model)
	var world:=WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color(.22,.25,.29);world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color(.8,.88,1);world.environment.ambient_light_energy=.65;viewport.add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.shadow_enabled=true;viewport.add_child(sun)
	var floor:=MeshInstance3D.new();floor.mesh=PlaneMesh.new();floor.scale=Vector3(20,1,20);viewport.add_child(floor)
	var bounds:=Library.bounds_of(model);var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=maxf(bounds.size.x,bounds.size.y)*1.4;viewport.add_child(cam);cam.position=bounds.get_center()+Vector3(4,2.5,6);cam.look_at(bounds.get_center())
	for i in 10:await process_frame
	await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(out+"/"+id+".png")
	var report:Variant=JSON.parse_string(FileAccess.get_file_as_string(out+"/validation.json"))
	if not report is Dictionary or report.get("failures",1)!=0:push_error("Baseline validation required");quit(1);return
	for row in report.assets:
		if row.id==id:row.entry=imported.entry;row.triangles=triangles;row.mesh_count=meshes.size();row.transparent_glass_materials=count
	report.potion_glass_incremental_verified=true
	var f:=FileAccess.open(out+"/validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close();print("POTION_GLASS_VERIFIED ",count);quit()
