extends "res://tools/test_prefab_texture_preparation.gd"
## Real private-renderer regression: worker pixels must not bypass publication slices.
const SchedulerFixture=preload("res://tools/test_deferred_ready_progress.gd")
const MaterialFixture=preload("res://tools/test_material_publication.gd")
const Slices=preload("res://scripts/world3d/material_publication.gd")

func clear_caches()->void:
	Prefab._meshes.clear();Prefab._render_meshes.clear();Paint.refresh_sources()

func run()->void:
	if not check_gpu():quit(1);return
	var logger:=Errors.new();OS.add_logger(logger)
	files=Files.new();files.content_root=Prep.Paths.external_root();files.folder=Prep.Paths.cache_directory("prepared_material_slices_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var paths:Array[String]=[]
	for i:int in 3:
		var path:String=files.folder.path_join("pixels_%d.png"%i);paths.append(path);files.created.append(path)
		var image:=Image.create(19,13,false,Image.FORMAT_RGBA8)
		for y:int in 13:
			for x:int in 19:image.set_pixel(x,y,Color(float((x+i)%7)/6.,float((y+i)%5)/4.,float((x+y+i)%9)/8.,.4 if x<4 else 1.))
		check(image.save_png(path)==OK,"save independent texture %d"%i)
	var paint:Dictionary={"name":"prepared slices","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":paths[0],"normal_path":paths[1],"normal_format":"directx","roughness_path":paths[2],"ao_path":paths[0]}
	var record:=bridge("prepared slices",0,paint)
	var requested:=Prep.sources(record);var plan:=Prep.estimate(requested,files.content_root)
	var packet:=await prepare_worker(requested,plan)
	check(packet.error.is_empty() and packet.images.size()==3,"worker returns three independent complete CPU images")
	var cpu:=Prefab.prepare_cpu(record)
	check(not cpu.is_empty(),"prepare real prefab geometry")
	clear_caches();Paint.texture_profile_enabled=true;Pixels.reset_profile()
	var fixtures:=SchedulerFixture.new();var f:Dictionary=fixtures.fixture(2,false,root)
	var service:Node=f.service;var doc:=MaterialFixture.Document.new();service._doc=doc
	var item:Dictionary=service._demanded_by_path["reference:building:0"][0]
	item.record.house_prefab=record.house_prefab
	var job:Dictionary=service._jobs[item.path]
	job.result={"prefab_cpu":{record.house_prefab.sha256:cpu},"prefab_texture_packet":packet}
	var charge:int=service._admission.reserved_bytes
	var timing:Dictionary=service._publish_ready(Time.get_ticks_usec()-1000000)
	var measured:Dictionary=Paint.profile_snapshot()
	var uploads:int=measured.counters.get("paint.texture.gpu_cache_miss",0)
	print("PREPARED_FIRST_TURN ",JSON.stringify({"uploads":uploads,"units":timing.units,"nodes":doc.calls.size(),"material_units":service.profile.get("material_preparation_units",0),"admitted_bytes":service._admission.reserved_bytes}))
	check(timing.units==1 and uploads==1,"expired budget permits one prepared texture upload, not the whole material")
	check(doc.calls.is_empty() and doc.load_material_pool.is_empty(),"prepared upload turn neither instantiates a component nor completes its material")
	check(int(service.profile.get("material_preparation_units",0))==1,"prepared pixel path participates in material publication units")
	check(Paint.prepared_images.is_empty() and packet.images.size()==3 and service._admission.reserved_bytes==charge,"temporary global image scope ends while the admitted packet retains CPU owners")
	var unrelated:=Paint.make_material({"name":"unrelated scope sentinel","color":[1.,1.,1.,1.],"roughness":.7})
	var turns:=1
	while doc.calls.is_empty() and turns<10:
		var before:int=Paint.profile_snapshot().counters.get("paint.texture.gpu_cache_miss",0)
		service._publish_ready(Time.get_ticks_usec()-1000000);turns+=1
		var after:int=Paint.profile_snapshot().counters.get("paint.texture.gpu_cache_miss",0)
		check(after-before<=1 and Paint.prepared_images.is_empty(),"each resumed prepared slice performs at most one upload and closes its image scope")
		check(Paint._materials.values().has(unrelated),"missing future uploads do not clear another material between slices")
	check(doc.calls.size()==1 and turns==5,"three texture turns and one material turn precede component instantiation")
	check(job.material_scope.initializations==1 and job.material_scope.reuses==4,"five scheduler turns include final publication without reopening its completed synchronous scope")
	var prior_images:Dictionary=Paint.prepared_images
	check(Prefab.publish_prepared(record,cpu,{},doc.load_material_pool,{},packet,job.material_scope) and job.material_scope.initializations==1 and job.material_scope.reuses==5 and is_same(Paint.prepared_images,prior_images),"a separate later publication checks once again and restores the exact previous image owner")
	check(Paint.profile_snapshot().counters.get("paint.texture.gpu_cache_miss",0)==3 and Paint.profile_snapshot().counters.get("paint.texture.runtime_image_lookup",0)==0,"all unique textures upload once from worker pixels without source decode fallback")
	var slot:Dictionary=cpu.data.materials[0]
	var material:StandardMaterial3D=doc.load_material_pool.get([slot])
	check(material!=null,"completed sliced material is retained in the normal caller pool")
	if material!=null:
		RenderingServer.force_sync()
		for field:String in ["albedo_texture","normal_texture","roughness_texture"]:
			var key:String=paths[["albedo_texture","normal_texture","roughness_texture"].find(field)]+("|normal|flip_y" if field=="normal_texture" else "")
			check(canonical(material.get(field).get_image())==canonical(packet.images[key]),field+" matches exact prepared pixels and mips")
		check(material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA and material.ao_texture==material.albedo_texture,"alpha semantics and repeated slot texture identity survive slicing")
		var tickets:=Prefab.texture_tickets(plan.rows,doc.load_material_pool)
		var resident_packet:Dictionary={"images":{},"sources":packet.sources.duplicate(),"resident_textures":tickets}
		var original_images:Dictionary=Paint.prepared_images
		var temporary_tickets:Dictionary={}
		check(Slices.step_prepared(record,cpu.data.materials,{},doc.load_material_pool,temporary_tickets,resident_packet)==Slices.READY and is_same(Paint.prepared_images,original_images),"resident ticket/cache hit performs no new material work and restores the caller scope")
		resident_packet.sources[paths[0]]="f".repeat(64)
		temporary_tickets.stale=material.albedo_texture
		check(Slices.step_prepared(record,cpu.data.materials,{},doc.load_material_pool,temporary_tickets,resident_packet)==Slices.FAILED and temporary_tickets.is_empty() and is_same(Paint.prepared_images,original_images),"invalid resident proof fails before installation and releases material handoff")
		resident_packet.clear();tickets.clear()
	transaction_case(record,cpu,doc.load_material_pool,packet)
	f.map.free();fixtures.free();packet.clear();cpu.clear();job.clear();clear_caches();Drainer.synchronize_transfer()
	material=null;doc=null
	await cancellation_case(record,requested,plan)
	await failure_case(paint,requested,plan)
	await final_geometry_failure_retry_case(record,requested,plan)
	await zero_budget_case(record,requested,plan)
	await generation_case(record,requested,plan)
	await resident_generation_case(record,requested,plan)
	await direct_scheduler_generation_case(record,requested,plan)
	Paint.texture_profile_enabled=false
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	for key:String in requested:files.created.append(Pixels.cache_path(requested[key][0],requested[key][1]))
	for created:String in files.created:
		if FileAccess.file_exists(created):DirAccess.remove_absolute(created)
	DirAccess.remove_absolute(files.folder);files.free()
	print("PREPARED_MATERIAL_PUBLICATION passed=",passed," failures=",failed)
	quit(0 if failed==0 else 1)

func cancellation_case(record:Dictionary,requested:Dictionary,plan:Dictionary)->void:
	var packet:=await prepare_worker(requested,plan);var cpu:=Prefab.prepare_cpu(record)
	clear_caches();var fixtures:=SchedulerFixture.new();var f:Dictionary=fixtures.fixture(2,false,root)
	var service:Node=f.service;var doc:=MaterialFixture.Document.new();service._doc=doc
	var item:Dictionary=service._demanded_by_path["reference:building:0"][0];item.record.house_prefab=record.house_prefab
	var job:Dictionary=service._jobs[item.path];job.result={"prefab_cpu":{record.house_prefab.sha256:cpu},"prefab_texture_packet":packet}
	var cpu_owner:WeakRef=weakref(packet.images.values()[0]);var gpu_owner:WeakRef
	service._publish_ready(Time.get_ticks_usec()-1000000)
	if not job.get("material_textures",{}).is_empty():gpu_owner=weakref(job.material_textures.values()[0])
	service._discard_job(item.path)
	check(packet.is_empty() and cpu_owner.get_ref()==null and not job.has("material_textures") and not job.has("material_scope"),"cancel between prepared slices clears packet aliases, CPU pixels, texture tickets and scope metadata")
	check(not service._jobs.has(item.path) and service._admission.reserved_bytes==1 and doc.calls.is_empty() and Paint.prepared_images.is_empty(),"cancel releases the job lease without publishing a partial component or global image owner")
	clear_caches();Drainer.synchronize_transfer()
	check(gpu_owner!=null and gpu_owner.get_ref()==null,"cancelled slice GPU texture releases after ordinary cache owners retire")
	f.map.free();fixtures.free();job.clear();cpu.clear()

func failure_case(paint:Dictionary,requested:Dictionary,plan:Dictionary)->void:
	var packet:=await prepare_worker(requested,plan)
	var broken:Dictionary=paint.duplicate(true);broken.texture_path="D:/outside_prepared_material_root.png"
	var record:=bridge("prepared failure",0,broken);var cpu:=Prefab.prepare_cpu(record)
	clear_caches();var fixtures:=SchedulerFixture.new();var f:Dictionary=fixtures.fixture(2,false,root)
	var service:Node=f.service;var doc:=MaterialFixture.Document.new();service._doc=doc
	var item:Dictionary=service._demanded_by_path["reference:building:0"][0];item.record.house_prefab=record.house_prefab
	var job:Dictionary=service._jobs[item.path];job.result={"prefab_cpu":{record.house_prefab.sha256:cpu},"prefab_texture_packet":packet}
	service._publish_ready(Time.get_ticks_usec()-1000000)
	check(service.instance_errors.has(item.record.uuid) and doc.calls.is_empty() and job.get("material_textures",{}).is_empty() and Paint.prepared_images.is_empty(),"failed prepared material closes its image scope and clears tickets without instantiation")
	service._discard_job(item.path)
	check(packet.is_empty() and service._admission.reserved_bytes==1,"failed prepared job releases packet and its admission lease")
	f.map.free();fixtures.free();job.clear();cpu.clear();clear_caches()

func final_geometry_failure_retry_case(record:Dictionary,requested:Dictionary,plan:Dictionary)->void:
	# Reach the scheduler's combined READY branch with a structurally admissible
	# packet whose geometry restore returns no entry. The first sibling is staged
	# already: failure of the final sibling must abort the whole group and retire
	# its admission, and an ordinary retry must construct the group again.
	var packet:=await prepare_worker(requested,plan);var cpu:=Prefab.prepare_cpu(record)
	var broken:Dictionary=cpu.duplicate(true);broken.data.entries=[]
	clear_caches();var fixtures:=SchedulerFixture.new();var f:Dictionary=fixtures.fixture(2,false,root)
	var service:Node=f.service;var doc:=MaterialFixture.Document.new();service._doc=doc
	var items:Array=service._demanded_by_path["reference:building:0"]
	var first_id:String=items[0].record.uuid;var last_id:String=items[1].record.uuid;var path:String=items[0].path
	items[1].record.house_prefab=record.house_prefab
	var job:Dictionary=service._jobs[path]
	job.result={"prefab_cpu":{record.house_prefab.sha256:broken},"prefab_texture_packet":packet}
	service._publish_ready(Time.get_ticks_usec()-1000000)
	check(job.get("staged",{}).has(first_id) and int(service.profile.instances)==0,"final failure fixture stages a healthy first sibling without partial publication")
	for turn:int in 12:
		if service.instance_errors.has(last_id):break
		service._publish_ready(Time.get_ticks_usec()-1000000)
	print("FINAL_GEOMETRY_FAILURE ",JSON.stringify({"reason":service.instance_errors.get(last_id,""),"material_ready":doc.load_material_pool.has([cpu.data.materials[0]]),"material_units":service.profile.get("material_preparation_units",0),"scope":job.get("material_scope",{})}))
	check(doc.load_material_pool.has([cpu.data.materials[0]]) and int(service.profile.get("material_preparation_units",0))>=5 and int(job.get("material_scope",{}).get("reuses",0))>=4,"failure reaches the combined final geometry branch after complete sliced materials")
	check(service.instance_errors.has(first_id) and service.instance_errors.has(last_id) and job.get("staged",{}).is_empty() and int(service.profile.instances)==0,"combined final geometry failure aborts the entire staged building")
	check(not Prefab._meshes.has(record.house_prefab.sha256) and Paint.prepared_images.is_empty() and Paint.prepared_textures.is_empty(),"failed final publication leaves neither prefab nor borrowed texture scope")
	for turn:int in 4:
		if not service._jobs.has(path):break
		service._process(0)
	check(not service._jobs.has(path) and packet.is_empty() and service._admission.reserved_bytes<=1,"failed building releases its image packet and admission through normal service cleanup")
	var replacement:=await prepare_worker(requested,plan)
	service.retry_failed(AABB(Vector3(-1,-1,-1),Vector3(12000,2,2)));service.set_process(false);service._refresh_demanded()
	check(not service.instance_errors.has(first_id) and not service.instance_errors.has(last_id),"ordinary retry clears both failed sibling records")
	service._admission.worker_limit=2
	service._admission.reserve(path,{"estimated_bytes":1,"exclusive":false})
	service._jobs[path]={"accepted":true,"result":{"prefab_cpu":{record.house_prefab.sha256:cpu},"prefab_texture_packet":replacement},"token":Deferred.Drainer.CancelToken.new(),"publication_ids":[first_id,last_id]}
	service._prepared_paths[path]=true;service._admission.worker_limit=0
	for turn:int in 20:
		if not service._pending_by_record_id.has(first_id) and not service._pending_by_record_id.has(last_id):break
		service._publish_ready(Time.get_ticks_usec()-1000000)
	check(not service._pending_by_record_id.has(first_id) and not service._pending_by_record_id.has(last_id) and doc.calls.get(first_id,0)==2 and doc.calls.get(last_id,0)==1,"valid retry reconstructs both siblings and publishes the group atomically")
	service._process(0)
	check(not service._jobs.has(path) and service._admission.reserved_bytes<=1,"successful retry retires its accepted job and reservation")
	f.map.free();fixtures.free();job.clear();cpu.clear();broken.clear();clear_caches();Drainer.synchronize_transfer()

func zero_budget_case(record:Dictionary,requested:Dictionary,plan:Dictionary)->void:
	var packet:=await prepare_worker(requested,plan);var cpu:=Prefab.prepare_cpu(record)
	clear_caches();Pixels.reset_profile();var old_budget:int=Paint.cache_byte_budget;Paint.cache_byte_budget=0
	var pool:Dictionary={};var tickets:Dictionary={};var state:Dictionary={};var turns:=0;var phase:=Slices.PROGRESS
	var slot:Dictionary=cpu.data.materials[0]
	while phase==Slices.PROGRESS and turns<10:
		phase=Slices.step_and_publish_prepared(record,cpu,{},pool,tickets,packet,state);turns+=1
		check(Paint.prepared_images.is_empty(),"zero-budget prepared slice restores image scope")
	check(phase==Slices.READY and turns==5 and pool.has([slot]) and tickets.is_empty(),"zero hot-cache budget still completes three prepared texture slices and a whole material")
	check(Paint.profile_snapshot().counters.get("paint.texture.gpu_cache_miss",0)==3,"zero-budget retries reuse job tickets instead of uploading the same texture repeatedly")
	check(state.initializations==1 and state.reuses==4,"zero-budget eviction does not become repeated source invalidation")
	check(Prefab._meshes.has(record.house_prefab.sha256) and Prefab._meshes[record.house_prefab.sha256].mesh.materials[0]==pool[[slot]],"zero-budget final transaction publishes the same complete material owner")
	Paint.cache_byte_budget=old_budget;pool.clear();packet.clear();cpu.clear();clear_caches();Drainer.synchronize_transfer()

func generation_case(record:Dictionary,requested:Dictionary,plan:Dictionary)->void:
	var packet:=await prepare_worker(requested,plan);var cpu:=Prefab.prepare_cpu(record)
	clear_caches();var pool:Dictionary={};var tickets:Dictionary={};var state:Dictionary={}
	check(Slices.step_and_publish_prepared(record,cpu,{},pool,tickets,packet,state)==Slices.PROGRESS,"old immutable generation starts one sliced upload")
	var path:String=record.prefab_materials[0].texture_path;var original:=FileAccess.get_file_as_bytes(path)
	var replacement:=Image.create(19,13,false,Image.FORMAT_RGBA8);replacement.fill(Color.BLUE)
	check(replacement.save_png(path)==OK,"replace only the temporary fixture source between slices")
	var fresh:=await prepare_worker(requested,Prep.estimate(requested,files.content_root))
	check(Prefab.publish_prepared(record,cpu,{},pool,{},fresh),"another owner publishes the replacement material and prefab generation")
	var newer_material:StandardMaterial3D=pool[[cpu.data.materials[0]]];var newer:Texture2D=newer_material.albedo_texture
	check(newer!=null and newer.get_meta("runtime_source_sha256")==fresh.sources[path],"another publication installs a genuinely different source generation")
	Paint._textures.clear();Paint._texture_refs.clear()
	files.write_bytes(path,original)
	var phase:=Slices.PROGRESS;var turns:=0
	while phase==Slices.PROGRESS and turns<8:
		phase=Slices.step_and_publish_prepared(record,cpu,{},pool,tickets,packet,state);turns+=1
	check(phase==Slices.READY and state.initializations==2,"interleaved replacement re-enters invalidation even after hot and weak texture catalogues are cleared")
	var slot:Dictionary=cpu.data.materials[0];var material:StandardMaterial3D=pool.get([slot])
	check(material!=null and material.albedo_texture.get_meta("runtime_source_sha256")==packet.sources[path] and material.albedo_texture!=newer,"resumed packet cannot consume a newer incompatible material generation")
	if material!=null and newer!=null:
		RenderingServer.force_sync()
		check(canonical(material.albedo_texture.get_image())==canonical(packet.images[path]) and canonical(newer.get_image())==canonical(fresh.images[path]),"both live texture generations preserve their exact original pixels")
	pool.clear();packet.clear();fresh.clear();cpu.clear();tickets.clear();state.clear();clear_caches();Drainer.synchronize_transfer()

func direct_scheduler_generation_case(record:Dictionary,requested:Dictionary,plan:Dictionary)->void:
	# Exercise actual scheduler slices and the direct projection after another
	# consumer replaces this source, then exercise both direct and node routes
	# through the record scope while an old streamed owner remains in the job.
	var packet:=await prepare_worker(requested,plan);var cpu:=Prefab.prepare_cpu(record)
	clear_caches()
	var policy=preload("res://scripts/world3d/runtime_package_policy.gd")
	var previous_policy:bool=policy.verify_packages;policy.verify_packages=false
	var fixture_owner:=SchedulerFixture.new();var f:Dictionary=fixture_owner.fixture(2,false,root)
	var service:Node=f.service;var doc=preload("res://scripts/world3d/world_document.gd").new()
	doc.load_immutable_records=true;doc.load_paint_validation={};doc.load_material_pool={};doc.load_texture_checks={};service._doc=doc
	var item:Dictionary=service._demanded_by_path["reference:building:0"][0];var uuid:String=item.record.uuid
	item.record.merge(record,true);item.record.uuid=uuid;item.record.kind="box"
	var job:Dictionary=service._jobs[item.path]
	job.result={"prefab_cpu":{record.house_prefab.sha256:cpu},"prefab_texture_packet":packet}
	service._publish_ready(Time.get_ticks_usec()-1000000)
	check(job.get("material_textures",{}).size()==1 and not job.get("staged",{}).has(uuid),"real scheduler holds its first sliced texture before direct projection")
	var path:String=record.prefab_materials[0].texture_path;var original:=FileAccess.get_file_as_bytes(path)
	var replacement:=Image.create(19,13,false,Image.FORMAT_RGBA8);replacement.fill(Color.BLUE)
	check(replacement.save_png(path)==OK,"replace only external test source while scheduler is between slices")
	var fresh:=await prepare_worker(requested,Prep.estimate(requested,files.content_root))
	check(Prefab.publish_prepared(item.record,cpu,{},doc.load_material_pool,{},fresh),"other consumer installs a different live prefab generation")
	var newer:Texture2D=doc.load_material_pool[[cpu.data.materials[0]]].albedo_texture
	Paint._textures.clear();Paint._texture_refs.clear();files.write_bytes(path,original)
	for turn:int in 12:
		if job.get("staged",{}).has(uuid):break
		service._publish_ready(Time.get_ticks_usec()-1000000)
	var staged:Dictionary=job.get("staged",{}).get(uuid,{})
	check(int(service.profile.get("native_prefab_direct_instances",0))==1 and staged.get("specs",[]).size()==1,"resumed real textured job reaches the direct scheduler route once")
	var material:StandardMaterial3D=Prefab._meshes[record.house_prefab.sha256].mesh.materials[0]
	check(material.albedo_texture!=newer and material.albedo_texture.get_meta("runtime_source_sha256")==packet.sources[path] and staged.specs[0].mesh==Prefab._meshes[record.house_prefab.sha256].mesh,"direct spec binds the resumed source generation and final canonical owner")
	RenderingServer.force_sync()
	check(canonical(material.albedo_texture.get_image())==canonical(packet.images[path]),"resumed direct source retains exact GPU pixels")
	var old_texture:Texture2D=material.albedo_texture
	f.map.free();fixture_owner.free()
	var old_direct:bool=Deferred.native_prefab_direct_specs_enabled
	for direct:bool in [true,false]:
		Deferred.native_prefab_direct_specs_enabled=direct
		fixture_owner=SchedulerFixture.new();f=fixture_owner.fixture(2,false,root);service=f.service;service._doc=doc
		item=service._demanded_by_path["reference:building:0"][0];uuid=item.record.uuid
		item.record.merge(record,true);item.record.uuid=uuid;item.record.kind="box"
		# Job retirement owns and clears packet dictionaries. Each case transfers
		# independent containers while retaining the same immutable pixel owners.
		job=service._jobs[item.path];job.result={"prefab_cpu":{record.house_prefab.sha256:cpu.duplicate(true)},"prefab_texture_packet":fresh.duplicate(true)}
		job.streamed_texture_owners={path:old_texture};job.streamed_texture_scope={}
		for turn:int in 12:
			if job.get("staged",{}).has(uuid):break
			service._publish_ready(Time.get_ticks_usec()-1000000)
		staged=job.get("staged",{}).get(uuid,{})
		check(int(service.profile.get("native_prefab_direct_instances",0))==int(direct) and staged.get("specs",[]).size()==1,"streamed record scope retains exactly one instance through direct="+str(direct))
		material=Prefab._meshes[record.house_prefab.sha256].mesh.materials[0]
		check(material.albedo_texture!=old_texture and material.albedo_texture.get_meta("runtime_source_sha256")==fresh.sources[path] and staged.specs[0].mesh==Prefab._meshes[record.house_prefab.sha256].mesh,"both routes reject the stale streamed owner and reacquire the replacement prefab")
		RenderingServer.force_sync()
		check(canonical(material.albedo_texture.get_image())==canonical(fresh.images[path]),"replacement keeps exact GPU pixels through direct="+str(direct))
		var invalid:Dictionary={"sources":fresh.sources,"resident_textures":{"bad":{"texture":null,"source_sha":"f".repeat(64)}}}
		var rejected:Dictionary=service._begin_record_texture_scope(item,{"result":{"prefab_texture_packet":invalid},"streamed_texture_owners":{path:old_texture},"streamed_texture_scope":{}})
		check(not rejected.ok and Paint.prepared_images.is_empty() and Paint.prepared_textures.is_empty(),"record scope rejects an invalid resident ticket without leaking a borrowed owner")
		f.map.free();fixture_owner.free()
	Deferred.native_prefab_direct_specs_enabled=old_direct;policy.verify_packages=previous_policy
	packet.clear();fresh.clear();cpu.clear();clear_caches();Drainer.synchronize_transfer()

func transaction_case(record:Dictionary,cpu:Dictionary,pool:Dictionary,packet:Dictionary)->void:
	# A synchronous READY hit used to open and restore the exact same scope twice.
	# Fixed work and nested sentinels make this independent of frame scheduling.
	var old_images:Dictionary=Paint.prepared_images;var old_uploaded:Dictionary=Paint.prepared_textures
	var sentinel:={"outer":Image.create(1,1,false,Image.FORMAT_RGBA8)}
	var uploaded:={"outer":pool.values()[0].albedo_texture}
	Paint.prepared_images=sentinel;Paint.prepared_textures=uploaded
	var owner:Dictionary=Prefab._meshes[record.house_prefab.sha256]
	var rows:Array=[]
	for combined:bool in [false,true,true,false]:
		var state:Dictionary={};var tickets:Dictionary={};var ok:=true;var began:=Time.get_ticks_usec()
		for i:int in 1000:
			if combined:ok=ok and Slices.step_and_publish_prepared(record,cpu,{},pool,tickets,packet,state)==Slices.READY
			else:
				ok=ok and Slices.step_prepared(record,cpu.data.materials,{},pool,tickets,packet,state)==Slices.READY
				ok=ok and Prefab.publish_prepared(record,cpu,{},pool,{},packet,state)
		rows.append({"combined":combined,"calls":1000,"elapsed_us":Time.get_ticks_usec()-began,"scope_entries":int(state.initializations)+int(state.reuses)})
		check(ok and rows.back().scope_entries==(1000 if combined else 2000),"fixed publication work enters one scope instead of two, combined="+str(combined))
		check(is_same(Prefab._meshes[record.house_prefab.sha256],owner) and is_same(Paint.prepared_images,sentinel) and is_same(Paint.prepared_textures,uploaded) and tickets.is_empty(),"each path preserves exact mesh/material identity and restores both outer handoff owners")
	var rejected:Dictionary={"sources":{files.folder.path_join("missing.png"):"a".repeat(64)},"resident_textures":{"bad":{"texture":null,"source_sha":"a".repeat(64)}}}
	var held:Dictionary={"old":uploaded.outer}
	check(Slices.step_and_publish_prepared(record,cpu,{},pool,held,rejected,{})==Slices.FAILED and held.is_empty() and is_same(Paint.prepared_images,sentinel) and is_same(Paint.prepared_textures,uploaded),"failed resident gate clears private tickets without modifying outer scopes")
	Prefab._meshes.clear();Prefab._render_meshes.clear()
	var broken:Dictionary=cpu.duplicate();broken.sha256="f".repeat(64)
	check(Slices.step_and_publish_prepared(record,broken,{},pool,{},packet,{})==Slices.FAILED and not Prefab._meshes.has(record.house_prefab.sha256) and is_same(Paint.prepared_images,sentinel) and is_same(Paint.prepared_textures,uploaded),"final geometry failure also closes the combined scope without installing a prefab")
	check(Slices.step_and_publish_prepared(record,cpu,{},pool,{},packet,{})==Slices.READY,"a later valid transaction publishes normally after failure")
	Paint.prepared_images=old_images;Paint.prepared_textures=old_uploaded
	print("MATERIAL_SCOPE_TRANSACTION ",JSON.stringify(rows))

func resident_generation_case(record:Dictionary,requested:Dictionary,plan:Dictionary)->void:
	var packet:=await prepare_worker(requested,plan)
	clear_caches();Paint.prepare_images(packet.images)
	var first_path:String=record.prefab_materials[0].texture_path
	var second_path:String=record.prefab_materials[0].roughness_path
	var first:Dictionary={"name":"resident first","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":first_path}
	var second:Dictionary=first.duplicate(true);second.name="resident second";second.texture_path=second_path
	var first_owner:=Paint.make_material(first);var second_owner:=Paint.make_material(second)
	var resident:=Prefab.texture_tickets({first_path:true,second_path:true})
	var resident_packet:Dictionary={"images":{},"sources":packet.sources.duplicate(),"resident_textures":resident}
	Paint._materials.clear();Paint._material_refs.clear();Paint.prepared_images.clear()
	var materials:Array=[{"paint":first,"cull":0},{"paint":second,"cull":0}]
	var pool:Dictionary={};var tickets:Dictionary={};var state:Dictionary={}
	check(Slices.step_prepared(record,materials,{},pool,tickets,resident_packet,state)==Slices.PROGRESS and pool.has([materials[0]]) and not pool.has([materials[1]]),"resident-only first slice completes one material and leaves the next slot pending")
	var original:=FileAccess.get_file_as_bytes(second_path)
	var image:=Image.create(19,13,false,Image.FORMAT_RGBA8);image.fill(Color.BLUE);image.save_png(second_path)
	var fresh_requested:Dictionary={second_path:[second_path,false,false]}
	var fresh:=await prepare_worker(fresh_requested,Prep.estimate(fresh_requested,files.content_root))
	Paint.prepare_images(fresh.images);var newer:Texture2D=Paint.texture(second)
	Paint._textures.erase(second_path)
	check(newer!=null and Paint._texture_refs[second_path].get_ref()==newer and Prefab.tickets_valid(resident,resident_packet.sources),"new generation remains only in weak catalogue while old immutable resident tickets stay admissible")
	files.write_bytes(second_path,original)
	check(Slices.step_prepared(record,materials,{},pool,tickets,resident_packet,state)==Slices.PROGRESS and pool.has([materials[1]]),"resident-only continuation completes the remaining material")
	var completed:StandardMaterial3D=pool.get([materials[1]])
	check(completed!=null and completed.albedo_texture==second_owner.albedo_texture and completed.albedo_texture.get_meta("runtime_source_sha256")==resident_packet.sources[second_path],"resident-only continuation restores its own ticket instead of borrowing a newer weak texture")
	check(state.initializations==2,"resident-only weak generation conflict re-enters the full handoff once")
	if completed!=null:
		RenderingServer.force_sync()
		check(canonical(completed.albedo_texture.get_image())==canonical(packet.images[second_path]) and canonical(newer.get_image())==canonical(fresh.images[second_path]),"resident-only generations keep independent exact pixels")
	first_owner=null;second_owner=null;completed=null;newer=null
	pool.clear();packet.clear();fresh.clear();resident.clear();resident_packet.clear();tickets.clear();state.clear();clear_caches();Drainer.synchronize_transfer()
