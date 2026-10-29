extends "res://tools/test_editor_native_texture_join.gd"
## Deterministic CPU boundaries found by review. All fixtures remain external.
const Queue=preload("res://scripts/world_editor/load_preparation_queue.gd")
const Native=preload("res://scripts/world_editor/native_model_texture_preparation.gd")
class CountingPool extends ControlledPool:
	var offers:=0
	var enabled:=true
	func offer(plan:Dictionary,cached:Dictionary={},revisions:Dictionary={})->Dictionary:
		offers+=1;return super.offer(plan,cached,revisions)
	func _streamed_handoff_enabled()->bool:return enabled

func variant(name_:String,empty:bool=false)->Dictionary:
	var model:=fixture(name_,true)
	var candidate:=Assets.native_candidate(model.path)
	var packet:=Assets._read_published_native(model.path,candidate)
	var table_body:String=FileAccess.get_file_as_string(Binding.Products.table_directory(content_root).path_join(model.table_sha+".json"))
	var table:Dictionary=JSON.parse_string(table_body);table.fixture_variant=name_
	if empty:table.textures={};table.image_bytes=0
	table_body=JSON.stringify(table);model.table_sha=table_body.sha256_text()
	write(Binding.Products.table_directory(content_root).path_join(model.table_sha+".json"),table_body)
	var scene:Node=packet.packed.instantiate();scene.set_meta(Binding.TABLE_META,model.table_sha)
	if empty:scene.get_child(0).mesh.surface_get_material(0).remove_meta(Binding.BINDINGS_META)
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"repack variant "+name_);scene.free()
	var folder:=Compiled.directory(content_root);var staging:=folder.path_join("edge_%d_%s.scn"%[OS.get_process_id(),name_])
	check(ResourceSaver.save(packed,staging,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save variant "+name_)
	packed=null;Drainer.dispose_result(packet)
	var sha:=FileAccess.get_sha256(staging);var product:=folder.path_join(sha+".scn")
	if FileAccess.file_exists(product):DirAccess.remove_absolute(staging)
	else:check(DirAccess.rename_absolute(staging,product)==OK,"publish variant "+name_)
	var file:=FileAccess.open(product,FileAccess.READ);var size:=file.get_length();file.close()
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Compiled.index_path(model.path,content_root)))
	manifest.payload_sha=sha;manifest.bytes=size;manifest.texture_table={"version":1,"sha256":model.table_sha,"bytes":table_body.to_utf8_buffer().size(),"textures":0 if empty else 1,"image_bytes":0 if empty else 64}
	write(Compiled.index_path(model.path,content_root),JSON.stringify(manifest))
	var envelope:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Footprint.descriptor_path(model.path,content_root)))
	var footprint:Dictionary=JSON.parse_string(envelope.body);footprint.payload_sha=sha;footprint.bytes=size
	var body:=JSON.stringify(footprint);write(Footprint.descriptor_path(model.path,content_root),JSON.stringify({"version":1,"body":body,"sha256":body.sha256_text()}))
	return model

func begin(host:Host,records:Array,pool:ControlledPool,bytes_:int=-1)->Node:
	var job:=Job.new();job.editor=host;job._timings.build={"units":{}};host.add_child(job)
	job.native_texture_pool=pool;job.native_texture_preparer=pixels
	var old_enabled:=Frame.enabled;var old_shared:RefCounted=Frame._shared
	Frame.enabled=true;Frame._shared=Frame.new();Frame._shared.covered_limits=Frame.COVERED.duplicate();Frame._shared.covered_limits.publication=0
	job._begin_asset_lookahead(records)
	job._preparation.worker_limit=1;job._preparation.ready_limit=1;job._preparation.ledger.worker_limit=1
	if bytes_>=0:job._preparation.byte_limit=bytes_;job._preparation.ledger.byte_limit=bytes_
	Frame.enabled=old_enabled;Frame._shared=old_shared
	return job

func record(model:Dictionary)->Dictionary:return {"kind":"asset","uuid":model.path,"asset_path":model.path}
func result_into(job:Node,item:Dictionary,box:Dictionary)->void:box.result=await job._prepare_asset(item)
func retire(job:Node,host:Host,paths:Array)->void:
	for path:String in paths:Assets._scenes.erase(path)
	job._clear_asset_lookahead()
	var deadline:=Time.get_ticks_msec()+4000
	while host._shared_preparation_ledger.count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(host._shared_preparation_ledger.count()==0 and host._shared_preparation_ledger.reserved_bytes==0,"edge: ledger drained")
	job.free();host.free();await process_frame

func demand_table(mode:String="fifo")->void:
	var first:=variant("demand_first_"+mode);var second:=variant("demand_second_"+mode)
	check(first.table_sha!=second.table_sha,"demand: table identities actually differ")
	var host:=Host.new();root.add_child(host);var pool:=CountingPool.new()
	var job:=begin(host,[record(first)],pool,1024);var queue:Node=job._preparation
	queue.lanes_enabled=mode!="fifo"
	queue.resident_enabled=mode=="resident";queue.resident_limit=1
	queue.resident_eligible=func(_key:String,packet:Dictionary)->bool:return packet.get("error",FAILED)==OK and Ready.packed_ready(packet.get("packed"))
	var deadline:=Time.get_ticks_msec()+4000
	while not queue.is_ready("model:"+first.path) and Time.get_ticks_msec()<deadline:await process_frame
	check(queue.is_ready("model:"+first.path),"demand: speculative A owns the only ready slot")
	var candidate:=Assets.native_candidate(second.path);job._model_candidates[second.path]=candidate
	job._native_textures.enqueue("model:"+second.path,second.path,candidate,Job._parse_native_asset.bind(second.path,content_root,candidate))
	var box:Dictionary={}
	if mode=="resident":queue.demand("model:"+second.path)
	else:result_into(job,record(second),box)
	deadline=Time.get_ticks_msec()+1200
	while not (queue.is_ready("model:"+second.path) if mode=="resident" else box.has("result")) and Time.get_ticks_msec()<deadline:await process_frame
	if mode=="resident":
		# This proves queue admission/retirement only. The separately gated
		# PreparedModelOwnership publisher still permits ImageTexture only.
		var packet:Dictionary=queue.acquire("model:"+second.path)
		check(not packet.is_empty() and Ready.packed_ready(packet.get("packed")),"resident queue: different-table demand reaches complete READY")
		queue.release("model:"+second.path)
	else:check(box.has("result") and box.result.get("scene")!=null,"demand: different-table B progresses despite A's oversized ready lease")
	check(int(pool.snapshot().produced)==1,"demand: retiring speculative geometry keeps its completed shared texture")
	if box.has("result") and box.result.get("scene")!=null:Drainer.dispose_scene(box.result.scene)
	check(not queue.rows.get("model:"+second.path,{}).has("contract"),"release: offer rows alias removed before metadata retirement")
	job._clear_asset_lookahead();await process_frame
	await retire(job,host,[first.path,second.path])

func overlap_generation()->void:
	var model:=fixture("generation",true);var host:=Host.new();root.add_child(host)
	var pool:=CountingPool.new();pool.hold=true
	var old:=begin(host,[record(model)],pool,4*1024*1024*1024);var old_helper:RefCounted=old._native_textures
	var deadline:=Time.get_ticks_msec()+4000
	while not pool.has_entered() and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.has_entered(),"generation: old native worker is inside controlled pixel preparation")
	old._clear_asset_lookahead()
	var pinned:int=old_helper.catalog.native_metadata_reserved_bytes;var before:int=host._shared_preparation_ledger.byte_limit
	check(pinned>0,"generation: cancelled worker still pins its table")
	var newer:=begin(host,[record(model)],CountingPool.new())
	check(host._shared_preparation_ledger.byte_limit==before,"generation: new LoadJob preserves existing metadata deductions")
	newer._clear_asset_lookahead();pool.gate.post()
	deadline=Time.get_ticks_msec()+4000
	while host._shared_preparation_ledger.count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(host._shared_preparation_ledger.byte_limit==4*1024*1024*1024,"generation: final allowance restores exactly, never above configured limit")
	old.free();await retire(newer,host,[model.path])

func polling_work()->void:
	var model:=fixture("polling",true);var queue:=Queue.new();root.add_child(queue);queue.set_process(false)
	var pool:=CountingPool.new();var helper:=Native.new();helper.configure(queue,content_root,pool,pixels)
	var candidate:=Assets.native_candidate(model.path);var task:=Job._parse_native_asset.bind(model.path,content_root,candidate)
	var key:String="model:"+model.path;helper.enqueue(key,model.path,candidate,task)
	var result:Dictionary={};var deadline:=Time.get_ticks_msec()+4000
	while not result.has("task") and Time.get_ticks_msec()<deadline:
		result=helper._offer(key,model.path,candidate,task);await process_frame
	check(result.has("task"),"polling: one immutable table is ready without dispatch")
	var before:=pool.offers
	for index:int in 40:result=helper._offer(key,model.path,candidate,task)
	check(pool.offers==before,"polling: unchanged admission retries do not rebuild full texture offers")
	var generation:int=Binding.Paint.source_generation;Binding.Paint.source_generation+=1
	result=helper._offer(key,model.path,candidate,task)
	check(pool.offers==before+1,"polling: changed texture identity invalidates exactly one cached offer")
	Binding.Paint.source_generation=generation
	result={};queue.cancel();helper.close()
	check(queue.ledger.reserved_bytes==0 and helper.catalog.native_metadata_reserved_bytes==0,"polling: never-dispatched metadata fully retires")
	queue.free();await process_frame

func empty_table()->void:
	var model:=variant("empty",true);var host:=Host.new();root.add_child(host);var pool:=CountingPool.new();pool.enabled=false
	var keys:=["rendering/textures/streaming/enabled","rendering/textures/streaming/memory_budget_enabled"];var previous:Dictionary={}
	for key:String in keys:previous[key]=ProjectSettings.get_setting(key);ProjectSettings.set_setting(key,false)
	var job:=begin(host,[record(model)],pool,4*1024*1024*1024)
	var result:Dictionary=await job._prepare_asset(record(model));var scene:Node=result.get("scene")
	check(scene!=null and Ready.scene_ready(scene),"empty: no-texture native reaches READY while streaming and budget are disabled")
	check(pool.audit.created==0,"empty: no texture production")
	check(not job._preparation.rows["model:"+model.path].has("contract"),"release: completed task releases its immutable offer aliases")
	if scene!=null:Drainer.dispose_scene(scene)
	for key:String in keys:ProjectSettings.set_setting(key,previous[key])
	await retire(job,host,[model.path])

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(35.0).timeout.connect(func():printerr("EDITOR_NATIVE_TEXTURE_EDGES watchdog");quit(2))
	await demand_table();await demand_table("lanes");await demand_table("resident")
	await overlap_generation();await polling_work();await empty_table()
	print("EDITOR_NATIVE_TEXTURE_EDGES checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
