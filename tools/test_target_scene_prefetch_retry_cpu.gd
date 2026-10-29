extends "res://tools/test_target_scene_prefetch_budget_cpu.gd"
## Actual approach/CrossMap/Target/MapLoader/native readers; only world startup,
## transport topology and renderer capability are isolated for this CPU test.
const World=preload("res://scripts/world3d/world_3d.gd")
const Net=preload("res://scripts/net/net.gd")
const Document=preload("res://scripts/world3d/world_document.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Policy=preload("res://scripts/world3d/definition_cache_policy.gd")
const GiB=1024*1024*1024
class SourceWorld extends World:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func _exit_tree()->void:pass
	func _approach_map_target(target:String)->String:return target
class Player extends CharacterBody3D:
	func streaming_intent(_locked:bool)->Dictionary:return {"velocity":Vector3.ZERO,"route":PackedVector3Array()}
class Server extends Node:
	var world3d_events:Dictionary={"targets":{}}
class Reads extends RefCounted:
	var mutex:=Mutex.new()
	var gate:=Semaphore.new()
	var hold:=false
	var entered:=false
	var content_root:String
	var geometry:=0
	var tables:=0
	var pixels:=0
	var owners:Array=[]
	func read(path:String,candidate_:Dictionary)->Dictionary:
		var result:Dictionary=preload("res://scripts/world3d/compiled_asset_preparation.gd").read(path,candidate_,content_root,Callable(),true,false,"",true)
		mutex.lock();geometry+=1
		if result.get("packed")!=null:owners.append(weakref(result.packed))
		var wait_:bool=hold;entered=wait_;mutex.unlock()
		if wait_:gate.wait()
		return result
	func table(candidate_:Dictionary,root_:String)->Dictionary:
		mutex.lock();tables+=1;mutex.unlock()
		return preload("res://scripts/world3d/model_texture_bindings.gd").candidate_plan(candidate_,root_,{})
	func pixel(_plan:Dictionary,_root:String,_token:RefCounted,_shared:Dictionary)->Dictionary:
		mutex.lock();pixels+=1;mutex.unlock();return {"error":"unexpected oversized pixel admission"}
	func snapshot()->Dictionary:
		mutex.lock();var alive:=0
		for owner:WeakRef in owners:
			if owner.get_ref()!=null:alive+=1
		var value:={"geometry":geometry,"tables":tables,"pixels":pixels,"geometry_owners_alive":alive,"entered":entered};mutex.unlock();return value
	func hold_next()->void:
		mutex.lock();hold=true;entered=false;mutex.unlock()
	func release()->void:
		mutex.lock();hold=false;mutex.unlock();gate.post()

var reads:=Reads.new()
var finishes:Array=[]
var retry_samples:Array=[]
func _initialize()->void:retry_run.call_deferred()
func publish_big()->String:
	budget_fixture("retry_native",16384,false)
	var path:=content_root.path_join("logical_model.glb");var native:=content_root.path_join("native.scn")
	check(ResourceSaver.save(packed,native)==OK,"retry: save tiny native geometry")
	var sha:=FileAccess.get_sha256(native);var product:=Compiled.directory(content_root).path_join(sha+".scn")
	check(DirAccess.copy_absolute(native,product)==OK,"retry: publish native geometry")
	var length:=FileAccess.get_file_as_bytes(product).size()
	var manifest:={"version":1,"generator":"cpu-budget-protocol","source_sha":"b".repeat(64),"payload_sha":sha,"bytes":length,"texture_table":candidate.texture_table}
	write_json(Compiled.index_path(path,content_root),manifest)
	var body:={"version":1,"source_path":path,"source_sha":manifest.source_sha,"payload_sha":sha,"generator":manifest.generator,"bytes":length,"estimated_bytes":64*MiB,"resident_bytes":64*MiB,"source_bytes":28,"model_metadata":{"version":1,"local_bounds":[0,0,0,1,1,1],"file_length":28,"json_bytes":4,"json_sha256":"a".repeat(64)}}
	var encoded:=JSON.stringify(body);write_json(Footprint.descriptor_path(path,content_root),{"version":1,"body":encoded,"sha256":encoded.sha256_text()})
	packed=null;candidate={};return path
func configure(node:Node)->void:
	if node.get_script()!=Loader or not node.background_preload:return
	node._model_preparation.candidate_reader=reads.read
	node._model_preparation.native_texture_table_reader=reads.table
	node._model_preparation.native_texture_preparer=reads.pixel
	node.finished.connect(func(_scene:Node,path:String,error:String):finishes.append({"path":path,"error":error,"reads":reads.snapshot(),"native_cap":node._model_preparation.inflight_byte_limit,"cache":Policy.reserved_bytes(),"native_profile":node._profile.get("native_texture_preparation",{}).duplicate(true)}))
func memo(world:Node)->Dictionary:
	var value:Variant=world._target_scene_prefetch.get("_budget_rejection")
	return value if value is Dictionary else {}
func sample(world:Node,label:String)->void:
	retry_samples.append({"label":label,"reads":reads.snapshot(),"cpu":world._cross_map_prefetch.profile.duplicate(true),"target":world._target_scene_prefetch.profile.duplicate(true),"memo":memo(world).duplicate(true),"ledger":world._prefetch_fallback_ledger.reserved_bytes})
func tick(world:Node)->void:
	world._update_approach_preparation();await create_timer(.25).timeout
func rejected(world:Node,expected:int,label:String)->void:
	for index:int in 32:
		await tick(world)
		if reads.snapshot().geometry>=expected and not memo(world).is_empty() and world._target_scene_prefetch._token==null:break
	check(reads.snapshot().geometry==expected and not memo(world).is_empty() and world._target_scene_prefetch._token==null,label+": one attempt retires and records budget rejection")
	sample(world,label)
func stable(world:Node,label:String,count:int=4)->void:
	var before:Dictionary=reads.snapshot();var cpu:int=world._cross_map_prefetch.profile.started;var starts:int=world._target_scene_prefetch.profile.started
	for index:int in count:await tick(world)
	check(reads.snapshot().geometry==before.geometry and reads.snapshot().tables==before.tables and world._cross_map_prefetch.profile.started==cpu and world._target_scene_prefetch.profile.started==starts,label+": no repeated CPU/geometry/table preparation")
	sample(world,label)

func retry_run()->void:
	output=OS.get_environment("RMMO_PREFETCH_REVIEW_OUT").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/"):quit(2);return
	var model:=publish_big();ProjectSettings.set_setting("rmmo/content_root",content_root)
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	reads.content_root=content_root
	var map_path:=content_root.path_join("target.gltf");var other_path:=content_root.path_join("other.gltf")
	var doc:=Document.new();doc.add_box("ground",Vector3(0,-.2,0),Vector3(64,.4,64))
	var uuid:=doc.add_asset({"asset_path":model},Vector3(0,1,8));doc.map_meta={"spawn":[0,.9,6],"map_ref":"retry_target"}
	check(not uuid.is_empty() and doc.save(map_path)==OK,"retry: actual native target map saved")
	check(doc.save(other_path)==OK,"retry: second target saved")
	var server:=Server.new();root.add_child(server);Net._server_override=server
	var world:=SourceWorld.new();root.add_child(world)
	world._map_root=Node3D.new();world.add_child(world._map_root)
	var proxy:=Node.new();proxy.name="DistantBuildingProxy";world._map_root.add_child(proxy)
	world._player=Player.new();world.add_child(world._player);world._player.position=Vector3(0,.9,6)
	var warp:=Node.new();world.add_child(warp);warp.set_meta("center",Vector3(0,.9,6));warp.set_meta("target_path",map_path);warp.set_meta("spawn",[0,.9,6]);world._warp_candidates=[warp]
	node_added.connect(configure)
	for index:int in 12:await tick(world)
	check(reads.snapshot().geometry==1 and reads.snapshot().tables==1,"same rejected approach makes one geometry/table read")
	check(reads.snapshot().pixels==0,"budget rejection precedes pixel IO")
	sample(world,"initial_12_ticks")
	var target:Node=world._target_scene_prefetch;var cpu:Node=world._cross_map_prefetch;var ledger:RefCounted=world._prefetch_fallback_ledger
	if target.has_method("can_prefetch"):
		check(not memo(world).is_empty() and ledger.reserved_bytes==0 and reads.snapshot().geometry_owners_alive==0,"memo holds only scalars after full retirement")
		var before_probes:int=target.profile.get("budget_probe_files",0);var before_suppressed:int=target.profile.get("budget_suppressed",0)
		await stable(world,"unchanged",8)
		check(int(target.profile.budget_probe_files)-before_probes<=32 and int(target.profile.budget_suppressed)-before_suppressed==8,"each approach check probes at most four paths")
		check(int(target.profile.budget_probe_us)>0 and int(target.profile.budget_probe_max_us)>0,"main-thread stat work is timed, not claimed zero IO")
		check(Target.verify(memo(world).files,content_root),"authoritative source verification remains usable during suppression")
		check(target.take(map_path,Vector3(0,.9,6))==null,"normal transfer receives a prefetch miss, not a retained failed scene")
		world._warp_candidates.clear();world._update_approach_preparation()
		check(memo(world).is_empty(),"leaving approach forgets rejection")
		world._warp_candidates=[warp];await rejected(world,2,"reapproach")
		warp.set_meta("target_path",other_path);await rejected(world,3,"different target")
		check(str(memo(world).path)==other_path,"different target keeps its own bounded memo")
		Policy.enabled=true;Policy.configure();await rejected(world,4,"definition cache capacity change")
		check(int(memo(world).definition_cache_bytes)==Policy.reserved_bytes() and Policy.reserved_bytes()>0,"memo uses actual configured definition cache capacity")
		await stable(world,"same cache capacity")
		Policy.enabled=false;Policy.configure();await rejected(world,5,"definition cache capacity restored")
		var original_files:Dictionary=memo(world).files.duplicate(true)
		var descriptor:=Footprint.descriptor_path(model,content_root)
		var file:=FileAccess.open(descriptor,FileAccess.READ_WRITE);file.seek_end();file.store_string("\n");file.close()
		check(not Target.verify(original_files,content_root),"normal source verification detects changed manifest despite memo")
		await rejected(world,6,"observable manifest length change")
		check(memo(world).files!=original_files,"fresh preparation captures new manifest identity")
		await stable(world,"unchanged new manifest")
		var prior_cap:int=memo(world).native_budget_bytes
		doc.records[0]["terrain_mesh"]={"version":1,"columns":2,"rows":2,"floor":-1,"heights":[0,0,0,0,0,0,0,0,0],"holes":[false,false,false,false]}
		check(doc.save(other_path)==OK,"save actual source change affecting native cap")
		await rejected(world,7,"native cap changes with source work")
		check(int(memo(world).native_budget_bytes)==prior_cap-4096,"memo records the actually used native cap after terrain reservation")
		await stable(world,"same changed native cap")
		world._warp_candidates.clear();world._update_approach_preparation();reads.hold_next();world._warp_candidates=[warp]
		for index:int in 24:
			await tick(world)
			if reads.snapshot().entered:break
		check(reads.snapshot().entered and ledger.reserved_bytes>=GiB,"controlled parser owns the full outer lease before cancellation")
		target.cancel();cpu.cancel();var frames:int=Engine.get_process_frames()
		for index:int in 4:await process_frame
		check(Engine.get_process_frames()>frames and ledger.reserved_bytes>=GiB and reads.snapshot().geometry_owners_alive>0,"cancel advances frames while parser geometry and lease stay owned")
		reads.release()
		for index:int in 500:
			await process_frame
			if target._token==null:break
		check(target._token==null and ledger.reserved_bytes==0 and memo(world).is_empty() and reads.snapshot().geometry_owners_alive==0,"ordinary cancellation retires fully without a budget memo")
		await rejected(world,9,"same target after ordinary cancel")
		check(reads.snapshot().pixels==0,"all speculative rejection cases avoid pixel IO")
	world._warp_candidates.clear();world._update_approach_preparation()
	await cpu.drain();await target.drain();world.free()
	for frame:int in 4:await process_frame
	check(ledger.reserved_bytes==0 and reads.snapshot().geometry_owners_alive==0,"final cancellation releases every lease and native geometry owner")
	Net._server_override=null;server.free();node_added.disconnect(configure);Policy.enabled=false;Policy.configure()
	write_json(output.path_join("result.json"),{"checks":checks,"failures":failures,"samples":retry_samples,"finishes":finishes,"final":reads.snapshot(),"scope":"CPU-only world startup/transport isolation; real approach method, CrossMap, Target, MapLoader, native SCN/table readers and scheduler. No texture pixels or GPU. Normal transfer is checked through existing miss and verify contracts; full foreground load retains its separate scheduler regression."})
	print("PREFETCH_RETRY ",JSON.stringify({"checks":checks,"failures":failures,"reads":reads.snapshot(),"finishes":finishes.size()}))
	quit(0 if failures.is_empty() else 1)
