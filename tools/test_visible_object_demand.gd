extends SceneTree
## Gameplay demand must cover every visible kind, independently of learned
## building metadata. Pure queue operations: no map/model I/O or worker jobs.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
const VIEW_RADIUS_CELLS:=126 # 4000m camera + one 32m orbit cell; also runs red on old code.
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failures+=1
func item(id:String,x:float,reason:String="model_accessor_bounds",group:String="",path:String="shared-native-model")->Dictionary:
	return {"record":{"uuid":id},"path":path,"bounds":AABB(Vector3(x,0,0),Vector3.ONE),"digest":"","native_reference":true,"memory":{"estimated_bytes":1,"exclusive":false},"group_id":group,"reference_entry":{"reason":reason}}
func ids(queue:Node)->Array:
	queue._refresh_demanded();var result:Array=queue._demanded_by_id.keys();result.sort();return result
func fixture(indexed:bool=true)->Node:
	var queue:=Deferred.new()
	var end:float=(VIEW_RADIUS_CELLS+1)*32.
	queue.pending=[item("near",10),item("house_unlearned",300),item("tree",400),item("prop",500),item("lamp",600),item("road",700,"native_road"),item("bridge",800,"native_bridge"),item("wall",900,"native_fortification"),item("terrain",950,"terrain_context_global"),item("house_grouped",975,"building_group","building:one"),item("distant_tree",3500),item("edge",end-1),item("beyond",end+1)]
	if indexed:queue._reference_index={"rows":[],"models":{},"groups":{}}
	return queue
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var expected:Array=["bridge","distant_tree","edge","house_grouped","house_unlearned","lamp","near","prop","road","terrain","tree","wall"]
	for indexed:bool in [true,false]:
		var queue:=fixture(indexed);queue.prioritize(Vector3.ZERO)
		var label:="indexed" if indexed else "legacy in-memory"
		check(ids(queue)==expected,label+" first demand includes every in-range kind before building learning")
		check(queue._runtime_building_records.is_empty(),label+" demand does not need runtime building classification")
		check(not queue._demanded_by_id.has("beyond"),label+" background ticket stays inside configured visual cells")
		check(int(queue._demanded_priority.get("near",999))==0 and int(queue._demanded_priority.get("tree",999))==10,label+" nearby work retains priority over distant visuals")
		check(queue._demands.has("visual_render") and queue._demands.get("visual_render",{}).get("kind")=="all",label+" one generic visual ticket replaces kind-specific far tickets")
		check(queue._demands.size()==2,label+" only player and shared visual tickets are created")
		check(queue._demands.player.clip.size==Vector3(288,200000,288) and Stream.COLLISION_RADIUS==2,label+" near preparation uses complete rings while physics stays unchanged")
		var seen:Dictionary={};var unique:=true
		for row:Dictionary in queue._demanded:
			if seen.has(row.record.uuid):unique=false
			seen[row.record.uuid]=true
		check(unique and queue._dispatch_paths.size()==1 and queue._demanded_by_path.get("shared-native-model",[]).size()==expected.size(),label+" overlapping tickets share each instance and model dispatch path")
		var revision:int=queue._demand_revision
		for tick in 10:queue.prioritize(Vector3.ZERO);ids(queue)
		check(queue._demand_revision==revision,label+" stationary frames do not rebuild demand")
		queue.set_demand("entry_safety",AABB(Vector3(-16,-10,-16),Vector3(32,20,32)),-3)
		queue.set_demand_scope(["entry_safety"])
		check(ids(queue)==["near"],label+" minimum entry scope excludes background visuals")
		queue.set_demand_scope([]);queue.release_demand("entry_safety")
		check(ids(queue)==expected,label+" releasing entry scope resumes all background visuals without movement")
		queue._pending_by_record_id["tree"].published=true;queue._demand_revision+=1
		var remaining:Array=expected.duplicate();remaining.erase("tree")
		check(ids(queue)==remaining,label+" completed instance is not requested a second time")
		queue.prioritize(Vector3(10000,0,0));check(ids(queue).is_empty(),label+" leaving visual cells releases stale requests")
		queue.prioritize(Vector3.ZERO);check(ids(queue)==remaining,label+" returning restores incomplete visible work only")
		check("visual_render_radius" in queue,label+" visible extent can follow the active camera")
		if "visual_render_radius" in queue:
			queue.visual_render_radius=2;queue.prioritize(Vector3.ZERO)
			check(ids(queue)==["near"],label+" camera extent change updates membership without player movement")
			queue.visual_render_radius=VIEW_RADIUS_CELLS;queue.prioritize(Vector3.ZERO)
			check(ids(queue)==remaining,label+" restoring camera extent resumes incomplete visible work")
		queue.free()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine or script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("VISIBLE_OBJECT_DEMAND ",JSON.stringify({"passed":passed,"failures":failures}));quit(0 if failures==0 else 1)
