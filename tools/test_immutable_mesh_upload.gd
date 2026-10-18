extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func same(a:Mesh,b:Mesh,label:String)->void:
	check(a.get_surface_count()==b.get_surface_count(),label+" slots")
	check(a.get_aabb().is_equal_approx(b.get_aabb()),label+" bounds")
	check(a.get_faces()==b.get_faces(),label+" collision faces")
	for slot in a.get_surface_count():
		check(var_to_bytes(Cpu.capture(a).surfaces[slot])==var_to_bytes(Cpu.capture(b).surfaces[slot]),label+" every CPU vertex channel "+str(slot))
		check(a.surface_get_material(slot)==b.surface_get_material(slot),label+" material identity "+str(slot))
func run()->void:
	var record:Dictionary={"uuid":"road","kind":"box","position":[321,0,160],"rotation":[0,37,0],"size":[32,.18,32],"surface_id":"block","collision":"block","road_mesh":{"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[320,0,160]}}
	var arrays:=Road.arrays(record);var frozen:=var_to_bytes(arrays)
	var legacy:=Doc.new();legacy.load_surface_arrays={"road":arrays}
	var runtime:=Doc.new();runtime.load_immutable_records=true;runtime.load_surface_arrays={"road":arrays}
	var before:=legacy._mesh(record);var after:=runtime._mesh(record)
	check(before.mesh is ArrayMesh and after.mesh is Cpu,"only immutable runtime defers GPU source upload")
	check(not after.mesh.get_rid().is_valid(),"prepared mesh has no GPU allocation")
	same(before.mesh,after.mesh,"road")
	var geometry:=Paint.geometry(before)
	var material:Dictionary={"name":"paint fixture","color":[.4,.3,.2,1.],"roughness":.8}
	var entries:Array=[{"mesh":".","surface":0,"face":geometry.surfaces[0].faces.keys()[0],"geometry":geometry.surfaces[0].signature,"mapping":"uv","material":material,"scale":[1.,1.],"offset":[0.,0.],"rotation":0.}]
	var painted_old:=Paint.painted_mesh(before,entries,true,{})
	var baseline_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-paint="):baseline_path=arg.trim_prefix("--baseline-paint=")
	if not baseline_path.is_empty():
		var baseline:Script=load(baseline_path)
		var frozen_result:Dictionary=baseline.painted_mesh(before,entries,true,{})
		check(frozen_result.ok,"frozen pre-review paint succeeds")
		if frozen_result.ok:
			check(frozen_result.mesh.get_surface_count()==painted_old.mesh.get_surface_count(),"frozen output slot count")
			for slot in frozen_result.mesh.get_surface_count():
				check(var_to_bytes(Cpu.capture(frozen_result.mesh).surfaces[slot])==var_to_bytes(Cpu.capture(painted_old.mesh).surfaces[slot]),"frozen output all channels "+str(slot))
				check(preload("res://scripts/world3d/runtime_mesh_cache.gd").material_data(frozen_result.mesh.surface_get_material(slot))==preload("res://scripts/world3d/runtime_mesh_cache.gd").material_data(painted_old.mesh.surface_get_material(slot)),"frozen output material definition "+str(slot))
	var painted_new:=Paint.painted_mesh(after,entries,true,{},true)
	check(painted_old.ok and painted_new.ok,"painted road preparation succeeds")
	if painted_old.ok and painted_new.ok:
		check(painted_new.mesh is Cpu and not painted_new.mesh.get_rid().is_valid(),"paint never temporarily uploads immutable geometry")
		same(painted_old.mesh,painted_new.mesh,"painted road")
		var restored:Mesh=painted_new.mesh.restore()
		check(restored.get_rid().is_valid(),"actual render publication uploads GPU mesh")
		same(painted_old.mesh,restored,"published paint")
	check(frozen==var_to_bytes(arrays),"source channels unchanged")
	var painted_record:Dictionary=record.duplicate(true);painted_record.surface_paint=entries
	before.set_surface_override_material(0,before.mesh.surface_get_material(0))
	Paint.apply(before,painted_record,null,{},true)
	check(before.mesh is Cpu and not before.has_meta("paint_error"),"GPU source with instance overrides can become painted CPU geometry")
	for slot in before.get_surface_override_material_count():check(before.get_surface_override_material(slot)==null,"CPU publication clears former override slot "+str(slot))
	Paint.apply(after,painted_record,null,{},true)
	check(after.mesh is Cpu and not after.has_meta("paint_error"),"CPU source paint never sends logical slots to renderer")
	await failed_image_handoff()
	before.free();after.free()
	print("IMMUTABLE_UPLOAD_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures==0 else 1)
func failed_image_handoff()->void:
	var paths=preload("res://scripts/world3d/map_paths.gd")
	var folder:String=paths.cache_directory("texture_handoff_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(folder)
	var path:String=folder.path_join("image.png")
	var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color.RED);image.save_png(path)
	var definition:Dictionary={"name":"failure fixture","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":path}
	var old:StandardMaterial3D=Paint.make_material(definition)
	Paint._textures.erase(path);Paint._materials.clear()
	image.fill(Color.BLUE);image.save_png(path)
	var installer=preload("res://scripts/world_editor/terrain_texture_preparation.gd")
	var previous:Dictionary=installer.install({"images":{},"failed":[path]})
	var current:StandardMaterial3D=Paint.make_material(definition)
	check(current!=old and current.albedo_texture!=old.albedo_texture,"failed preparation invalidates hot and weak material/texture aliases")
	RenderingServer.force_sync()
	check(current.albedo_texture.get_image().get_pixel(0,0).b>.9 and old.albedo_texture.get_image().get_pixel(0,0).r>.9,"repaired source loads current pixels while existing consumer keeps old pixels")
	installer.restore(previous);Paint.refresh_sources();old=null;current=null
	DirAccess.remove_absolute(path)
	var cache:String=preload("res://scripts/world3d/runtime_texture_cache.gd").cache_path(path,false)
	if FileAccess.file_exists(cache):DirAccess.remove_absolute(cache)
	DirAccess.remove_absolute(folder)
