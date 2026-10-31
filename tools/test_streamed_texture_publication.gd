extends "res://tools/test_prefab_texture_preparation.gd"
## Return-load regression: real reference worker, scheduler and WorldDocument.
const SchedulerFixture=preload("res://tools/test_deferred_ready_progress.gd")
const TerrainFixture=preload("res://tools/test_terrain_load_preparation.gd")
const RoadFixture=preload("res://tools/test_native_road_preparation.gd")
const References=preload("res://tools/test_chunk_reference_preparation.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
class Document extends "res://scripts/world3d/world_document.gd":
	var calls:=0
	var calls_by_id:Dictionary={}
	var observed:Array=[]
	func _mesh(record:Dictionary,effects:bool=true,timings:Variant=null,prepared_context:RefCounted=null)->MeshInstance3D:
		calls+=1
		calls_by_id[record.uuid]=int(calls_by_id.get(record.uuid,0))+1
		var node:=super(record,effects,timings,prepared_context)
		if node.mesh!=null:
			for slot:int in node.mesh.get_surface_count():observed.append(node.mesh.surface_get_material(slot))
		observed.append(node.material_override)
		observed.append_array(node.get_meta(River.CPU_SURFACE_OVERRIDES_META,[]))
		return node

func clear_caches()->void:
	Prefab._meshes.clear();Prefab._render_meshes.clear();Paint.refresh_sources();River.cache.clear()

func declared(record:Dictionary)->Dictionary:
	var result:Dictionary={}
	for definition:Dictionary in Paint.definitions(record):
		for field:String in Paint.MAP_FIELDS:
			var path:String=definition.get(field,"")
			if path.is_empty():continue
			var flip:bool=field=="normal_path" and definition.get("normal_format","opengl")=="directx"
			result[Paint.texture_key(path,flip,field=="normal_path")]=[path,flip,field=="normal_path"]
	return result

func document()->Document:
	var doc:=Document.new();doc.load_immutable_records=true
	doc.load_box_meshes={};doc.load_material_pool={};doc.load_paint_validation={};doc.load_texture_checks={}
	return doc

func run()->void:
	if not check_gpu():quit(1);return
	var logger:=Errors.new();OS.add_logger(logger)
	files=Files.new();files.content_root=Prep.Paths.external_root();files.folder=Prep.Paths.cache_directory("streamed_texture_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var paths:Array[String]=[]
	for i:int in 4:
		var path:String=files.folder.path_join("texture_%d.png"%i);paths.append(path);files.created.append(path)
		var image:=Image.create(19,13,false,Image.FORMAT_RGBA8)
		for y:int in 13:
			for x:int in 19:image.set_pixel(x,y,Color(float((x+i)%7)/6.,float((y+i)%5)/4.,float((x+y+i)%9)/8.,1.))
		check(image.save_png(path)==OK,"save unique external texture "+str(i))
	var paint:Dictionary={"name":"streamed terrain","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":paths[0],"normal_path":paths[1],"normal_format":"directx","roughness_path":paths[2],"ao_path":paths[0],"height_path":paths[3]}
	var terrain_helper:=TerrainFixture.new();var terrain:Dictionary=terrain_helper.fixture("terrain",0);terrain_helper.free()
	terrain.collision="none";terrain.terrain_material=paint
	terrain.terrain_slope_blend={"rock_material":paint.duplicate(true),"steep_start":40.,"steep_end":65.}
	var road_helper:=RoadFixture.new();var road:Dictionary=road_helper.road()
	road.uuid="road";road.collision="none";road.road_mesh.kerbs=[road_helper.part(true,true)];road.road_kerb_material=paint.duplicate(true);road_helper.free()
	await publication_case(terrain,false)
	await publication_case(road,false)
	await publication_case(terrain,true)
	await cancellation_case(terrain)
	await cancellation_case(terrain,true)
	await shader_generation_case(terrain)
	await partial_packet_case(terrain)
	# A frozen building can also carry an additional painted face. The CPU
	# prefab's base materials alone are not its full texture dependency set.
	var painted:Dictionary=files.box("painted_prefab",0)
	var box:=BoxMesh.new();box.size=Vector3(2,2,2)
	var cpu:Mesh=Prefab.Cpu.capture(box)
	var data:Dictionary=Prefab.Cook.pack({[0]:{"mesh":cpu,"source":cpu}},"","house_prefab_v1");var bytes:=var_to_bytes(data)
	painted.collision="none";painted.house_prefab={"version":1,"sha256":Index.Store._sha(bytes),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))};painted.prefab_locked=true;painted.prefab_materials=[]
	painted.building={"id":"painted_fixture","part":"main/baked_0","role":"shell","floor":0,"floor_y":0.}
	var node:MeshInstance3D=document()._mesh(painted)
	var geometry:Dictionary=Paint.geometry(node);node.free()
	painted.surface_paint=[{"mesh":".","surface":0,"face":geometry.surfaces[0].faces.keys()[0],"geometry":geometry.surfaces[0].signature,"mapping":"planar","material":paint.duplicate(true),"scale":[1.,1.],"offset":[0.,0.],"rotation":0.}]
	await publication_case(painted,true)
	clear_caches();Paint.texture_profile_enabled=false
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	for path:String in paths:
		for flip:bool in [false,true]:files.created.append(Pixels.cache_path(path,flip))
	for created:String in files.created:
		if FileAccess.file_exists(created):DirAccess.remove_absolute(created)
	files.free()
	print("STREAMED_TEXTURE_PUBLICATION passed=",passed," failures=",failed)
	quit(0 if failed==0 else 1)

func partial_packet_case(record:Dictionary)->void:
	var expected:Dictionary=declared(record)
	var packet:Dictionary=await prepare_worker(expected,Prep.estimate(expected,files.content_root))
	var path:String=record.terrain_material.normal_path
	var omitted:String=path+"|normal|flip_y"
	# The source SHA alone is not admission for every variant of that path.
	var raw:Dictionary=await prepare_worker({path:[path,false,false]},Prep.estimate({path:[path,false,false]},files.content_root))
	packet.images[path]=raw.images[path]
	packet.images.erase(omitted)
	clear_caches();Paint.texture_profile_enabled=true;Pixels.reset_profile()
	var owners:Dictionary={};var state:Dictionary={};var phase:=1;var turns:=0
	while phase==1 and turns<10:
		phase=preload("res://scripts/world3d/material_publication.gd").step_record_prepared(record,{},owners,packet,state);turns+=1
	check(phase==0,"partial packet finishes admitted texture preparation")
	check(Paint.profile_snapshot().counters.get("paint.texture.runtime_image_lookup",0)==0,"partial packet never synchronously reads an unadmitted variant")
	check(not owners.has(omitted) and owners.size()==3,"partial packet pins only its exact admitted variants")
	var count:int=Paint.profile_snapshot().counters.get("paint.texture.unprepared_slice_skip",0)
	for repeat:int in 3:preload("res://scripts/world3d/material_publication.gd").step_record_prepared(record,{},owners,packet,state)
	check(count==1 and Paint.profile_snapshot().counters.get("paint.texture.unprepared_slice_skip",0)==1,"partial packet records the missing variant once across repeated slices")
	owners.clear();state.clear();packet.clear();clear_caches()

func publication_case(record:Dictionary,zero_budget:bool)->void:
	var label:String=record.uuid+(" zero LRU" if zero_budget else " return")
	var expected:Dictionary=declared(record)
	check(Prep.sources(record)==expected,label+" source catalogue covers all six texture roles and deduplicates shared paths")
	var metadata:Dictionary={}
	if record.has("building"):
		var blueprint=preload("res://scripts/world3d/building_blueprint.gd")
		metadata.building_instances={record.building.id:{"version":blueprint.VERSION,"parameters":blueprint.defaults(),"position":[0.,0.,0.],"yaw":0.,"baked":true,"parts":{record.building.part:record.uuid},"signatures":{record.building.part:blueprint.geometry_signature(record)}}}
	var stored:Dictionary=files.fixture(record.uuid+str(zero_budget),[record],metadata)
	check(not stored.is_empty(),label+" saved isolated native references")
	if stored.is_empty():return
	var index:Dictionary=Index.build(stored.path,files.content_root,[record])
	check(index.ok,label+" builds dependency index")
	if not index.ok:print(index);return
	var helper:=References.new();var entries:Array=helper.entries(index,[0]);helper.free()
	var plan:Dictionary=Prep.estimate(index.rows[0].prefab_textures,files.content_root)
	if plan.rows.is_empty():plan={}
	var worker:=Thread.new();worker.start(Chunk.prepare.bind(index,entries,stored.path,files.content_root,null,null,plan))
	while worker.is_alive():await process_frame
	var prepared:Dictionary=worker.wait_to_finish()
	check(prepared.error.is_empty() and (prepared.surface_arrays.has(record.uuid) or not prepared.get("prefab_cpu",{}).is_empty()),label+" real worker prepares CPU geometry")
	if not prepared.error.is_empty():print(prepared);return
	check(prepared.get("prefab_texture_packet",{}).get("images",{}).size()==expected.size(),label+" real worker prepares all declared unique pixels")
	# Also isolate publication from the catalogue bug: an explicitly supplied
	# correct worker packet must not be ignored by a non-prefab publisher.
	var forced:bool=prepared.get("prefab_texture_packet",{}).is_empty()
	if forced:prepared.prefab_texture_packet=await prepare_worker(expected,Prep.estimate(expected,files.content_root))
	var packet:Dictionary=prepared.prefab_texture_packet
	clear_caches()
	var control:=document();var control_queue:=Deferred.new();control_queue._doc=control;control_queue._accept_prepared_records(prepared);control_queue.free()
	var old:MeshInstance3D=control._mesh(record);old.free()
	var baseline:Array=control.observed;control=null
	# Actual return begins with absent hot/weak/material aliases, as after unload.
	clear_caches();var saved_budget:int=Paint.cache_byte_budget
	if zero_budget:Paint.cache_byte_budget=0
	Paint.texture_profile_enabled=true;Pixels.reset_profile()
	var fixtures:=SchedulerFixture.new();var f:Dictionary=fixtures.fixture(1,false,root)
	var queue:Node=f.service;var doc:=document();queue._doc=doc
	var item:Dictionary=queue._demanded_by_path["reference:building:0"][0]
	var current:Dictionary=record.duplicate(true);current.uuid=item.record.uuid
	item.record=current
	if prepared.surface_arrays.has(record.uuid):prepared.surface_arrays[current.uuid]=prepared.surface_arrays[record.uuid];prepared.surface_arrays.erase(record.uuid)
	if prepared.surface_bounds.has(record.uuid):prepared.surface_bounds[current.uuid]=prepared.surface_bounds[record.uuid];prepared.surface_bounds.erase(record.uuid)
	if prepared.get("terrain_contexts",{}).has(record.uuid):prepared.terrain_contexts[current.uuid]=prepared.terrain_contexts[record.uuid];prepared.terrain_contexts.erase(record.uuid)
	queue._accept_prepared_records(prepared)
	var job:Dictionary=queue._jobs[item.path];job.result=prepared
	var turns:=0;var max_uploads:=0
	while doc.calls==0 and turns<30:
		var before:int=Paint.profile_snapshot().counters.get("paint.texture.gpu_cache_miss",0)
		queue._publish_ready(Time.get_ticks_usec()-1000000);turns+=1
		var uploads:int=int(Paint.profile_snapshot().counters.get("paint.texture.gpu_cache_miss",0))-before
		max_uploads=maxi(max_uploads,uploads)
		check(Paint.prepared_images.is_empty(),label+" returns synchronous image scope after turn "+str(turns))
	var counters:Dictionary=Paint.profile_snapshot().counters
	print("STREAMED_CASE ",JSON.stringify({"label":label,"forced_packet":forced,"turns":turns,"max_uploads":max_uploads,"counters":counters}))
	check(doc.calls==1 and max_uploads<=1,label+" each publication turn uploads at most one texture before real WorldDocument construction")
	check(counters.get("paint.texture.runtime_image_lookup",0)==0,label+" prepared publication never falls back to synchronous pixel loading")
	check(counters.get("paint.texture.sidecar_main_reads",0)==0,label+" prepared publication never rereads DDS on the scene thread")
	check(counters.get("paint.texture.gpu_cache_miss",0)==expected.size(),label+" all unique texture variants upload exactly once including height")
	if not record.has("house_prefab"):check(doc.load_material_pool.is_empty(),label+" texture-only warmup does not create unused StandardMaterials")
	if record.has("terrain_mesh"):
		var shaders:Array=doc.observed.filter(func(value):return value is ShaderMaterial)
		check(not shaders.is_empty(),label+" real terrain retains its ShaderMaterial")
		if not shaders.is_empty():
			var shader:ShaderMaterial=shaders[0]
			var height:Texture2D=shader.get_shader_parameter("base_height")
			check(height!=null and canonical(height.get_image())==canonical(packet.images[record.terrain_material.height_path]),label+" height pixels and every mip survive zero hot-cache residency")
	check(not baseline.is_empty() and not doc.observed.is_empty(),label+" ordinary and sliced paths both produce actual materials")
	RenderingServer.force_sync()
	var expected_materials:Array=material_fingerprints(baseline);var actual_materials:Array=material_fingerprints(doc.observed)
	if expected_materials!=actual_materials:print("MATERIAL_DIFF ",label," ",JSON.stringify({"expected":expected_materials,"actual":actual_materials}))
	check(expected_materials==actual_materials,label+" every bound texture pixel, mip and material role matches the ordinary path")
	f.map.free();fixtures.free();baseline.clear();doc=null;prepared.clear();packet.clear();job.clear()
	Paint.cache_byte_budget=saved_budget;clear_caches();Drainer.synchronize_transfer()

func material_fingerprints(materials:Array)->Array:
	var result:Array=[]
	for material:Variant in materials:
		if material==null:result.append(null);continue
		var fields:Array=[]
		if material is StandardMaterial3D:fields=Paint.TEXTURE_PROPERTIES
		elif material is ShaderMaterial:
			for uniform:Dictionary in material.shader.get_shader_uniform_list():fields.append(str(uniform.name))
		var row:Dictionary={"kind":material.get_class(),"textures":{},"flags":{}}
		for field:String in fields:
			var value:Variant=material.get_shader_parameter(field) if material is ShaderMaterial else material.get(field)
			if value is Texture2D:
				var image:Image=value.get_image()
				row.textures[field]={"width":image.get_width(),"height":image.get_height(),"mips":image.has_mipmaps(),"sha":Pixels.Envelope.checksum(canonical(image)).hex_encode(),"normal_xy":value.get_meta("runtime_normal_xy",false)}
			elif value is bool:row.flags[field]=value
		result.append(row)
	return result

func cancellation_case(record:Dictionary,fail_scope:bool=false)->void:
	var requested:Dictionary=declared(record);var packet:Dictionary=await prepare_worker(requested,Prep.estimate(requested,files.content_root))
	clear_caches();var old_budget:int=Paint.cache_byte_budget;Paint.cache_byte_budget=0
	var fixtures:=SchedulerFixture.new();var f:Dictionary=fixtures.fixture(1,false,root);var queue:Node=f.service;var doc:=document();queue._doc=doc
	var item:Dictionary=queue._demanded_by_path["reference:building:0"][0]
	var current:Dictionary=record.duplicate(true);current.uuid=item.record.uuid;item.record=current
	var job:Dictionary=queue._jobs[item.path];job.result={"prefab_texture_packet":packet}
	var cpu_owner:WeakRef=weakref(packet.images.values()[0]);queue._publish_ready(Time.get_ticks_usec()-1000000)
	check(doc.calls==0 and job.get("streamed_texture_owners",{}).size()==1 and Paint._textures.is_empty(),"cancel fixture owns one complete texture despite a zero hot-cache budget")
	var gpu_owner:WeakRef=weakref(job.streamed_texture_owners.values()[0]) if not job.get("streamed_texture_owners",{}).is_empty() else null
	if fail_scope:
		var key:String=job.streamed_texture_owners.keys()[0]
		packet.resident_textures={key:{"texture":job.streamed_texture_owners[key],"source_sha":"f".repeat(64)}}
		var previous:Dictionary=Paint.prepared_images
		queue._publish_ready(Time.get_ticks_usec()-1000000)
		check(queue.instance_errors.has(current.uuid) and doc.calls==0 and is_same(Paint.prepared_images,previous),"invalid packet fails before record construction and restores the exact earlier image scope")
	queue._discard_job(item.path)
	check(not job.has("streamed_texture_owners") and not job.has("streamed_texture_scope") and Paint.prepared_images.is_empty(),"cancel drops record texture owners and restores the synchronous handoff")
	check(doc.calls==0 and doc.load_material_pool.is_empty() and queue._admission.reserved_bytes==1,"cancel never constructs a record and releases exactly its existing admission lease")
	check(cpu_owner.get_ref()==null and gpu_owner!=null and gpu_owner.get_ref()==null,"cancel releases actual CPU/GPU owners with no hidden strong cache")
	f.map.free();fixtures.free();packet.clear();job.clear();Paint.cache_byte_budget=old_budget;clear_caches()

func shader_generation_case(record:Dictionary)->void:
	var stored:Dictionary=files.fixture("shader_generation",[record])
	var index:Dictionary=Index.build(stored.path,files.content_root,[record])
	var helper:=References.new();var entries:Array=helper.entries(index,[0]);helper.free()
	var plan:Dictionary=Prep.estimate(index.rows[0].prefab_textures,files.content_root)
	var worker:=Thread.new();worker.start(Chunk.prepare.bind(index,entries,stored.path,files.content_root,null,null,plan))
	while worker.is_alive():await process_frame
	var prepared:Dictionary=worker.wait_to_finish();var packet:Dictionary=prepared.prefab_texture_packet
	check(prepared.error.is_empty() and prepared.surface_arrays.has(record.uuid),"generation fixture has actual worker geometry")
	clear_caches()
	var fixtures:=SchedulerFixture.new();var f:Dictionary=fixtures.fixture(1,false,root);var queue:Node=f.service;var doc:=document();queue._doc=doc
	var item:Dictionary=queue._demanded_by_path["reference:building:0"][0]
	var current:Dictionary=record.duplicate(true);current.uuid=item.record.uuid;item.record=current
	prepared.surface_arrays[current.uuid]=prepared.surface_arrays[record.uuid];prepared.surface_arrays.erase(record.uuid)
	prepared.surface_bounds[current.uuid]=prepared.surface_bounds[record.uuid];prepared.surface_bounds.erase(record.uuid)
	if prepared.get("terrain_contexts",{}).has(record.uuid):prepared.terrain_contexts[current.uuid]=prepared.terrain_contexts[record.uuid];prepared.terrain_contexts.erase(record.uuid)
	queue._accept_prepared_records(prepared)
	var job:Dictionary=queue._jobs[item.path];job.result=prepared
	queue._publish_ready(Time.get_ticks_usec()-1000000)
	check(doc.calls==0 and job.get("streamed_texture_owners",{}).size()==1,"generation A has begun sliced publication")
	var path:String=record.terrain_material.texture_path;var original:=FileAccess.get_file_as_bytes(path)
	var changed:=Image.create(19,13,false,Image.FORMAT_RGBA8);changed.fill(Color(.1,.9,.2,1.));changed.save_png(path)
	Paint.refresh_sources();var other:ShaderMaterial=River.terrain(record)
	var b_texture:Texture2D=other.get_shader_parameter("base_albedo");var b_pixels:=canonical(b_texture.get_image())
	check(b_texture.get_meta("runtime_source_sha256","")!=packet.sources[path],"interleaved actual shader retains generation B")
	files.write_bytes(path,original)
	var unrelated_record:Dictionary=record.duplicate(true);var plain:Dictionary={"name":"unrelated shader","color":[.4,.3,.2,1.],"roughness":.6}
	unrelated_record.terrain_material=plain;unrelated_record.terrain_slope_blend.rock_material=plain
	var unrelated:ShaderMaterial=River.terrain(unrelated_record)
	Paint._textures.clear();Paint._texture_refs.clear();Paint._materials.clear();Paint._material_refs.clear()
	check(River.cache.values().has(other) and Paint._texture_refs.is_empty(),"shader cache still owns B after both texture catalogues are cleared")
	var turns:=0
	while not doc.calls_by_id.has(current.uuid) and turns<15:queue._publish_ready(Time.get_ticks_usec()-1000000);turns+=1
	var shaders:Array=doc.observed.filter(func(value):return value is ShaderMaterial)
	print("SHADER_GENERATION ",JSON.stringify({"calls":doc.calls_by_id,"shaders":shaders.size(),"errors":queue.instance_errors,"owners":job.get("streamed_texture_owners",{}).size(),"turns":turns}))
	check(doc.calls_by_id.get(current.uuid,0)==1 and not shaders.is_empty(),"generation A reaches real WorldDocument shader binding")
	if not shaders.is_empty():
		var actual:Texture2D=shaders[0].get_shader_parameter("base_albedo")
		check(actual.get_meta("runtime_source_sha256","")==packet.sources[path] and canonical(actual.get_image())==canonical(packet.images[path]),"target shader cache cannot substitute B for the prepared A generation")
	check(canonical(b_texture.get_image())==b_pixels and other.get_shader_parameter("base_albedo")==b_texture,"already published generation B remains immutable")
	check(River.cache.values().has(unrelated),"target generation replacement preserves unrelated shader cache entries")
	f.map.free();fixtures.free();packet.clear();job.clear();clear_caches()
