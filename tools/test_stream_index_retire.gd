extends SceneTree
## CPU-only index transactions; no scene nodes, uploads or rendering.
const Index=preload("res://scripts/world3d/stream_index.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func spec(id:String,low:Vector2i=Vector2i.ZERO,high:Vector2i=Vector2i.ZERO,record:Dictionary={},extra:Dictionary={})->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,2,2)
	return {"uuid":id,"chunk":low,"chunk_min":low,"chunk_max":high,"transform":Transform3D(Basis.IDENTITY,Vector3(low.x*32,0,low.y*32)),"mesh":mesh,"extras":extra,"ground_batch_record":record,"map_draw_order":17}
func ids_of(items:Array)->Array:
	return items.map(func(item):return item.uuid)
func same_contents(actual:Dictionary,expected:Dictionary)->bool:
	var left:=actual.duplicate();var right:=expected.duplicate()
	for key in ["stream_collision_revision","stream_collision_candidate_cache"]:left.erase(key);right.erase(key)
	return left==right
func reject(existing:Dictionary,library:Array,ids:Array,label:String)->void:
	var before:=existing.duplicate(true);var before_library:=library.duplicate(true)
	var validation:=Index.validate_retire(existing,library,ids)
	var result:=Index.retire(existing,library,ids)
	check(not validation.ok and not result.ok and result.error==validation.error and result.removed_specs.is_empty() and existing==before and library==before_library,label+" rejects atomically")
func weak_probe()->Dictionary:
	var library:Array=[spec("single")]
	var weak:WeakRef=weakref(library[0].mesh)
	var data:=Index.build(library)
	var result:=Index.retire(data,library,["single"])
	return {"watch":weak,"receipt":result,"data":data,"library":library}
func run()->void:
	var library:Array=[spec("before",Vector2i.ZERO,Vector2i.ZERO),spec("bench__a",Vector2i(-1,0),Vector2i(1,1),{"kind":"asset"}),spec("between",Vector2i.ZERO,Vector2i.ZERO),spec("bench__b",Vector2i(1,0),Vector2i(2,1),{"kind":"asset"},{"rmmo_collision":"none"}),spec("after",Vector2i(7,8),Vector2i(7,8))]
	for i in library.size():library[i].map_draw_order=i*11
	var data:=Index.build(library)
	var maps:Dictionary={}
	for field in ["stream_by_id","stream_known","stream_index","stream_prop_index","stream_collision_index","stream_append_state"]:maps[field]=data[field]
	var shared_bucket:Array=data.stream_index[Vector2i.ZERO]
	var shared_props:Array=data.stream_prop_index[Vector2i.ZERO]
	var distant_bucket:Array=data.stream_index[Vector2i(7,8)]
	var survivors:Array=[library[0],library[2],library[4]]
	var removed:Array=[library[1],library[3]]
	reject(data,library,["bench__a"],"partial imported namespace")
	reject(data,library,["bench__a","bench__b","missing"],"invalid late ID after complete namespace")
	reject(data,library,["before","before"],"duplicate requested UUID")
	reject(data,library,["before",23],"non-string late UUID")
	reject(data,library,[""],"empty UUID")
	var snapshot:=data.duplicate(true);var library_before:=library.duplicate(true)
	var preflight:=Index.validate_retire(data,library,["bench__b","bench__a"])
	check(preflight.ok and preflight.removed_ids==["bench__a","bench__b"] and data==snapshot and library==library_before,"preflight is read-only and reports authored order")
	var result:=Index.retire(data,library,["bench__b","bench__a"])
	check(result.ok and result.removed==2 and result.removed_ids==["bench__a","bench__b"] and is_same(result.removed_specs[0],removed[0]) and is_same(result.removed_specs[1],removed[1]),"retire returns original removed specs in stable order")
	check(is_same(result.data,data) and ids_of(library)==["before","between","after"] and library==survivors,"library compaction preserves survivor order")
	var identity_ok:=true
	for survivor:Dictionary in survivors:identity_ok=identity_ok and is_same(data.stream_by_id[survivor.uuid],survivor)
	for field:String in maps:identity_ok=identity_ok and is_same(data[field],maps[field])
	check(identity_ok and library.map(func(item):return item.map_draw_order)==[0,22,44],"survivor objects, maps and draw order remain unchanged")
	check(is_same(shared_bucket,data.stream_index[Vector2i.ZERO]) and shared_bucket==["before","between"] and is_same(shared_props,data.stream_prop_index[Vector2i.ZERO]) and ids_of(shared_props)==["before","between"] and is_same(distant_bucket,data.stream_index[Vector2i(7,8)]),"touched and untouched surviving buckets retain identity and order")
	check(not data.stream_index.has(Vector2i(2,1)) and not data.stream_prop_index.has(Vector2i(2,1)) and not data.stream_collision_index.has(Vector2i(-1,0)),"empty spatial buckets are removed")
	check(not data.stream_append_state.namespaces.has("bench") and not data.stream_append_state.prefixes.has("bench") and not data.stream_known.has("bench__a") and data.stream_building_count==3,"namespace, known and count are retired together")
	check(same_contents(data,Index.build(library.duplicate(true))),"retired index equals a fresh index of survivors")
	var revisit:=Index.append(data,removed)
	library.append_array(removed)
	check(revisit.ok and data.stream_by_id.has("bench__a") and data.stream_append_state.namespaces.has("bench") and same_contents(data,Index.build(library.duplicate(true))),"complete namespace can be published again after retirement")
	var before_empty:=data.duplicate(true)
	check(Index.retire(data,library,[]).ok and data==before_empty,"empty retirement leaves index unchanged")
	var pinned:Array=[]
	for record in [{"building":{}},{"fixture":{}},{"house_prefab":{}},{"terrain_mesh":{}},{"road_mesh":{}},{"channel_mesh":{}},{"bridge_mesh":{}},{"fortification":{}},{"kind":"box"},{"kind":"asset","surface_paint":[]},{"kind":"asset","prefab_materials":[]},{"kind":"asset","material_state":{}},{"kind":"asset","event_template":{}}]:pinned.append(spec("pin_"+str(pinned.size()),Vector2i.ZERO,Vector2i.ZERO,record))
	for extra in [{"fixture":{"id":"door","kind":"door"}},{"building":{}},{"kind":"npc"},{"kind":"gather"},{"kind":"warp"},{"hostile":true},{"ally":true},{"rmmo_streetlamp_instance":"lamp"}]:pinned.append(spec("pin_"+str(pinned.size()),Vector2i.ZERO,Vector2i.ZERO,{},extra))
	for field in ["render_supports","render_dependents","render_bounds","render_building","native_visual"]:
		var item:=spec("pin_"+str(pinned.size()));item[field]=true if field=="native_visual" else [];pinned.append(item)
	for item:Dictionary in pinned:
		var entries:Array=[spec("eligible"),item];var current:=Index.build(entries)
		reject(current,entries,["eligible",item.uuid],"dependent type "+item.uuid)
	var tower:=spec("tower__wall");tower.mesh.size=Vector3(4,20,4)
	var tower_library:Array=[tower];var tower_data:=Index.build(tower_library)
	reject(tower_data,tower_library,[tower.uuid],"inferred tall imported building")
	# A stale consumer cannot swap equal-looking dictionaries underneath the index.
	var wrong_library:=library.duplicate(true)
	reject(data,wrong_library,["before"],"equal-value library with different spec identities")
	var missing_record:=spec("plain",Vector2i.ZERO,Vector2i.ZERO,{}, {"kind":"asset"});missing_record.erase("ground_batch_record")
	var plain_library:Array=[missing_record];var plain_data:=Index.build(plain_library)
	check(Index.retire(plain_data,plain_library,["plain"]).ok and plain_library.is_empty(),"bare independent static prop supports pure index consumers")
	var probe:=weak_probe()
	check(probe.receipt.ok and probe.watch.get_ref()!=null and probe.library.is_empty() and probe.data.stream_by_id.is_empty(),"only short-lived removal receipt retains retired mesh")
	probe.receipt.clear()
	check(probe.watch.get_ref()==null,"mesh is released after caller drops removal receipt")
	var random:=RandomNumberGenerator.new();random.seed=519382
	var authored:Array=[]
	for group in 24:
		for part in 3:
			var low:=Vector2i(random.randi_range(-4,4),random.randi_range(-4,4))
			authored.append(spec("p%d__%d"%[group,part],low,low+Vector2i(1,1),{"kind":"asset"}, {"rmmo_collision":"none"} if part==2 else {}))
	var growing:=Index.build(authored)
	for group in 24:
		var retiring:Array=["p%d__2"%group,"p%d__0"%group,"p%d__1"%group]
		var retired:=Index.retire(growing,authored,retiring)
		check(retired.ok and same_contents(growing,Index.build(authored.duplicate(true))),"successive retirement %d keeps exact spatial and append semantics"%group)
	print("STREAM_INDEX_RETIRE_FINISHED checks=",checks," failures=",failures)
	quit(1 if failures else 0)
