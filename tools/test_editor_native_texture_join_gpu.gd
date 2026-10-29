extends "res://tools/test_initial_native_texture_join_gpu.gd"
## Real editor LoadJob + native files + renderer. Only cancellation scheduling
## uses HeldPool; that gate calls the actual STEX loader before waiting.
const Job=preload("res://scripts/world_editor/load_job.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Frame=preload("res://scripts/world3d/frame_work_budget.gd")
const SOURCE_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
class Host extends Node3D:
	var _shared_preparation_ledger=Admission.new()

func write_json(path:String,value:Dictionary)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(value))

func publish_fixture(scene:Node3D,prepared:Dictionary,label:String)->String:
	scene.name=label
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack "+label+" native geometry")
	var directory:=Compiled.directory(folder);DirAccess.make_dir_recursive_absolute(directory)
	var staging:=directory.path_join(label+".scn")
	check(ResourceSaver.save(packed,staging,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save "+label+" real native geometry")
	packed=null
	var payload_sha:=FileAccess.get_sha256(staging);var product:=directory.path_join(payload_sha+".scn")
	check(DirAccess.rename_absolute(staging,product)==OK,"publish "+label+" immutable native product")
	var file:=FileAccess.open(product,FileAccess.READ);var bytes:=file.get_length();file.close()
	var path:=folder.path_join("assets/"+label+".glb")
	var manifest:={"version":1,"source_path":path,"source_sha":SOURCE_SHA,"payload_sha":payload_sha,"generator":Compiled.generator(),"bytes":bytes,"texture_table":prepared.texture_table}
	write_json(Compiled.index_path(path,folder),manifest)
	var footprint:=manifest.duplicate(true);footprint.erase("texture_table")
	footprint.merge({"source_bytes":28,"estimated_bytes":67108864,"resident_bytes":67108864,"model_metadata":{"version":1,"local_bounds":[-1.525,-.475,0,3.05,.95,0],"file_length":28,"json_bytes":4,"json_sha256":SOURCE_SHA}})
	var body:=JSON.stringify(footprint)
	write_json(Footprint.descriptor_path(path,folder),{"version":1,"body":body,"sha256":body.sha256_text()})
	check(not FileAccess.file_exists(path) and not Assets.native_candidate(path).is_empty(),"real manifest discovers "+label+" without GLB fallback")
	return path

func make_job(paths:Array,pool:RefCounted=null)->Dictionary:
	var host:=Host.new();root.add_child(host)
	var job:=Job.new();job.editor=host;job._timings.build={"units":{}};host.add_child(job)
	if pool!=null:job.native_texture_pool=pool
	var records:Array=[]
	for path:String in paths:records.append({"kind":"asset","uuid":path.get_file(),"asset_path":path})
	job._begin_asset_lookahead(records)
	check(job._preparation.ledger==host._shared_preparation_ledger,"real editor uses its shared admission ledger")
	check(not job._preparation.resident_enabled and not Job.prepared_model_residency_enabled,"default publisher remains residency=false")
	return {"host":host,"job":job,"records":records,"helper":job._native_textures}

func wait_ready(state:Dictionary)->void:
	var queue:Node=state.job._preparation;var deadline:=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<deadline:
		var complete:=true
		for record:Dictionary in state.records:
			if not queue.is_ready("model:"+record.asset_path):complete=false
		if complete:break
		await process_frame
	for record:Dictionary in state.records:
		var key:String="model:"+record.asset_path
		check(queue.is_ready(key),"real queue reaches READY "+record.uuid)
		var packet:Dictionary=queue.rows[key].packet
		check(packet.get("error",FAILED)==OK and Ready.packed_ready(packet.get("packed")),"READY already contains completed native material bindings "+record.uuid)
		check(not Assets._scenes.has(record.asset_path),"private READY has not bypassed LoadJob publication "+record.uuid)

func publish_all(state:Dictionary)->Array:
	var scenes:Array=[]
	for record:Dictionary in state.records:
		var result:Dictionary=await state.job._prepare_asset(record)
		var scene:Node3D=result.get("scene")
		check(scene!=null and Ready.scene_ready(scene),"real LoadJob publishes a bound scene "+record.uuid)
		check(Assets._scenes.has(record.asset_path),"real LoadJob populates the existing template cache "+record.uuid)
		if scene!=null:scenes.append(scene)
	return scenes

func owners_of(packed:PackedScene,plan:Dictionary)->Dictionary:
	var binding:=Binding.begin(packed,plan["keys"],plan.table_sha);var result:Dictionary={}
	for row:Dictionary in binding.bindings:
		for at:int in row.slots.size():
			var texture:Texture2D=row.material.get(row.slots[at])
			check(texture!=null and texture.get_script()==null and texture.is_class("StreamedTexture2D") and texture.call("is_streaming_active"),"material slot owns an engine-registered native texture")
			if texture!=null:result[row.targets[at]]={"id":texture.get_instance_id(),"rid":texture.get_rid().get_id(),"weak":weakref(texture)}
	Binding.release(binding);return result

func same_owners(first:Dictionary,second:Dictionary)->bool:
	if first.size()!=second.size():return false
	for key:String in first:
		if not second.has(key) or first[key].id!=second[key].id or first[key].rid!=second[key].rid:return false
	return true

func close_job(state:Dictionary,label:String)->void:
	state.job._clear_asset_lookahead()
	var deadline:=Time.get_ticks_msec()+10000
	while state.host._shared_preparation_ledger.count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	report[label+"_final_ledger"]=state.host._shared_preparation_ledger.snapshot()
	check(state.host._shared_preparation_ledger.count()==0 and state.host._shared_preparation_ledger.reserved_bytes==0,label+": temporary ledger fully released")
	check(state.helper.catalog.native_metadata_reserved_bytes==0 and state.helper.pool.snapshot().consumers==0 and state.helper.pool.snapshot().outputs==0,label+": catalog and pool release all operation owners")
	state.job.free();state.host.free();state.clear();await process_frame

func wait_engine_zero(label:String)->void:
	var streaming:=Engine.get_singleton("TextureStreaming");var deadline:=Time.get_ticks_msec()+10000
	while int(streaming.call("get_memory_budget_bytes_used"))!=0 and Time.get_ticks_msec()<deadline:await process_frame
	var amount:int=streaming.call("get_memory_budget_bytes_used");report[label+"_engine_bytes"]=amount
	check(amount==0,label+": last native owner drains engine residency to zero")

func compare_views(source:SubViewport,target:SubViewport,label:String)->void:
	var different:=-1;var visible:=0
	for frame:int in 180:
		await process_frame;await RenderingServer.frame_post_draw
		if frame<12 or frame%6!=0:continue
		var a:=source.get_texture().get_image().get_data();var b:=target.get_texture().get_image().get_data();different=0;visible=0
		for at:int in a.size():different+=int(a[at]!=b[at])
		for at:int in range(0,a.size(),4):
			if a[at]!=a[0] or a[at+1]!=a[1] or a[at+2]!=a[2]:visible+=1
		if different==0 and visible>1000:break
	check(different==0 and visible>1000,label+": source/candidate RGBA bytes are identical with visible geometry")
	report[label+"_render"]={"mismatched_bytes":different,"visible_pixels":visible}
	var original:=source.get_texture().get_image();var candidate:=target.get_texture().get_image()
	for entry:Dictionary in [{"name":label+"_source","image":original},{"name":label+"_candidate","image":candidate}]:
		check(entry.image.save_png(folder.path_join(entry.name+".png"))==OK,"keep local lossless "+entry.name)
		check(entry.image.save_webp(folder.path_join(entry.name+".webp"),true,.9)==OK,"write original-size lossy WebP q90 "+entry.name)
	report.screenshot_encoding={"lossy":true,"quality":.9,"dimensions":[384,192]}

func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root()
	if not folder.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(150).timeout.connect(func():printerr("EDITOR_NATIVE_GPU watchdog");quit(2))
	Paint.refresh_sources();Prep.Pixels.Policy.verify_packages=false;Prep.Pixels.profile_enabled=true
	var original:=fixture();original.get_child(1).material_override.resource_local_to_scene=true
	var prepared:=Products.prepare(original,folder)
	check(prepared.ok and prepared.stats.textures==2,"fixture writes two real STEX products shared by eighteen slots")
	var paths:Array=[]
	for label:String in ["cold_first","cold_second","inbound","cancel_ready","cancel_running"]:paths.append(publish_fixture(original,prepared,label))
	Products.restore(prepared)
	check(independent_source(original),"visual baseline retains independent ImageTexture owners")
	var plan:=Binding.candidate_plan(Assets.native_candidate(paths[0]),folder,{})
	var state:=make_job(paths.slice(0,2));await wait_ready(state)
	report.cold_ready=state.helper.snapshot();report.cold_ready_ledger=state.host._shared_preparation_ledger.snapshot()
	check(report.cold_ready.tables.native_async_reads==1,"two cold models read one shared table")
	check(report.cold_ready.geometry_calls==2 and report.cold_ready.binding_calls==2 and report.cold_ready.binding_sets==36,"two actual native geometries bind all thirty-six slots")
	check(report.cold_ready.pool.streamed_loads==2 and report.cold_ready.pool.produced==2 and report.cold_ready.pool.uploads==0,"each STEX loads once with no ImageTexture upload")
	check(report.cold_ready.pool.handoff_outputs==2 and report.cold_ready.pool.retained_bytes==0,"joined native products transfer their envelopes to actual engine residency")
	var scenes:=await publish_all(state)
	if scenes.size()!=2:await close_job(state,"cold_failed");original.free();finish();return
	var owners:=owners_of(Assets._scenes[paths[0]],plan);var second:=owners_of(Assets._scenes[paths[1]],plan)
	check(same_owners(owners,second),"two cold models share exact Texture object and RID identities")
	report.cold_published=state.helper.snapshot()
	var source:=viewport(original);var target:=viewport(scenes[0]);scenes[1].free();scenes.clear()
	await compare_views(source,target,"cold")
	var streaming:=Engine.get_singleton("TextureStreaming");report.cold_engine_bytes=streaming.call("get_memory_budget_bytes_used")
	check(report.cold_engine_bytes>0,"real rendered STEX residency is engine-accounted")
	await close_job(state,"cold")
	check(owners.values().all(func(item):return item.weak.get_ref()!=null),"cache and scene retain native owners after operation closes")
	var fresh:=make_job([paths[2]]);await wait_ready(fresh)
	report.inbound_ready=fresh.helper.snapshot()
	check(report.inbound_ready.cached_textures==2 and report.inbound_ready.pool.get("streamed_loads",0)==0 and report.inbound_ready.pool.produced==0,"new LoadJob reuses both prior owners without STEX reload or allocation")
	check(report.inbound_ready.pool.handoff_outputs==0 and report.inbound_ready.pool.peak_retained_bytes==0,"inbound resident owners neither reserve nor transfer another full texture chain")
	var incoming:=await publish_all(fresh)
	if incoming.size()!=1:await close_job(fresh,"inbound_failed");source.free();target.free();finish();return
	var new_owners:=owners_of(Assets._scenes[paths[2]],plan)
	check(same_owners(owners,new_owners),"inbound LoadJob uses the exact prior objects and RIDs")
	var inbound_view:=viewport(incoming[0]);incoming.clear();target.free()
	Assets.evict_cached_scene(paths[0]);Assets.evict_cached_scene(paths[1]);await close_job(fresh,"inbound")
	await compare_views(source,inbound_view,"inbound_after_old_retirement")
	check(owners.values().all(func(item):return item.weak.get_ref()!=null),"inbound cache survives old operation and both old caches")
	source.free();inbound_view.free();original=null;Assets.evict_cached_scene(paths[2]);prepared.clear()
	await wait_engine_zero("all_published_released")
	check(owners.values().all(func(item):return item.weak.get_ref()==null) and Paint._textures.is_empty(),"final published owners die without a strong texture hot cache")
	await cancel_case(paths[3],false)
	await cancel_case(paths[4],true)
	finish()

func cancel_case(path:String,running:bool)->void:
	var label:="cancel_running" if running else "cancel_ready"
	var pool:RefCounted=HeldPool.new() if running else null
	var state:=make_job([path],pool)
	if running:
		var deadline:=Time.get_ticks_msec()+10000
		while not pool.is_held() and Time.get_ticks_msec()<deadline:await process_frame
		check(pool.is_held(),label+": actual native load reaches the controlled hold")
		check(not state.job._preparation.is_ready("model:"+path) and not Assets._scenes.has(path),label+": incomplete bindings cannot become READY or publish")
		state.job._clear_asset_lookahead()
		check(state.host._shared_preparation_ledger.reserved_bytes>0,label+": in-flight resources remain charged until worker join")
		pool.gate.post()
	else:
		await wait_ready(state)
		report[label+"_ready"]=state.helper.snapshot()
	await close_job(state,label)
	check(not Assets._scenes.has(path),label+": cancellation never publishes a cache entry")
	await wait_engine_zero(label)
