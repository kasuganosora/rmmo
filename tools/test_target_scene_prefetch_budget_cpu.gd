extends "res://tools/test_initial_native_texture_join.gd"
## Real scheduler/admission with tiny owned geometry and an explicit CPU native
## texture stub. This is not a renderer/StreamedTexture2D success claim.
const Jobs=preload("res://scripts/world3d/initial_native_texture_jobs.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Catalog=preload("res://scripts/world3d/texture_plan_catalog.gd")
const Bridge=preload("res://scripts/world3d/initial_native_resident_bridge.gd")
const Streamed=preload("res://scripts/world3d/streamed_texture_source.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Target=preload("res://scripts/world3d/target_scene_prefetch.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const MiB=1024*1024
const OUTER=1024*MiB
var output:String
var samples:Dictionary={}

class ObservedJobs extends Jobs:
	var stages:Array=[]
	var external_bytes:=0
	func observe(stage:String)->void:
		stages.append({"stage":stage,"external":external_bytes,"geometry":int(profile.geometry_retained_bytes),"metadata":metadata_bytes,"tickets":scope.resident_metadata_bytes,"ledger":ledger.reserved_bytes,"available":ledger.byte_limit})
	func _reapply_budget()->void:
		super._reapply_budget();observe("reapply")
	func _launch(model:Dictionary,stage:String,call:Callable,key:String,starter:Callable)->void:
		super._launch(model,stage,call,key,starter);observe("launch:"+stage)
	func _join_finished()->void:
		super._join_finished();observe("joined")

class ObservedRun extends Bridge.Run:
	var jobs:ObservedJobs
	var transfers:Array=[]
	func request(id:String,rows:Dictionary)->int:
		var reservation:Dictionary=jobs.ledger._entries.get("initial_table:"+id,{})
		var reserved:=int(reservation.get("bytes",0))
		var retained:=int(jobs.tables[id].metadata_bytes)
		var tickets:=super.request(id,rows)
		transfers.append({"reserved_before_request":reserved,"metadata":retained,"tickets":tickets,"covered_before_allocation":reserved>=retained+tickets})
		return tickets

class ObservedBridge extends Bridge:
	var job:ObservedJobs
	var observed:ObservedRun
	func open_run()->Run:
		observed=ObservedRun.new();observed.jobs=job
		_runs[observed.get_instance_id()]=observed
		return observed

func _initialize()->void:budget_run.call_deferred()

func budget_fixture(label:String,width:int,full:bool,count_:int=1)->void:
	content_root=output.path_join(label);var rows:Dictionary={};var total:=0
	var sizes:Array=Streamed._mip_sizes(width,width,Image.FORMAT_RGBA8) if full else [width*width*4]
	var bytes:=0
	for amount:int in sizes:bytes+=amount
	var scene:=Node3D.new()
	for index:int in count_:
		var id:=("texture_%d"%index).sha256_text();total+=bytes
		rows[id]={"file":"cache/world3d/model_textures_v1/"+id+".stex","pixel_sha":id,"width":width,"height":width,"format":Image.FORMAT_RGBA8,"mip_sizes":sizes,"bytes":bytes,"file_bytes":44+8*sizes.size()+bytes,"alpha":false,"normal_xy":false}
		var part:=MeshInstance3D.new();scene.add_child(part);part.owner=scene
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var mat:=StandardMaterial3D.new();mat.set_meta(Binding.BINDINGS_META,{"albedo_texture":{"id":id,"normal":false}})
		mesh.surface_set_material(0,mat);part.mesh=mesh
	var encoded:=JSON.stringify({"version":1,"textures":rows,"image_bytes":total});var sha:=encoded.sha256_text()
	var directory:=content_root.path_join("cache/world3d/compiled_assets_v1/texture_tables_v1")
	DirAccess.make_dir_recursive_absolute(directory)
	var file:=FileAccess.open(directory.path_join(sha+".json"),FileAccess.WRITE);file.store_string(encoded);file.close()
	scene.set_meta(Binding.TABLE_META,sha);packed=PackedScene.new();check(packed.pack(scene)==OK,label+": tiny geometry packed");scene.free()
	candidate={"estimated_bytes":64*MiB,"exclusive":false,"source_sha":"b".repeat(64),"texture_table":{"version":1,"sha256":sha,"bytes":encoded.to_utf8_buffer().size(),"textures":count_,"image_bytes":total}}

func has_property(object:Object,name:String)->bool:
	for property:Dictionary in object.get_property_list():
		if property.name==name:return true
	return false

func fixture_owners()->Array:
	var owners:Array=[]
	for fixture:Dictionary in fixtures.values():owners.append(weakref(fixture.packed))
	return owners

func check_ready(label:String)->void:
	for fixture:Dictionary in fixtures.values():check(Readiness.packed_ready(fixture.packed),label+": complete binding proof before result publication")

func all_retired(owners:Array)->bool:
	for owner:WeakRef in owners:
		if owner.get_ref()!=null:return false
	return true

func write_json(path:String,value:Variant)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value));file.close()

func plan_case()->void:
	budget_fixture("plan_without_table_read",4096,true)
	var path:=content_root.path_join("logical_model.glb");var native:=content_root.path_join("native.scn")
	check(ResourceSaver.save(packed,native)==OK,"plan: real image-free native product saved")
	var sha:=FileAccess.get_sha256(native);var product:=Compiled.directory(content_root).path_join(sha+".scn")
	check(DirAccess.copy_absolute(native,product)==OK,"plan: native product published")
	var length:=FileAccess.get_file_as_bytes(product).size()
	var manifest:={"version":1,"generator":"cpu-budget-protocol","source_sha":"b".repeat(64),"payload_sha":sha,"bytes":length,"texture_table":candidate.texture_table}
	write_json(Compiled.index_path(path,content_root),manifest)
	var body:={"version":1,"source_path":path,"source_sha":manifest.source_sha,"payload_sha":sha,"generator":manifest.generator,"bytes":length,"estimated_bytes":64*MiB,"resident_bytes":64*MiB,"source_bytes":28,"model_metadata":{"version":1,"local_bounds":[0,0,0,1,1,1],"file_length":28,"json_bytes":4,"json_sha256":"a".repeat(64)}}
	var encoded:=JSON.stringify(body);write_json(Footprint.descriptor_path(path,content_root),{"version":1,"body":encoded,"sha256":encoded.sha256_text()})
	var table:=Compiled.directory(content_root).path_join("texture_tables_v1/"+str(candidate.texture_table.sha256)+".json")
	check(DirAccess.rename_absolute(table,table+".withheld")==OK,"plan: withhold table payload for no-extra-read check")
	var planned:Dictionary=Target.plan([{"asset_path":path},{"asset_path":path},{"terrain_mesh":{"columns":1,"rows":1}}],content_root,content_root.path_join("map.gltf"),"c".repeat(64),{})
	check(DirAccess.rename_absolute(table+".withheld",table)==OK,"plan: restore identical table bytes")
	check(not planned.is_empty(),"plan: descriptor-only planning requires no table payload read")
	check(planned.get("native_budget_bytes",-1)==512*MiB-1024,"plan: source/non-model allowance is removed once from outer envelope")
	check(planned.get("estimated_bytes",0)==OUTER,"plan: split declares its complete bounded envelope")
	check(planned.get("files",{}).size()==4,"plan: repeated model path adds no duplicated identity work")
	samples.plan=planned;packed=null;candidate={}

func preparation_zero_case()->void:
	budget_fixture("preparation_zero",4,false)
	var prep:=Preparation.new();prep.require_native_products=true;prep.inflight_byte_limit=0
	if has_property(prep,"strict_native_budget"):prep.set("strict_native_budget",true)
	var pool:=ControlledPool.new();prep.native_texture_pool=pool;prep.native_texture_preparer=fake_pixels;prep.candidate_reader=read_candidate
	prep.candidate_provider=func(_path:String)->Dictionary:return candidate
	prep.memory_estimator=func(_path:String)->Dictionary:return {"estimated_bytes":4096,"exclusive":false}
	var path:=content_root.path_join("model.glb");fixtures={path:{"packed":packed}}
	var worker:=Thread.new();check(worker.start(prep.run.bind([path],Callable(),1,Callable(),content_root))==OK,"preparation: real entry accepts zero-budget operation")
	var deadline:=Time.get_ticks_msec()+10000
	while worker.is_alive() and Time.get_ticks_msec()<deadline:await process_frame
	check(not worker.is_alive(),"preparation: zero-budget coordinator terminates")
	if worker.is_alive():prep.cancel()
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish()
	check(result.error!=OK and not pool.is_entered(),"preparation: strict flag reaches real scheduler before any native pixels")
	check(result.peak_live_estimate_bytes==0 and result.inflight_budget_bytes==0,"preparation: cache-policy work budget cannot round zero up to one")
	Drainer.dispose_result(result);fixtures.clear();packed=null;candidate={}
	check(pool.admission.count()==0,"preparation: zero-budget scope retires")

func scheduler_case(label:String,width:int,full:bool,cap:int,strict:bool,expected_ok:bool,models:int=1,textures:int=1,bridge_case:bool=false,exact_table:bool=false)->void:
	budget_fixture(label,width,full,textures)
	var geometry_bytes:=64*MiB
	if exact_table:
		geometry_bytes=4096
		cap=geometry_bytes+int(Catalog.new()._model_estimate(candidate.texture_table,content_root).estimated_bytes)
	if label=="zero_remaining":geometry_bytes=cap
	var prep:=Preparation.new();prep.require_native_products=true;prep.inflight_byte_limit=cap
	if has_property(prep,"strict_native_budget"):prep.set("strict_native_budget",strict)
	var pool:=ControlledPool.new();prep.native_texture_pool=pool;prep.native_texture_preparer=fake_pixels;prep.candidate_reader=read_candidate
	var paths:Array=[];var candidates:Dictionary={};var estimates:Dictionary={};fixtures={};geometry_reads=0
	for index:int in models:
		var path:=content_root.path_join("model_%d.glb"%index);paths.append(path)
		fixtures[path]={"packed":packed.duplicate(true)};candidates[path]=candidate
		estimates[path]={"estimated_bytes":geometry_bytes,"exclusive":false}
	var jobs:=ObservedJobs.new();jobs.external_bytes=OUTER-cap
	var bridge:ObservedBridge
	if bridge_case:
		bridge=ObservedBridge.new();bridge.job=jobs;bridge.lookup_override=func(_key:String,_row:Dictionary)->Dictionary:return {}
		prep.native_resident_bridge=bridge
	var outer:=Admission.new();outer.worker_limit=2;outer.byte_limit=OUTER
	check(outer.reserve_background("speculative",OUTER,prep.cancel,2),label+": outer lease charged before dispatch")
	var worker:=Thread.new();check(worker.start(jobs.run.bind(prep,paths,candidates,estimates,content_root,1,cap,Callable()))==OK,label+": production scheduler started")
	var deadline:=Time.get_ticks_msec()+10000
	while worker.is_alive() and Time.get_ticks_msec()<deadline:
		if bridge!=null:bridge.pump(1000)
		await process_frame
	check(not worker.is_alive(),label+": scheduler terminates without admission spin")
	if worker.is_alive():prep.cancel()
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish()
	check((result.error==OK)==expected_ok,label+": success or bounded speculative rejection matches contract")
	check(result.threads_started==result.threads_joined,label+": all child workers joined")
	var maximum:=0;var zero_seen:=false
	for stage:Dictionary in jobs.stages:
		var sum_:int=stage.external+stage.geometry+stage.metadata+stage.tickets+stage.ledger
		maximum=maxi(maximum,sum_);zero_seen=zero_seen or stage.available==0
	check(maximum<=OUTER if strict else maximum>OUTER,label+": strict total never exceeds outer lease" if strict else label+": ordinary demand retains oversized exclusive admission")
	if expected_ok:
		check(pool.snapshot().streamed_loads==textures,label+": shared models load each unique texture only once")
		check_ready(label)
	else:check(not pool.is_entered(),label+": rejected pixels never reach native reader")
	if label=="zero_remaining":
		check(zero_seen and jobs.ledger.byte_limit==0,label+": zero capacity remains zero")
		check(not jobs.ledger.reserve("one_byte",{"estimated_bytes":1,"exclusive":false}),label+": zero capacity cannot admit even one byte")
		jobs.ledger.release("one_byte")
	if bridge!=null:
		check(bridge.observed!=null and bridge.observed.transfers.size()==1,label+": one table makes one resident request")
		for transfer:Dictionary in bridge.observed.transfers:check(transfer.covered_before_allocation,label+": original table lease covers metadata and ticket during request")
		check(maximum==OUTER,label+": table launch reaches the exact outer bound")
	check(outer.reserved_bytes==OUTER,label+": joined but undisposed results retain original outer lease")
	var scope:RefCounted=result.native_texture_scope;var ledger:RefCounted=pool.admission
	var owners:=fixture_owners()
	var summary:={"error":result.error,"peak_total":maximum,"outer":OUTER,"cap":cap,"stages":jobs.stages,"profile":result.native_texture_profile.duplicate(true),"transfers":bridge.observed.transfers.duplicate(true) if bridge!=null and bridge.observed!=null else []}
	Drainer.dispose_result(result);fixtures.clear();packed=null;candidate={}
	check(scope.released and ledger.count()==0 and pool.snapshot().consumers==0,label+": scope and child reservations retire completely")
	if bridge!=null:bridge.observed.jobs=null;bridge.job=null;bridge.release_now()
	jobs=null;prep=null
	check(all_retired(owners),label+": observed scheduler and fixture aliases no longer keep private geometry alive")
	outer.release("speculative");check(outer.reserved_bytes==0,label+": outer lease returned after complete retirement")
	samples[label]=summary

func budget_run()->void:
	output=OS.get_environment("RMMO_PREFETCH_REVIEW_OUT").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/"):quit(2);return
	plan_case()
	await preparation_zero_case()
	await scheduler_case("single_mip_reject",16384,false,512*MiB,true,false)
	await scheduler_case("full_8192_reject",8192,true,512*MiB,true,false)
	await scheduler_case("full_4096_accept",4096,true,512*MiB,true,true)
	await scheduler_case("eight_2048_accept",2048,true,512*MiB,true,true,1,8)
	await scheduler_case("shared_models",4096,true,512*MiB,true,true,2)
	await scheduler_case("zero_remaining",4,false,4096,true,false)
	await scheduler_case("resident_exact_boundary",4,false,0,true,false,1,1,true,true)
	await scheduler_case("ordinary_demand",4,false,1024,false,true)
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples,"scope":"CPU native stub protocol, real scheduler/admission and main scope disposal. No large pixels or GPU execution."}));file.close()
	print("TARGET_PREFETCH_BUDGET_CPU ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
