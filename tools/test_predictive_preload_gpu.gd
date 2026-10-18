extends SceneTree
## Real temporary map, native package worker and publication. Run on the private
## desktop. No textures, authored game maps, alternate budgets or fake results.
const Approach=preload("res://scripts/world3d/approach_preparation.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
class Host extends Node3D:
	var _ready_for_play:=true
	var _transfer_pending:=false
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	create_timer(45).timeout.connect(func():quit(2))
	var folder:=Paths.cache_directory("predictive_preload_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("map.gltf")
	var doc:=preload("res://scripts/world3d/world_document.gd").new()
	doc.add_box("ground",Vector3(0,-.5,0),Vector3(8,1,8))
	var ahead:String=doc.add_box("block",Vector3(192,1,0),Vector3(2,2,2))
	var behind:String=doc.add_box("block",Vector3(-192,1,0),Vector3(2,2,2))
	check(doc.save(path)==OK,"isolated white fixture saved externally")
	var sha:=FileAccess.get_sha256(path)
	var loader:=Loader.new();loader.near_first=true;root.add_child(loader);loader.start(path,Vector3(0,.9,0))
	var loaded:Array=await loader.finished
	check(loaded[0]!=null and loaded[2].is_empty(),"production near-first loader opens fixture")
	if loaded[0]==null:quit(1);return
	var map:Node=loaded[0];var host:=Host.new();root.add_child(host);host.add_child(map)
	var queue:Node=map.get_node("DeferredAssets");queue.release_demand("entry_safety");queue.prioritize(Vector3.ZERO);queue.activate(host)
	var ledger:RefCounted=queue._admission;var limit:int=ledger.byte_limit
	var predictor:=Approach.new();Approach.predictive_enabled=false
	predictor.update(queue,Vector3.ZERO,Vector3(4,0,0))
	for i:int in 30:await process_frame
	check(not map.get_meta("stream_by_id",{}).has(ahead),"old building-only prediction leaves ordinary forward geometry unprepared")
	Approach.predictive_enabled=true;var start:=Time.get_ticks_usec()
	predictor.update(queue,Vector3.ZERO,Vector3(4,0,0))
	var deadline:=Time.get_ticks_msec()+10000
	while not map.get_meta("stream_by_id",{}).has(ahead) and Time.get_ticks_msec()<deadline:await process_frame
	var ready_ms:=(Time.get_ticks_usec()-start)/1000.
	check(map.get_meta("stream_by_id",{}).has(ahead),"corridor reads and publishes actual forward geometry while player remains at origin")
	check(not map.get_meta("stream_by_id",{}).has(behind),"off-route geometry stays deferred")
	check(ledger.byte_limit==limit and queue.error.is_empty(),"preloading uses unchanged shared budget without publication errors")
	for i:int in 30:await process_frame
	var prepared:int=int(queue.profile.get("reference_records",0))
	queue.prioritize(Vector3(192,0,0));predictor.release()
	for i:int in 30:await process_frame
	check(int(queue.profile.get("reference_records",0))==prepared,"arrival consumes resident prepared geometry without another package read")
	check(FileAccess.get_sha256(path)==sha,"prediction does not change authored fixture bytes")
	await queue.quiesce();host.free()
	for i:int in 10:await process_frame
	check(ledger.reserved_bytes==0,"exit releases admitted worker and byte leases")
	print("PREDICTIVE_PRELOAD_GPU ",JSON.stringify({"checks":checks,"failures":failures,"ready_before_arrival_ms":ready_ms,"reference_records":prepared}));quit(1 if failures else 0)
