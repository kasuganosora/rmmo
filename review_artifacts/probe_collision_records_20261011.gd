extends SceneTree
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Descriptor=preload("res://scripts/world3d/collision_asset_descriptor.gd")
const Adapter=preload("res://scripts/world3d/collision_instance_preparation.gd")
const MAP="D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf"
const ROOT="D:/code/rmmo_runtime"
var worker:=Thread.new()
func _initialize()->void:run.call_deferred()
static func probe()->Dictionary:
	var loaded:=Index.read_for_loading(MAP,ROOT)
	if not loaded.ok:return {"ok":false,"reason":loaded.reason}
	var index:Dictionary=loaded.index
	var selected:=Index.select(index,[AABB(Vector3(320,-100000,160),Vector3(32,200000,32))])
	if not selected.ok:return {"ok":false,"reason":selected.reason}
	var candidates:Dictionary={};var compact:Array=[];var sources:Dictionary={};var output:Array=[]
	var landing:=Rect2(319.2,158.3,4,4)
	for at:int in selected.record_indices:
		var row:Dictionary=index.rows[at]
		if row.reason!="model_accessor_bounds" or not row.bounds_known or not row.group_id.is_empty() or not row.owner_keys.is_empty() or row.asset_path.is_empty():continue
		var bounds:AABB=row.bounds
		if landing.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z),true):continue
		if not candidates.has(row.asset_path):candidates[row.asset_path]=Descriptor.candidate(row.asset_path,ROOT)
		if candidates[row.asset_path].is_empty():continue
		compact.append(index.extras.rmmo_records[at]);sources[index.extras.rmmo_records[at].rmmo_ref.uri]=index.extras.rmmo_records[at].rmmo_ref.sha256
	var hydrated:=Store.read_records(compact,MAP,ROOT,sources,1)
	if not hydrated.ok:return {"ok":false,"reason":hydrated.reason}
	var paths:Dictionary={};var issues:Dictionary={}
	for record:Dictionary in hydrated.records:
		var unsupported:Dictionary={}
		for key in record:
			if key not in Adapter.RECORD_FIELDS:unsupported[key]=record[key]
		var row:Dictionary={"uuid":record.uuid,"asset_path":record.asset_path,"collision":record.get("collision",""),"supported":Adapter._supported_record(record),"unsupported_fields":unsupported,"keys":record.keys()}
		output.append(row);paths[record.asset_path]=int(paths.get(record.asset_path,0))+1
		for key in unsupported:issues[key]=int(issues.get(key,0))+1
	return {"ok":true,"selected":selected.selected_count,"deferred_candidates":output.size(),"records":output,"path_counts":paths,"unsupported_counts":issues,"glb_full_sha_calls":0,"imports":0}
func run()->void:
	if worker.start(probe)!=OK:quit(2);return
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish()
	var file:=FileAccess.open("res://review_artifacts/collision_record_semantics_20261011.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print(JSON.stringify(result));quit(0 if result.ok else 1)
