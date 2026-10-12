extends SceneTree
## CPU-only definition reuse and authority fixtures. Real-map benchmark is
## optional and read-only; all mutations below target newly created fixtures.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Prepare=preload("res://scripts/world3d/chunk_reference_preparation.gd")
var passed:=0
var failed:=0
var directory:=""
var files:Array[String]=[]
var folders:Array[String]=[]

class CancelToken extends RefCounted:
	var checks:=0
	var after:=1
	func is_cancelled()->bool:
		checks+=1
		return checks>=after

class ChangeSourceToken extends RefCounted:
	var checks:=0
	var path:=""
	var bytes:=PackedByteArray()
	func is_cancelled()->bool:
		checks+=1
		if checks==5:
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
		return false

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if value:passed+=1
	else:failed+=1

func fixture(value:int=1)->Dictionary:
	return {"kind":"box","nested":{"array":[{"value":value},[1,2,3]]},"packed":PackedByteArray([value,255]),"text":"bounded CPU snapshot ".repeat(200),"vector":Vector3.ONE,
		"all_packed":{"bytes":PackedByteArray([1,2]),"i32":PackedInt32Array([1,2]),"i64":PackedInt64Array([1,2]),"f32":PackedFloat32Array([1.,2.]),"f64":PackedFloat64Array([1.,2.]),"string":PackedStringArray(["one","two"]),"v2":PackedVector2Array([Vector2.ONE]),"v3":PackedVector3Array([Vector3.ONE]),"v4":PackedVector4Array([Vector4.ONE]),"color":PackedColorArray([Color.WHITE])}}

func mutate_packed(definition:Dictionary)->void:
	# Intentionally pull the value out of a nested container before modifying it;
	# freezing that container alone does not isolate the underlying packed data.
	for field:String in definition.all_packed:
		var packed:Variant=definition.all_packed[field]
		match typeof(packed):
			TYPE_PACKED_STRING_ARRAY:packed[0]="changed"
			TYPE_PACKED_VECTOR2_ARRAY:packed[0]=Vector2(7,8)
			TYPE_PACKED_VECTOR3_ARRAY:packed[0]=Vector3(7,8,9)
			TYPE_PACKED_VECTOR4_ARRAY:packed[0]=Vector4(7,8,9,10)
			TYPE_PACKED_COLOR_ARRAY:packed[0]=Color.BLACK
			_:packed[0]=7

func write(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes);file.close()
	if not files.has(path):files.append(path)

func resource(definition:Variant,map_name:String="map")->Dictionary:
	var path:=directory.path_join(map_name+".gltf")
	var folder:=path+".resources"
	if not folders.has(folder):
		DirAccess.make_dir_recursive_absolute(folder);folders.append(folder)
	var raw:=var_to_bytes(definition);var bytes:=Store._compressed(raw);var sha:=Store._sha(bytes)
	var uri:=path.get_file()+".resources/"+sha+".rmres"
	var location:=directory.path_join(uri)
	write(location,bytes)
	return {"path":path,"location":location,"raw_length":raw.size(),"bytes":bytes,"compact":{"uuid":"fixture","position":[0.,0.,0.],"rotation":[0.,0.,0.],"size":[1.,1.,1.],"rmmo_state":{"editor_name":"fixture"},"rmmo_ref":{"version":1,"uri":uri,"sha256":sha,"length":bytes.size()}}}

func read(item:Dictionary)->Dictionary:
	return Store._read(item.location,item.compact.rmmo_ref.sha256,item.bytes.size())

func stat_count(trace:Dictionary,label:String)->int:
	for stat:Dictionary in trace.stats:
		if stat.label==label:return int(stat.count)
	return 0

func run()->void:
	directory=Paths.cache_directory("house_definition_reuse_%d"%Time.get_ticks_usec())
	var first:=resource(fixture())
	Store.configure_definition_cache(0)
	var decoded:=read(first)
	check(decoded.ok and decoded.definition_cache=="bypass" and Store.definition_cache_stats().entries==0,"standalone default retains no definition without a reserved byte budget")
	check(Store.configure_definition_cache(Store.DEFINITION_CACHE_MAX_BYTES+1)==Store.DEFINITION_CACHE_MAX_BYTES,"configured budget has a hard 32 MiB ceiling")
	Store.reset_definition_cache()
	Trace.start();decoded=read(first)
	var trace:=Trace.stop()
	check(decoded.ok and decoded.definition_cache=="miss" and stat_count(trace,"resource.decompress_variant")==1,"cold read decodes the complete definition once")
	var stats:=Store.definition_cache_stats()
	check(stats.insertions==1 and stats.entries==1 and stats.resident_bytes==Store._definition_cost(first.raw_length),"retained definition is charged by conservative bytes rather than entry count")
	decoded.definition.nested.array[0].value=999
	decoded.definition.nested.array[1][0]=999
	decoded.definition.packed[0]=99
	decoded.definition.text="mutated caller"
	mutate_packed(decoded.definition)
	Trace.start();var second:=read(first);trace=Trace.stop()
	check(second.ok and second.definition_cache=="hit" and second.definition==fixture(),"cold return cannot mutate the private immutable snapshot")
	check(decoded.definition.all_packed!=second.definition.all_packed,"all ten packed types pulled from a cold return are isolated by the private deep copy")
	check(stat_count(trace,"resource.read_sha")==1 and stat_count(trace,"resource.decompress_variant")==0 and stat_count(trace,"resource.safety")==0 and stat_count(trace,"resource.identity_sha")==0,"warm reuse still reads and hashes file bytes but skips only proven decode/safety/raw SHA")
	second.definition.nested.array[0].value=333;second.definition.packed[0]=44
	mutate_packed(second.definition)
	check(read(first).definition==fixture(),"warm returns also own independent nested and packed data")
	check(second.definition.all_packed!=fixture().all_packed,"all ten packed types pulled from a warm return are isolated by its deep copy")
	Store.configure_definition_cache(Store.DEFINITION_CACHE_MAX_BYTES)
	check(Store.definition_cache_stats().entries==1,"repeating the owner's same reservation preserves reuse")
	var another_path:=resource(fixture(),"other")
	check(read(another_path).definition_cache=="hit","identical verified content may reuse a snapshot across different approved paths")
	var before:int=Store.definition_cache_stats().hits
	DirAccess.remove_absolute(another_path.location)
	check(not read(another_path).ok and Store.definition_cache_stats().hits==before,"a missing different path cannot borrow an old content proof")
	write(another_path.location,another_path.bytes)
	var corrupt:PackedByteArray=first.bytes.duplicate();corrupt[-1]^=1
	write(first.location,corrupt)
	check(not read(first).ok and Store.definition_cache_stats().hits==before,"same-size in-place corruption is rejected before cache lookup")
	write(first.location,first.bytes.slice(0,first.bytes.size()-1))
	check(not read(first).ok,"truncation cannot borrow a cached definition")
	write(first.location,first.bytes)
	check(not Store._read(first.location,first.compact.rmmo_ref.sha256,first.bytes.size()+1).ok,"requested length remains authoritative on a warm hit")
	var different:=resource(fixture(2))
	var different_read:=read(different)
	check(different_read.ok and different_read.definition_cache=="miss" and different_read.definition==fixture(2),"different complete content identities never alias")
	var records:Array=[first.compact.duplicate(true),first.compact.duplicate(true)]
	records[1].uuid="second";records[1].position[0]=3.;records[1].rmmo_state.editor_name="second"
	var closure:Dictionary={first.compact.rmmo_ref.uri:first.compact.rmmo_ref.sha256}
	var hydrated:=Store.read_records(records,first.path,Paths.external_root(),closure)
	check(hydrated.ok and hydrated.read_profile.definition_cache_hits==1 and hydrated.records.size()==2,"public hydration reports one shared definition hit per unique URI")
	hydrated.records[0].nested.array[0].value=89;hydrated.records[0].position[0]=99.;hydrated.records[0].editor_name="edited"
	check(hydrated.records[1].nested.array[0].value==1 and hydrated.records[1].position[0]==3. and records[0].rmmo_state.editor_name=="fixture","editable instances never share mutable definition, transform or state")
	var bad:Array=records.duplicate(true);bad[-1].rmmo_ref.uri="../escape.rmres"
	before=Store.definition_cache_stats().hits
	check(not Store.read_records(bad,first.path,Paths.external_root()).ok and Store.definition_cache_stats().hits==before,"cached bytes do not bypass public path preflight")
	check(Store.verify_dependencies(closure,first.path,Paths.external_root()),"final source verification accepts the intact closure")
	write(first.location,corrupt)
	check(not Store.verify_dependencies(closure,first.path,Paths.external_root()),"final source verification rejects changes after a successful cached hydration")
	write(first.location,first.bytes)
	check(Store.definition_cache_stats().hits==before,"final source verification never consumes decode proofs")
	Store.reset_definition_cache()
	var unsafe:=resource({"uuid":"overrides-instance","kind":"box"},"unsafe")
	check(not read(unsafe).ok and Store.definition_cache_stats().entries==0,"decoded definitions overriding identity cannot seed reuse")
	var old_ticket:=Store._definition_lookup(first.compact.rmmo_ref.sha256,first.bytes.size(),first.raw_length)
	Store.reset_definition_cache()
	Store._definition_remember(old_ticket,fixture(),Store._sha(var_to_bytes(fixture())))
	check(Store.definition_cache_stats().entries==0,"reset cancels in-flight cache publication by generation")
	old_ticket=Store._definition_lookup(first.compact.rmmo_ref.sha256,first.bytes.size(),first.raw_length)
	Store.configure_definition_cache(0)
	Store._definition_remember(old_ticket,fixture(),Store._sha(var_to_bytes(fixture())))
	check(Store.definition_cache_stats().entries==0,"disabling the reserved cache cannot be undone by an old worker")
	var third:=resource(fixture(3))
	var cost:=Store._definition_cost(first.raw_length)
	Store.configure_definition_cache(cost*2)
	read(first);read(different);read(first);read(third)
	stats=Store.definition_cache_stats()
	check(stats.entries==2 and stats.evictions==1 and stats.resident_bytes<=cost*2 and stats.peak_bytes<=cost*2,"LRU eviction bounds accounted resident bytes")
	check(read(first).definition_cache=="hit" and read(different).definition_cache=="miss","recently used content survives and least-recently-used content is decoded again")
	Store.configure_definition_cache(cost-1)
	check(read(first).definition_cache=="bypass" and Store.definition_cache_stats().entries==0,"oversized definitions bypass instead of exceeding the reserve")
	Store.configure_definition_cache(Store.DEFINITION_CACHE_MAX_BYTES);Store.reset_definition_cache()
	var jobs:Array=[]
	for i in 12:jobs.append({"location":first.location,"sha256":first.compact.rmmo_ref.sha256,"length":first.bytes.size()})
	var parallel:=Store._read_many(jobs,true,4)
	stats=Store.definition_cache_stats()
	check(parallel.ok and stats.entries==1 and stats.insertions==1 and parallel.read_profile.workers_joined==parallel.read_profile.threads_started,"concurrent cold requests safely publish one retained snapshot without worker waiting")
	parallel.entries[0].definition.nested.array[0].value=543
	check(parallel.entries[1].definition==fixture() and read(first).definition==fixture(),"concurrent results remain independent of each other and the cache")
	parallel=Store._read_many(jobs,true,4)
	check(parallel.ok and parallel.read_profile.definition_cache_hits==12,"all concurrent warm reads consume validated immutable snapshots")
	check(Store.definition_cache_stats().resident_bytes<=Store.definition_cache_stats().budget_bytes,"concurrent cache publication remains inside its reservation")
	chunk_contract()
	if "--town-benchmark" in OS.get_cmdline_user_args():benchmark()
	Store.configure_definition_cache(0)
	for path:String in files:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	for folder:String in folders:DirAccess.remove_absolute(folder)
	DirAccess.remove_absolute(directory)
	print("HOUSE_DEFINITION_REUSE passed=",passed," failures=",failed)
	quit(1 if failed else 0)

func chunk_contract()->void:
	var helper:=preload("res://tools/test_map_dependency_index.gd").new()
	helper.content_root=Paths.external_root();helper.folder=directory
	var records:Array=[helper.box("entry",0)]
	var map_fixture:Dictionary=helper.fixture("chunk_contract",records)
	var index:Dictionary=Prepare.Index.build(map_fixture.path,helper.content_root,records)
	check(index.ok,"cache transaction fixture has a fully validated dependency index")
	if not index.ok:
		helper.free();return
	var row:Dictionary=index.rows[0]
	var entries:Array=[{"record_index":0,"compact_record":index.extras.rmmo_records[0],"bounds":row.bounds,"group_id":row.group_id,"asset_path":row.asset_path}]
	Store.reset_definition_cache()
	var prepared:=Prepare.prepare(index,entries,map_fixture.path,helper.content_root)
	check(prepared.error.is_empty() and prepared.selected_closure_verified,"cold definition participates in the real final preparation contract")
	prepared=Prepare.prepare(index,entries,map_fixture.path,helper.content_root)
	check(prepared.error.is_empty() and prepared.read_profile.definition_cache_hits==1 and prepared.selected_closure_verified,"warm definition still earns readiness through the real final preparation contract")
	var before:int=Store.definition_cache_stats().hits
	var token:=CancelToken.new()
	var cancelled:=Prepare.prepare(index,entries,map_fixture.path,helper.content_root,token)
	check(cancelled.cancelled and cancelled.records.is_empty() and Store.definition_cache_stats().hits==before,"cancelled demand cannot borrow a previous warm readiness proof")
	token=CancelToken.new();token.after=3
	cancelled=Prepare.prepare(index,entries,map_fixture.path,helper.content_root,token)
	check(cancelled.cancelled and cancelled.records.is_empty() and Store.definition_cache_stats().hits==before+1,"cancellation after a warm read discards the transaction result")
	var source:String=directory.path_join(row.reference.uri)
	var original:=FileAccess.get_file_as_bytes(source)
	var changed:=original.duplicate();changed[-1]^=1
	var changer:=ChangeSourceToken.new();changer.path=source;changer.bytes=changed
	var rejected:=Prepare.prepare(index,entries,map_fixture.path,helper.content_root,changer)
	check(not rejected.error.is_empty() and rejected.records.is_empty() and changer.checks>=5,"source replacement after cached hydration fails the real final SHA gate")
	write(source,original)
	for path:String in helper.created:
		if not files.has(path):files.append(path)
	folders.append(map_fixture.path+".resources")
	helper.free()

func benchmark()->void:
	var selection:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://review_artifacts/house_audit_selection_20261011.json"))
	check(FileAccess.get_sha256(selection.map)==selection.map_sha,"benchmark starts with the audited map identity")
	var groups:Dictionary={};var unique:Dictionary={}
	for row:Dictionary in selection.house_rows:
		var ref:Dictionary=row.reference
		unique[ref.sha256]=ref
		if not groups.has(row.group_id):groups[row.group_id]={}
		groups[row.group_id][ref.sha256]=ref
	var refs:Array=[]
	for group:Dictionary in groups.values():refs.append_array(group.values())
	# Separate initial filesystem effects from the warm CPU reuse comparison.
	# Every measured round still performs all complete file reads and SHA checks.
	Store.configure_definition_cache(0)
	var warm_started:=Time.get_ticks_usec();var warm_ok:=true
	for ref:Dictionary in unique.values():
		if not Store._read(selection.map.get_base_dir().path_join(ref.uri),ref.sha256,int(ref.length)).ok:warm_ok=false;break
	check(warm_ok,"untimed unique-source warmup validates all real definitions")
	var report:={"scope":"CPU-only serial repeated group definition reads. Same complete file reads/SHA on every call; no game entry, images, geometry or final transaction timing. Each round starts with empty definition cache; all unique sources read once before timing and filesystem cache not cleared.","map_sha":selection.map_sha,"groups":groups.size(),"unique_resources":unique.size(),"group_resource_pairs":refs.size(),"warmup_us":Time.get_ticks_usec()-warm_started,"rounds":[]}
	for enabled:bool in [false,true,true,false]:
		Store.configure_definition_cache(Store.DEFINITION_CACHE_MAX_BYTES if enabled else 0)
		Store.reset_definition_cache()
		Trace.start()
		var start:=Time.get_ticks_usec();var valid:=true
		for ref:Dictionary in refs:
			var result:=Store._read(selection.map.get_base_dir().path_join(ref.uri),ref.sha256,int(ref.length))
			if not result.ok:valid=false;break
		var elapsed:=Time.get_ticks_usec()-start
		var trace:=Trace.stop()
		check(valid,"real town group-pair round retains valid decoded definitions")
		report.rounds.append({"enabled":enabled,"elapsed_us":elapsed,"cache":Store.definition_cache_stats(),"trace_stats":trace.stats,"events_dropped":trace.dropped})
		print("HOUSE_DEFINITION_BENCH enabled=",enabled," elapsed_ms=",elapsed/1000.," cache=",Store.definition_cache_stats())
	for ref:Dictionary in unique.values():
		if FileAccess.get_sha256(selection.map.get_base_dir().path_join(ref.uri))!=ref.sha256:
			check(false,"benchmark left a source resource unchanged");return
	check(FileAccess.get_sha256(selection.map)==selection.map_sha,"benchmark ends with unchanged map and all 424 resource identities")
	report.passed=passed;report.failures=failed
	var output:=FileAccess.open("res://review_artifacts/house_definition_reuse_20261011.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
