extends SceneTree
## Imports/packages the Blender asset; validates isolated placement and optional night scene.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Prefabs=preload("res://scripts/world_editor/prefab_library.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Lamp=preload("res://scripts/world3d/banner_streetlamp.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
var failed:=0
var out:String
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failed+=1
func own_children(node:Node,owner_:Node)->void:
	for child in node.get_children():child.owner=owner_;own_children(child,owner_)
func count_meshes(node:Node)->Array:
	var result:Array=[]
	if node is MeshInstance3D:result.append(node)
	for child in node.get_children():result.append_array(count_meshes(child))
	return result
func make_lamp(path:String)->Node3D:
	var n:=Node3D.new();n.name="BannerStreetlamp";n.set_script(Lamp)
	var model:=Library.instantiate_preview(path);n.add_child(model);model.name="Model"
	var body:=StaticBody3D.new();body.name="PostCollision";n.add_child(body)
	var shape:=CollisionShape3D.new();var cylinder:=CylinderShape3D.new();cylinder.radius=.105;cylinder.height=3.08;shape.shape=cylinder;shape.position.y=1.54;body.add_child(shape)
	var foot:=CollisionShape3D.new();var base:=CylinderShape3D.new();base.radius=.19;base.height=.12;foot.shape=base;foot.position.y=.06;body.add_child(foot)
	var light:=OmniLight3D.new();light.name="NightLight";light.position=Lamp.CRYSTAL_POSITION;light.light_color=Color(.06,.48,1);light.light_energy=.75;light.omni_range=7.0;light.shadow_enabled=false;light.visible=false;n.add_child(light)
	own_children(n,n);return n
func run()->void:
	out=Art.review_path("banner_streetlamp/report.json").get_base_dir()
	var source:=Art.path("banner_streetlamp/banner_streetlamp.glb")
	var model:=Library.instantiate_preview(source)
	check(model!=null,"Godot GLTFDocument imports actual Blender GLB")
	if model==null:quit(1);return
	var meshes:=count_meshes(model);var surfaces:=0;var triangles:=0;var valid:=true
	for m:MeshInstance3D in meshes:
		surfaces+=m.mesh.get_surface_count()
		for surface in m.mesh.get_surface_count():
			var arrays:=m.mesh.surface_get_arrays(surface);var positions:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			triangles+=indices.size()/3
			for p in positions:valid=valid and p.is_finite()
			for i in range(0,indices.size(),3):
				var area2:float=(positions[indices[i+1]]-positions[indices[i]]).cross(positions[indices[i+2]]-positions[indices[i]]).length_squared()
				valid=valid and area2>1e-15
	var bounds:=Library.bounds_of(model)
	check(meshes.size()==4 and surfaces==7 and triangles<6000,"four meshes with independent fabric, seven shared materials, under 6000 triangles")
	check(preload("res://scripts/world3d/streetlamp_banner.gd").slot(model)!=null,"explicit replaceable cloth slot survives GLB import")
	check(valid and absf(bounds.position.y)<.001 and bounds.size.y>4.0 and bounds.size.y<4.2,"finite nondegenerate triangles and metre-scale ground pivot")
	model.free()
	var pack_path:=Art.path("banner_streetlamp/library")
	var library:=Library.new(pack_path)
	# Replace only this generator's named catalog entries; immutable old blobs remain valid.
	library.entries=library.entries.filter(func(entry):return entry.get("label","") not in ["banner_streetlamp","古铜旗幡路灯（静态）","古铜旗幡路灯（可换旗·随风）"])
	var imported:=library.import_file(source);check(imported.ok,"import self-contained resource pack")
	if not imported.ok:quit(1);return
	var doc:=Doc.new();var id:=doc.add_asset(imported.entry,Vector3.ZERO);doc._find(id).collision="block"
	var saved:=Prefabs.capture(doc.records,library,"古铜旗幡路灯（可换旗·随风）")
	check(saved.ok,"capture one-record native editor prefab")
	if not saved.ok:print(saved);quit(1);return
	var destination:=Doc.new();var placed:=Prefabs.place(destination,saved.entry,Vector3(3,0,2))
	check(placed.ok and destination.records.size()==1,"native prefab placement is a single asset record")
	check(destination.undo() and destination.records.is_empty() and destination.redo() and destination.records.size()==1,"native placement undo and redo")
	var temp:=Paths.cache_directory("banner_streetlamp_test").path_join("map.gltf")
	check(destination.save(temp)==OK,"save isolated test map")
	var opened=Doc.open_file(temp);check(opened!=null and opened.records.size()==1 and opened.missing_assets().is_empty(),"reopen resolves packaged dependency")
	var source_scene:=make_lamp(source);var packed:=PackedScene.new();check(packed.pack(source_scene)==OK,"pack independent Godot scene with simple collision and dark-by-default lights")
	var scene_path:=Art.path("banner_streetlamp/banner_streetlamp.tscn")
	check(ResourceSaver.save(packed,scene_path)==OK,"save reusable Godot scene")
	source_scene.free()
	var viewport:=SubViewport.new();viewport.size=Vector2i(1000,1100);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.15,.18,.19);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.86,.91,1);env.environment.ambient_light_energy=.5;viewport.add_child(env)
	env.environment.glow_enabled=true;env.environment.glow_intensity=.7;env.environment.glow_bloom=.1
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-32,0);sun.shadow_enabled=true;viewport.add_child(sun)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(30,30);floor.mesh=plane;var ground:=StandardMaterial3D.new();ground.albedo_color=Color(.30,.32,.28);plane.material=ground;viewport.add_child(floor)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.7;viewport.add_child(camera);camera.position=Vector3(4.8,4.7,10);camera.look_at(Vector3(-.32,2.05,0))
	var lamps:Array=[]
	for i in 4:
		var n:Node3D=packed.instantiate();viewport.add_child(n);n.position.x=i*3.0;lamps.append(n)
	check(Lamp.update_group(lamps,Vector3.ZERO,12,2)==0,"daytime has no active lights")
	check(not lamps[0].is_crystal_lit() and lamps[0].find_child("ArcaneCrystal",true,false)!=null,"daytime blue crystal exists without emission")
	check(Lamp.update_group(lamps,Vector3.ZERO,21,2)==2,"night group respects two-light cap")
	check(lamps[0].is_crystal_lit(),"nighttime crystal surfaces emit light")
	var crystal_a:MeshInstance3D=lamps[0].get_node("Model/ArcaneCrystal")
	var crystal_b:MeshInstance3D=lamps[1].get_node("Model/ArcaneCrystal")
	var shared_night:=crystal_a.get_surface_override_material(0)
	var material_count:int=Lamp._night_materials.size()
	for i in 8:Lamp.update_group(lamps,Vector3.ZERO,21,2)
	check(Lamp._night_materials.size()==material_count and crystal_a.get_surface_override_material(0)==shared_night and crystal_b.get_surface_override_material(0)==shared_night,"repeated night calls allocate no materials and instances share night materials")
	check(not lamps[2].get_node("NightLight").visible and not lamps[3].get_node("NightLight").visible,"nearest lamps win budget")
	check(Lamp.update_group(lamps,Vector3.ZERO,21,0)==0,"no remaining shared budget means no dynamic light")
	check(Lamp.update_group(lamps,Vector3(100,0,0),21,2)==0,"distant lights are disabled")
	check(Lamp.update_group(lamps,Vector3.ZERO,6,2)==0 and Lamp.update_group(lamps,Vector3.ZERO,20,1)==1,"shared candle night boundaries and one-light budget")
	lamps[0].visible=false;Lamp.update_group(lamps,Vector3.ZERO,21,2);check(not lamps[0].is_crystal_lit() and not lamps[0].get_node("NightLight").visible,"hidden fixture disables all presentation")
	lamps[0].visible=true
	for i in range(1,4):lamps[i].queue_free()
	await process_frame;lamps.resize(1)
	for mode in ["day","night","back","scroll_front","scroll_back","lantern_front","lantern_back","crystal_night"]:
		var nighttime:bool=mode in ["night","crystal_night"];sun.light_energy=.05 if nighttime else 1.0;env.environment.ambient_light_energy=.07 if nighttime else .5
		Lamp.update_group(lamps,Vector3.ZERO,22 if nighttime else 12,2)
		if mode=="back":camera.position=Vector3(-4.5,3.5,-10);camera.look_at(Vector3(-.32,2.05,0))
		if mode in ["scroll_front","scroll_back"]:
			camera.size=.65;camera.position=Vector3(-1.8,3.2,2.0) if mode=="scroll_front" else Vector3(-1.8,3.2,-2.0);camera.look_at(Vector3(-.8,2.985,0))
		if mode in ["lantern_front","lantern_back"]:
			camera.size=1.05;camera.position=Vector3(1.5,3.8,2.0) if mode=="lantern_front" else Vector3(-1.5,3.8,-2.0);camera.look_at(Vector3(0,3.46,0))
		if mode=="crystal_night":camera.size=1.05;camera.position=Vector3(1.5,3.8,2);camera.look_at(Vector3(0,3.46,0))
		for i in 8:await process_frame
		await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(out.path_join(mode+".png"))
	var report={"failures":failed,"meshes":meshes.size(),"surfaces":surfaces,"triangles":triangles,"bounds_y":bounds.size.y,"prefab":saved.entry,"scene":scene_path,"formal_map_modified":false}
	var f:=FileAccess.open(out.path_join("report.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("BANNER_STREETLAMP_RESULT ",JSON.stringify(report));quit(1 if failed else 0)
