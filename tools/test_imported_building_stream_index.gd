extends SceneTree
## CPU-only imported membership/residency regression. No maps or assets written.
const Index=preload("res://scripts/world3d/stream_index.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
var checks:Array=[]
var failed:=0

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	checks.append({"check":label,"ok":ok});print("PASS " if ok else "FAIL ",label)
	if not ok:failed+=1

func part(id:String,cell:Vector2i,extra:Dictionary,record:Dictionary={})->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,2,2)
	var spec:={"uuid":id,"chunk":cell,"chunk_min":cell,"chunk_max":cell,"transform":Transform3D(Basis.IDENTITY,Vector3(cell.x*32,1,cell.y*32)),"mesh":mesh,"extras":extra}
	if not record.is_empty():spec.ground_batch_record=record
	return spec

func members()->Array:
	var owner:={"id":"imported","floor":0,"role":"body","part":"source"}
	var result:Array=[]
	result.append(part("imported__wall",Vector2i.ZERO,{"building":owner,"rmmo_collision":"block"},{"kind":"box","building":owner}))
	for type_:String in ["lamp","lod","wind","glass"]:
		var extra:={"building":owner.duplicate(),"rmmo_collision":"none"}
		match type_:
			"lamp":extra.rmmo_model_light={}
			"lod":extra.rmmo_auto_lod=true;extra.rmmo_visibility_range={}
			"wind":extra.rmmo_wind={}
			"glass":extra.rmmo_tinted_glass={}
		result.append(part("imported__"+type_,Vector2i(1,0),extra))
	return result

func public_index(data:Dictionary)->Dictionary:
	var value:=data.duplicate(true)
	for field in ["stream_append_state","stream_collision_revision","stream_collision_candidate_cache"]:value.erase(field)
	return value

func run()->void:
	var imported:=members();var original:Array=imported.duplicate(true)
	var built:=Index.build(imported)
	check(built.stream_building_groups.keys()==["imported"] and built.stream_building_groups.imported.size()==5,"full build groups all explicit members independently of merge eligibility and low height")
	var reference:Dictionary=imported[0].render_bounds
	check(imported.all(func(spec):return spec.render_building=="imported" and is_same(spec.render_bounds,reference)),"batched wall and nonbatched lamp/LOD/wind/glass share complete render bounds")
	check(reference.chunk_min==Vector2i.ZERO and reference.chunk_max==Vector2i(1,0),"group render bounds cover every original member")
	check(built.stream_prop_index.is_empty(),"explicit nonbatched building members do not become near-only props")
	var far:={"low":Vector2i(19,-1),"high":Vector2i(21,1)}
	check(imported.all(func(spec):return Stream._draws(spec,far)),"actual runtime draw decision retains all members at town view distance")
	check(built.stream_collision_index.size()==1 and built.stream_collision_index[Vector2i.ZERO].size()==1 and built.stream_collision_index[Vector2i.ZERO][0].uuid=="imported__wall","nonphysical membership does not add walk collision or enlarge near collision bounds")
	check(imported.all(func(spec):return spec.transform==original[imported.find(spec)].transform and spec.chunk_min==original[imported.find(spec)].chunk_min and spec.chunk_max==original[imported.find(spec)].chunk_max),"grouping does not change actual transforms or physical cells")
	var ground:=part("ground",Vector2i.ZERO,{}, {"kind":"box","surface_id":"ground","size":[32,1,32]})
	var growing:=Index.build([ground]);var incoming:=members()
	var appended:=Index.append(growing,incoming)
	check(appended.ok and appended.added==5 and appended.affected_groups==1,"incremental publication accepts the complete imported namespace as one group")
	var rebuilt:=Index.build(([ground]+incoming).duplicate(true))
	check(public_index(growing)==public_index(rebuilt) and growing.stream_append_state==rebuilt.stream_append_state,"incremental group and support bookkeeping equal a fresh full build")
	check(incoming.all(func(spec):return is_same(growing.stream_by_id[spec.uuid],spec) and spec.render_building=="imported" and spec.render_supports==[ground]),"incremental publication retains source identity and shared ground support for nonbatched members")
	var old:=part("legacy__mesh",Vector2i.ZERO,{}, {"building":{"id":"legacy","floor":0,"role":"body"}})
	check(Index.build([old]).stream_building_groups.has("legacy"),"old batch-record-only building membership remains supported")
	var preferred:=part("preferred__mesh",Vector2i.ZERO,{"building":{"id":"authored"}}, {"building":{"id":"stale_batch"}})
	var preferred_index:=Index.build([preferred])
	check(preferred_index.stream_building_groups.has("authored") and not preferred_index.stream_building_groups.has("stale_batch"),"explicit authored owner wins over a stale derived batch owner")
	var ordinary:Array=[part("ordinary_wind__mesh",Vector2i.ZERO,{"rmmo_wind":{},"rmmo_collision":"none"}),part("ordinary_lod__mesh",Vector2i.ZERO,{"rmmo_auto_lod":true,"rmmo_visibility_range":{},"rmmo_collision":"none"})]
	ordinary[0].mesh.size=Vector3(2,20,2)
	var ordinary_index:=Index.build(ordinary)
	check(ordinary_index.stream_building_groups.is_empty() and ordinary_index.stream_prop_index[Vector2i.ZERO].size()==2,"ordinary unowned wind and LOD props retain near residency without invented membership")
	check(ordinary.all(func(spec):return not Stream._draws(spec,far)),"ordinary unowned wind and LOD still disappear outside their near draw ring")
	var growth:=Index.build([]);var ordinary_add:=[part("later_wind__mesh",Vector2i.ZERO,{"rmmo_wind":{},"rmmo_collision":"none"}),part("later_lod__mesh",Vector2i.ZERO,{"rmmo_auto_lod":true,"rmmo_collision":"none"})]
	check(Index.append(growth,ordinary_add).ok and growth.stream_building_groups.is_empty() and growth.stream_prop_index[Vector2i.ZERO].size()==2,"incremental ordinary wind/LOD behavior remains unchanged")
	for bad_id:Variant in [42,1.5,null,[],{}]:
		var bad:=part("invalid__member",Vector2i.ZERO,{"building":{"id":bad_id}})
		var before:=growing.duplicate(true);var before_bad:=bad.duplicate(true)
		var denied:=Index.append(growing,[bad])
		check(not denied.ok and growing==before and bad==before_bad,"non-string authored owner rejected without mutating index or input: "+type_string(typeof(bad_id)))
	var bad_shape:=part("invalid_shape__member",Vector2i.ZERO,{"building":"not_dictionary"})
	check(not Index.append(growing,[bad_shape]).ok,"non-dictionary authored membership is rejected before grouping")
	var destination:="D:/code/rmmo/review_artifacts/axel_landmarks_20261016/pipeline/imported_stream_index.json"
	var file:=FileAccess.open(destination,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed,"scope":"CPU-only full and incremental spatial indexing; no GPU, maps or assets changed","source_sha256":FileAccess.get_sha256("res://scripts/world3d/stream_index.gd")},"\t"));file.close()
	print("IMPORTED_STREAM_INDEX checks=",checks.size()," failures=",failed)
	quit(1 if failed else 0)
