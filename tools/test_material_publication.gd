extends "res://tools/test_prefab_texture_preparation.gd"
## Tiny temporary resources. Run on the private GPU desktop, not house interiors.
const Slices=preload("res://scripts/world3d/material_publication.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const SchedulerFixture=preload("res://tools/test_deferred_ready_progress.gd")
class Document extends RefCounted:
	var calls:Dictionary={}
	var load_material_pool:Dictionary={}
	var load_paint_validation:Dictionary={}
	func _mesh(record:Dictionary,_effects:bool=true,_timings:Variant=null)->Node3D:
		calls[record.uuid]=int(calls.get(record.uuid,0))+1
		return Node3D.new()
func clear_caches()->void:
	Prefab._meshes.clear();Prefab._render_meshes.clear();Paint._textures.clear();Paint._materials.clear()
	Paint._texture_refs.clear();Paint._material_refs.clear()
func run()->void:
	if not check_gpu():quit(1);return
	var logger:=Errors.new();OS.add_logger(logger)
	files=Files.new();files.content_root=Prep.Paths.external_root();files.folder=Prep.Paths.cache_directory("material_slices_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var path:String=files.folder.path_join("pixels.png");files.created.append(path)
	var image:=Image.create(19,13,false,Image.FORMAT_RGBA8)
	for y:int in 13:
		for x:int in 19:image.set_pixel(x,y,Color(float(x%7)/6.,float(y%5)/4.,float((x+y)%9)/8.,.4 if x<4 else 1.))
	check(image.save_png(path)==OK,"save isolated alpha/normal fixture")
	var paint:Dictionary={"name":"sliced fixture","color":[.9,.8,.7,1.],"roughness":.8,"texture_path":path,"normal_path":path,"normal_format":"directx","normal_strength":.6,"roughness_path":path,"ao_path":path}
	var slot:Dictionary={"paint":paint,"cull":0}
	var record:=bridge("sliced",0,paint)
	var cpu:=Prefab.prepare_cpu(record)
	check(not cpu.is_empty(),"prepare exact native prefab geometry")
	clear_caches()
	var pool:Dictionary={};var validation:Dictionary={}
	check(Slices.step([slot],validation,pool)==Slices.PROGRESS and Paint._textures.size()==1 and pool.is_empty(),"first turn completes one texture, no partial material")
	check(Slices.step([slot],validation,pool)==Slices.PROGRESS and Paint._textures.size()==2 and pool.is_empty(),"next turn prepares distinct DirectX normal orientation")
	check(Slices.step([slot],validation,pool)==Slices.PROGRESS and pool.has([slot]),"third turn restores one complete material using shared textures")
	var sliced:StandardMaterial3D=pool[[slot]]
	check(Slices.step([slot],validation,pool)==Slices.READY and pool[[slot]]==sliced,"complete pool is immediately ready and identity stays shared")
	check(Prefab.publish_prepared(record,cpu,validation,pool),"ordinary prefab restore consumes prepared material pool")
	var sliced_geometry:Dictionary=Prefab._meshes[record.house_prefab.sha256]
	check(sliced_geometry.mesh.materials[0]==sliced,"prefab and incremental material use identical resource identity")
	clear_caches()
	var legacy_pool:Dictionary={}
	check(Prefab.publish_prepared(record,cpu,{},legacy_pool),"legacy synchronous prefab restore succeeds")
	var legacy:StandardMaterial3D=legacy_pool[[slot]]
	RenderingServer.force_sync()
	for field:String in ["albedo_texture","normal_texture","roughness_texture","ao_texture"]:
		check(canonical(sliced.get(field).get_image())==canonical(legacy.get(field).get_image()),field+" exact GPU pixels and mips match")
	for field:String in ["albedo_color","normal_scale","normal_enabled","ao_enabled","transparency","texture_filter","roughness","cull_mode"]:
		check(sliced.get(field)==legacy.get(field),field+" retains synchronous material semantics")
	check(sliced.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA and sliced.albedo_texture.get_meta("runtime_source_sha256")==FileAccess.get_sha256(path),"alpha and exact immutable source SHA retained")
	check(sliced_geometry.mesh.surfaces==Prefab._meshes[record.house_prefab.sha256].mesh.surfaces and sliced_geometry.mesh._collision_faces==cpu.collision_faces[0],"render arrays and collision triangles unchanged")
	var tinted:=slot.duplicate(true);tinted.vertex_color=true
	check(Slices.step([tinted],validation,pool)==Slices.PROGRESS and pool[[tinted]]!=sliced and pool[[tinted]].vertex_color_use_as_albedo and not sliced.vertex_color_use_as_albedo,"vertex tint gets an independent material without mutating shared walls")
	var stored:Dictionary={"values":{"roughness":.3,"albedo_color":Color.RED}}
	check(Slices.step([stored,{"null":true}],{},pool)==Slices.PROGRESS and is_equal_approx(pool[[stored]].roughness,.3),"stored material uses validated property restoration")
	check(Slices.step([stored,{"null":true}],{},pool)==Slices.PROGRESS and pool.has([{"null":true}]) and pool[[{"null":true}]]==null,"null slot is a complete valid material entry")
	check(Slices.step([{"values":{"roughness":"invalid"}}],{},pool)==Slices.FAILED,"wrong stored property type fails")
	check(Slices.step([{"values":{"script":null}}],{},pool)==Slices.FAILED,"stored script injection fails")
	var invalid:=slot.duplicate(true);invalid.paint.texture_path="D:/outside_material_root.png"
	var textures_before:=Paint._textures.duplicate()
	check(Slices.step([invalid],{},pool)==Slices.FAILED and Paint._textures==textures_before,"out-of-root texture fails without resource publication")
	clear_caches();pool={}
	Slices.step([slot],{},pool);Paint._textures.clear()
	check(Slices.step([slot],{},pool)==Slices.PROGRESS and Paint._textures.size()==1 and pool.is_empty(),"eviction between turns recovers one complete texture")
	await scheduler_cases(record,cpu)
	clear_caches()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	for flip:bool in [false,true]:files.created.append(Pixels.cache_path(path,flip))
	for created:String in files.created:
		if FileAccess.file_exists(created):DirAccess.remove_absolute(created)
	DirAccess.remove_absolute(files.folder);files.free()
	print("MATERIAL_PUBLICATION passed=",passed," failures=",failed)
	quit(0 if failed==0 else 1)
func scheduler_cases(record:Dictionary,cpu:Dictionary)->void:
	var fixtures:=SchedulerFixture.new()
	# Fixture owns two admitted two-member groups plus an unready demand prefix.
	var f:Dictionary=fixtures.fixture(2,false,root);var service:Node=f.service;var doc:=Document.new();service._doc=doc
	var item:Dictionary=service._demanded_by_path["reference:building:0"][0]
	var selected_id:String=item.record.uuid
	item.record.house_prefab=record.house_prefab
	service._jobs[item.path].result={"prefab_cpu":{record.house_prefab.sha256:cpu}}
	clear_caches()
	for turn:int in 3:
		var timing:Dictionary=service._publish_ready(Time.get_ticks_usec()-1000000)
		check(timing.units==1 and doc.calls.is_empty() and int(service.profile.instances)==0,"exhausted frame budget advances one material unit without displaying partial group "+str(turn))
	service._publish_ready(Time.get_ticks_usec()-1000000)
	check(doc.calls.has(selected_id) and doc.calls.size()==1 and int(service.profile.instances)==0,"same component resumes after textures and stays staged until whole building ready")
	service._publish_ready(Time.get_ticks_usec()-1000000)
	check(int(service.profile.instances)==2,"second component publishes the whole building atomically")
	f.map.free()
	f=fixtures.fixture(2,false,root);service=f.service;doc=Document.new();service._doc=doc
	item=service._demanded_by_path["reference:building:0"][0];item.record.house_prefab=record.house_prefab
	service._jobs[item.path].result={"prefab_cpu":{record.house_prefab.sha256:cpu}}
	clear_caches();service._publish_ready(Time.get_ticks_usec()-1000000)
	var job:Dictionary=service._jobs[item.path]
	service._discard_job(item.path)
	check(not job.has("material_textures"),"cancel drops current material texture handoff before releasing its lease")
	check(not service._jobs.has(item.path) and service._admission.count()==1 and service._admission.reserved_bytes==1 and doc.calls.is_empty(),"cancel during material preparation releases admission without publishing components")
	check(not job.has("material_cursor") and doc.load_material_pool.is_empty() and Paint.prepared_images.is_empty(),"cancel leaves no partial material or CPU image handoff owner")
	check(Paint._textures.size()==1,"completed texture remains in the ordinary bounded reusable cache")
	f.map.free()
	f=fixtures.fixture(2,false,root);service=f.service;doc=Document.new();service._doc=doc
	item=service._demanded_by_path["reference:building:0"][1];item.record.house_prefab=record.house_prefab
	service._jobs[item.path].result={"prefab_cpu":{record.house_prefab.sha256:cpu}}
	clear_caches();service._publish_ready(Time.get_ticks_usec()-1000000)
	service._publish_ready(Time.get_ticks_usec()-1000000)
	check(service._publication_queues[item.path].scan==1 and int(service.profile.instances)==0,"wrapped ready scan retains exact final-member index after staged prefix")
	for turn:int in 3:service._publish_ready(Time.get_ticks_usec()-1000000)
	check(int(service.profile.instances)==2 and doc.calls.size()==2,"material work on final member completes the original atomic group")
	f.map.free()
	for grouped:bool in [false,true]:
		f=fixtures.fixture(2,false,root);service=f.service;doc=Document.new();service._doc=doc
		item=service._demanded_by_path["reference:building:0"][0]
		var missing:Dictionary=record.prefab_materials[0].duplicate(true);missing.texture_path=files.folder.path_join("missing.png")
		var broken:=bridge("missing",0,missing)
		item.record.house_prefab=broken.house_prefab
		if not grouped:item.group_id=""
		service._jobs[item.path].result={"prefab_cpu":{broken.house_prefab.sha256:Prefab.prepare_cpu(broken)}}
		clear_caches();service._publish_ready(Time.get_ticks_usec()-1000000)
		check(service.instance_errors.has(item.record.uuid) and doc.calls.is_empty() and int(service.profile.instances)==0,"missing texture fails safely before scene publication, grouped="+str(grouped))
		if grouped:
			service._publish_ready(Time.get_ticks_usec()-1000000)
			check(service.instance_errors.size()==2 and int(service.profile.instances)==0 and service._jobs[item.path].staged.is_empty(),"subsequent group completion propagates material failure and clears staging")
		f.map.free()
	fixtures.free()
