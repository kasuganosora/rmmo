extends SceneTree
const Index=preload("res://scripts/world3d/stream_index.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func spec(id:String,low:Vector2i,high:Vector2i,record:Dictionary={},extra:Dictionary={},height:float=2.,y:float=0.)->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,height,2)
	return {"uuid":id,"chunk":low,"chunk_min":low,"chunk_max":high,"transform":Transform3D(Basis.IDENTITY,Vector3(low.x*32,y,low.y*32)),"mesh":mesh,"extras":extra,"ground_batch_record":record}
func ground(id:String,low:Vector2i,high:Vector2i)->Dictionary:
	return spec(id,low,high,{"kind":"box","surface_id":"ground","size":[32,1,32]})
func house(id:String,group:String,at:Vector2i,floor_id:int=0)->Dictionary:
	return spec(id,at,at,{"building":{"id":group,"floor":floor_id,"role":"floor"}},{"building":{"id":group,"floor":floor_id,"role":"floor"}})
func public_index(data:Dictionary)->Dictionary:
	var result:=data.duplicate(true);result.erase("stream_append_state");return result
func same_full(actual:Dictionary,all:Array,label:String)->void:
	var expected:=Index.build(all.duplicate(true))
	for key:String in expected:
		if key=="stream_append_state":continue
		check(actual[key]==expected[key],label+" matches full build: "+key)
func rejected(existing:Dictionary,items:Array,label:String)->void:
	var before:=existing.duplicate(true);var input:=items.duplicate(true)
	var result:=Index.append(existing,items)
	check(not result.ok and existing==before and items==input,label+" rejects without modifying either input")
func run()->void:
	var initial:Array=[ground("ground_a",Vector2i(-1,0),Vector2i(0,0)),house("house_a_floor","a",Vector2i.ZERO),house("house_a_roof","a",Vector2i.ZERO,1),
		spec("prop_a",Vector2i(7,2),Vector2i(7,2)),spec("road_a",Vector2i(0,0),Vector2i(3,0),{"road_mesh":{}}),
		house("far_floor","far",Vector2i(100,100)),ground("far_ground",Vector2i(100,100),Vector2i(101,101))]
	var additions:Array=[ground("ground_b",Vector2i(0,0),Vector2i(2,0)),house("house_b_floor","b",Vector2i(1,0)),house("house_b_upper","b",Vector2i(1,0),1),
		spec("tower__lower",Vector2i(3,0),Vector2i(3,0),{}, {},8.,0.),spec("tower__upper",Vector2i(3,0),Vector2i(3,0),{}, {},8.,8.),
		spec("lamp__base",Vector2i(2,0),Vector2i(2,0)),spec("lamp__crystal",Vector2i(2,0),Vector2i(2,0),{},{"rmmo_streetlamp_crystal":true,"rmmo_collision":"none"}),
		spec("tree__leaves",Vector2i(2,2),Vector2i(2,2),{},{"rmmo_wind":{},"rmmo_collision":"none"},18.),
		spec("house_b_door",Vector2i(1,0),Vector2i(2,0),{"building":{"id":"b","floor":0,"role":"door"}},{"building":{"id":"b"},"fixture":{"id":"door","kind":"door","open":.4}})]
	var catalog:=Index.build(initial)
	var maps:Dictionary={}
	for key in ["stream_index","stream_by_id","stream_known","stream_prop_index","stream_collision_index","stream_building_groups"]:maps[key]=catalog[key]
	var old_bucket:Array=catalog.stream_index[Vector2i.ZERO]
	var far_supports:Array=catalog.stream_by_id.far_floor.render_supports
	var far_bounds:Dictionary=catalog.stream_by_id.far_floor.render_bounds
	var old_bounds:Dictionary=catalog.stream_by_id.house_a_floor.render_bounds
	var result:=Index.append(catalog,additions)
	check(result.ok and is_same(result.data,catalog) and result.affected_groups==4,"append succeeds and touches only intersected/new groups")
	var invalidated:Dictionary={}
	for old_spec:Dictionary in result.affected_existing_specs:
		check(not invalidated.has(old_spec.uuid) and is_same(old_spec,catalog.stream_by_id[old_spec.uuid]),"residency invalidation keeps unique old reference: "+old_spec.uuid)
		invalidated[old_spec.uuid]=true
	check(invalidated.has("ground_a") and not invalidated.has("far_floor") and not invalidated.has("far_ground") and not invalidated.has("house_b_floor"),"new building invalidates existing support only, not unrelated or incoming specs")
	for key:String in maps:check(is_same(catalog[key],maps[key]),"existing dictionary reference retained: "+key)
	check(is_same(old_bucket,catalog.stream_index[Vector2i.ZERO]),"existing index bucket reference retained")
	check(is_same(catalog.stream_by_id.house_a_floor,initial[1]) and is_same(catalog.stream_by_id.house_b_floor,additions[1]),"existing and incoming author specs keep their identity")
	check(is_same(old_bounds,catalog.stream_by_id.house_a_floor.render_bounds),"affected existing render-bounds dictionary retained")
	check(is_same(far_supports,catalog.stream_by_id.far_floor.render_supports) and is_same(far_bounds,catalog.stream_by_id.far_floor.render_bounds),"unaffected far building dependencies retain their references")
	var all:Array=initial+additions
	same_full(catalog,all,"first append")
	var more:Array=[ground("ground_c",Vector2i(2,-1),Vector2i(4,1)),spec("free_prop",Vector2i(-8,3),Vector2i(-8,3),{},{"rmmo_collision":"none"}),spec("bridge",Vector2i(-3,2),Vector2i(3,2),{"bridge_mesh":{}})]
	var later:=Index.append(catalog,more)
	check(later.ok,"later ground patches can update existing complete groups")
	var later_ids:Array=[]
	for old_spec:Dictionary in later.affected_existing_specs:later_ids.append(old_spec.uuid)
	check(later_ids.has("house_b_floor") and later_ids.has("house_b_upper") and later_ids.has("ground_b") and not later_ids.has("ground_c"),"new ground invalidates old whole building and old support, excluding incoming specs")
	all.append_array(more);same_full(catalog,all,"second append")
	var before:=catalog.duplicate(true)
	check(Index.append(catalog,[]).ok and catalog==before,"empty append is a no-op")
	rejected(catalog,[spec("free_prop",Vector2i.ZERO,Vector2i.ZERO)],"existing UUID")
	rejected(catalog,[spec("duplicate",Vector2i.ZERO,Vector2i.ZERO),spec("duplicate",Vector2i.ONE,Vector2i.ONE)],"duplicate inside batch")
	rejected(catalog,[spec("tower__late",Vector2i.ZERO,Vector2i.ZERO)],"partial imported namespace")
	rejected(catalog,[spec("tower",Vector2i.ZERO,Vector2i.ZERO)],"late plain UUID sharing imported namespace")
	rejected(catalog,[spec("prop_a__late",Vector2i.ZERO,Vector2i.ZERO)],"late namespace sharing an existing plain UUID")
	rejected(catalog,[house("house_b_late","b",Vector2i.ZERO)],"partial native building")
	rejected(catalog,[spec("lamp_late",Vector2i.ZERO,Vector2i.ZERO,{},{"rmmo_streetlamp_instance":"lamp"})],"partial lamp group")
	rejected(catalog,[spec("late_door",Vector2i.ZERO,Vector2i.ZERO,{},{"building":{"id":"b"},"fixture":{"id":"door"}})],"partial active fixture")
	rejected(catalog,[{"uuid":"missing_geometry"}],"malformed spec")
	# Grouping failure after an otherwise valid first item must not leak that item.
	rejected(catalog,[ground("rejected_ground",Vector2i.ZERO,Vector2i.ONE),house("late_house","a",Vector2i.ZERO)],"mixed invalid batch")
	var random:=RandomNumberGenerator.new();random.seed=837219
	var growing:=Index.build([]);var authored:Array=[]
	for batch in 24:
		var at:=Vector2i(random.randi_range(-4,4),random.randi_range(-4,4))
		var end:=at+Vector2i(random.randi_range(0,3),random.randi_range(0,3))
		var building:=Vector2i(random.randi_range(-4,4),random.randi_range(-4,4))
		var incoming:Array=[ground("g_%d"%batch,at,end),house("h_%d_0"%batch,"random_%d"%batch,building),house("h_%d_1"%batch,"random_%d"%batch,building+Vector2i.RIGHT,1)]
		var appended:=Index.append(growing,incoming);authored.append_array(incoming)
		var rebuilt:=Index.build(authored.duplicate(true))
		check(appended.ok and public_index(growing)==public_index(rebuilt) and growing.stream_append_state==rebuilt.stream_append_state,"random ordered batch %d equals full public index and dependency bookkeeping"%batch)
	print("STREAM_INDEX_APPEND_FINISHED failures=",failures)
	quit(1 if failures else 0)
