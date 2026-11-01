extends SceneTree
const Priority=preload("res://scripts/world3d/visual_chunk_priority.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failures+=1
func ordered(heading:int)->Array:
	var values:Array=[]
	for z in range(-2,3):
		for x in range(-2,3):
			if x!=0 or z!=0:values.append([Priority.rank(Vector2i(x,z),heading),Vector2i(x,z)])
	values.sort();return values.map(func(value:Array):return value[1])
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var expected:Array=[Vector2i(0,-1),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(-1,1),Vector2i(1,1),Vector2i(0,-2),Vector2i(-1,-2),Vector2i(1,-2)]
	check(ordered(0).slice(0,11)==expected,"north view reproduces all eleven illustrated chunk priorities")
	var east:Array=expected.map(func(value:Vector2i):return Vector2i(-value.y,value.x))
	check(ordered(2).slice(0,11)==east,"ninety-degree camera turn rotates the full chunk sequence")
	for heading:int in 8:
		var values:Array=ordered(heading);var previous:=0;var ring_order:=true
		for cell:Vector2i in values:
			var ring:=maxi(absi(cell.x),absi(cell.y));ring_order=ring_order and ring>=previous;previous=ring
		check(ring_order,"heading %d completes the current ring before an outer front cell"%heading)
	check(Priority.heading(Vector3.FORWARD)==0 and Priority.heading(Vector3.RIGHT,0)==2,"initial and quarter-turn headings are stable compass buckets")
	var stable:=true
	for angle:float in [21.,23.,20.,26.,22.,-22.,-26.]:
		stable=stable and Priority.heading(Vector3(sin(deg_to_rad(angle)),0,-cos(deg_to_rad(angle))),0)==0
	check(stable,"boundary jitter stays within the existing heading hysteresis")
	check(Priority.heading(Vector3(sin(deg_to_rad(29.)),0,-cos(deg_to_rad(29.))),0)==1,"deliberate turn past hysteresis changes heading")
	check(Priority.heading(Vector3.ZERO,3)==3 and Priority.heading(Vector3.INF,3)==3,"missing or invalid view direction retains its last heading")
	check(Priority.bounds_rank(AABB(Vector3(-10,0,-10),Vector3(1000,1,1000)),Vector3.ZERO,32.,0)==0.,"large spanning bounds rank from their nearest occupied chunk")
	queue_contract(expected)
	mixed_scoring_contract()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine or script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("VISUAL_CHUNK_PRIORITY ",JSON.stringify({"passed":passed,"failures":failures}));quit(0 if failures==0 else 1)

func queue_item(id:String,cell:Vector2i)->Dictionary:
	return {"record":{"uuid":id},"path":"shared-native-model","bounds":AABB(Vector3(cell.x*32.+16.,0,cell.y*32.+16.),Vector3.ONE),"digest":"","native_reference":true,"memory":{"estimated_bytes":1,"exclusive":false}}
func queue_ids(queue:Node)->Array:
	queue._refresh_demanded();return queue._demanded.map(func(row:Dictionary):return row.record.uuid)
func queue_contract(expected:Array)->void:
	var queue:=Deferred.new();var expected_ids:Array=[]
	for cell:Vector2i in ordered(0):
		var id:=str(cell);queue.pending.append(queue_item(id,cell))
	for cell:Vector2i in expected:expected_ids.append(str(cell))
	queue.set_view_direction(Vector3.FORWARD);queue.prioritize(Vector3(16,0,16))
	check(queue_ids(queue).slice(0,11)==expected_ids,"real scheduler uses the eleven illustrated priorities")
	check(queue._dispatch_paths.size()==1 and queue._demanded_by_path["shared-native-model"].size()==24,"direction order keeps one model dispatch and each instance once")
	var revision:int=queue._demand_revision
	for angle:float in [21.,23.,20.,26.,22.,-22.,-26.]:
		queue.set_view_direction(Vector3(sin(deg_to_rad(angle)),0,-cos(deg_to_rad(angle))));queue.prioritize(Vector3(16,0,16));queue_ids(queue)
	check(queue._demand_revision==revision,"camera jitter causes no scheduling revision or repeat work")
	queue.set_view_direction(Vector3.RIGHT)
	var east_ids:Array=expected.map(func(cell:Vector2i):return str(Vector2i(-cell.y,cell.x)))
	check(queue_ids(queue).slice(0,11)==east_ids and queue._demand_revision==revision+1,"quarter-turn invalidates ranks once and rotates the real queue")
	queue.free()
	queue=Deferred.new();queue.pending=[queue_item("far_visual",Vector2i(10,0)),queue_item("predicted",Vector2i(12,0)),queue_item("safety",Vector2i(14,0)),queue_item("near",Vector2i(0,-1))]
	queue.set_view_direction(Vector3.FORWARD);queue.prioritize(Vector3(16,0,16))
	queue.set_demand("prediction",queue.pending[1].bounds,2)
	queue.set_demand("player_collision",queue.pending[2].bounds,-2)
	check(queue_ids(queue)==["safety","near","predicted","far_visual"],"explicit safety and predicted approach retain priority over distant visual order")
	check(queue._demanded_by_id.size()==4 and queue._dispatch_paths.size()==1,"overlapping safety, prediction and visual tickets do not duplicate instances or model paths")
	queue.free()

func mixed_scoring_contract()->void:
	var original:=Deferred.demand_score_pruning_enabled
	var results:Array=[]
	for pruned:bool in [false,true]:
		Deferred.demand_score_pruning_enabled=pruned
		var queue:=Deferred.new();queue.pending=[queue_item("right",Vector2i(1,0)),queue_item("left",Vector2i(-1,0))]
		queue.set_view_direction(Vector3.FORWARD);queue.prioritize(Vector3.ZERO)
		check(queue_ids(queue)==["right","left"],"ordinary side cells retain the illustrated right-before-left order")
		queue.set_demand("explicit_distance",AABB(Vector3(-128,-1,-128),Vector3(256,2,256)),0)
		results.append(queue_ids(queue));queue.free()
	Deferred.demand_score_pruning_enabled=original
	check(results==[["left","right"],["left","right"]],"mixed distance and direction consumers give identical ranks with score pruning")
