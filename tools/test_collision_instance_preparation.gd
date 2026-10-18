extends "res://tools/test_collision_asset_descriptor.gd"
## Real PNG/GLB + actual map/rmres/index proof. All preparation runs on Thread;
## no scene/tree/physics publication and no permanent author resources touched.
const Prepare=preload("res://scripts/world3d/collision_instance_preparation.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const MapFixture=preload("res://tools/test_map_dependency_index.gd")
class Mutate extends RefCounted:
	var calls:=0
	var at:=6
	var path:=""
	var bytes:=PackedByteArray()
	var cancel:=false
	func is_cancelled()->bool:
		calls+=1
		if calls==at and not path.is_empty():
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
		return cancel and calls>=at

func request(index:Dictionary,positions:Array)->Array:
	var result:Array=[]
	for at:int in positions:
		var row:Dictionary=index.rows[at]
		result.append({"record_index":at,"compact_record":index.extras.rmmo_records[at],"bounds":row.bounds,"group_id":row.group_id,"asset_path":row.asset_path})
	return result
func placed(uuid:String,path:String,position:Array,rotation:Array,size_:Array,mode:String="")->Dictionary:
	return {"uuid":uuid,"kind":"asset","asset_path":path,"position":position,"rotation":rotation,"size":size_,"collision":mode}
func rewrite_nodes(path:String,operation:Callable)->void:
	var original:=FileAccess.get_file_as_bytes(path);var length:int=original.decode_u32(12)
	var data:Dictionary=JSON.parse_string(original.slice(20,20+length).get_string_from_utf8())
	operation.call(data)
	var binary:=original.slice(28+length);var json:=JSON.stringify(data).to_utf8_buffer()
	while json.size()%4:json.append(32)
	var out:=PackedByteArray();out.resize(20);out.encode_u32(0,0x46546c67);out.encode_u32(4,2);out.encode_u32(8,28+json.size()+binary.size());out.encode_u32(12,json.size());out.encode_u32(16,0x4e4f534a);out.append_array(json)
	var tail:=PackedByteArray();tail.resize(8);tail.encode_u32(0,binary.size());tail.encode_u32(4,0x004e4942);out.append_array(tail);out.append_array(binary);put(path,out)

func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=true # Explicit source replacement diagnostic.
	var errors:=Errors.new();OS.add_logger(errors)
	folder=Paths.cache_directory("collision_instance_test_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var model:=folder.path_join("fixture.glb");fixture(model)
	var original_model:=FileAccess.get_file_as_bytes(model)
	var built:=await worker(Builder.build.bind(model,folder,Builder.estimate(model,folder).estimated_bytes))
	check(built.ok and verify_png(built.private_preparation),"real producer parses PNG model before independent map adapter")
	if not built.ok:Drainer.dispose_result(built);finish(errors);return
	var expected:=expected_entries(built.private_preparation.scene)
	var doc:=preload("res://scripts/world3d/world_document.gd").new()
	doc._namespace_asset(built.private_preparation.scene,"probe",built.private_preparation.scene)
	var namespace_ok:=true
	for row:Dictionary in expected:
		var node:Node=built.private_preparation.scene.get_node(NodePath(row.node_path))
		namespace_ok=namespace_ok and Io.extras_of(node).uuid=="probe__"+row.node_path.replace("/","__") and row.node_path!=row.selector
	check(namespace_ok,"actual importer name paths match production namespace including its generated wrapper")
	Drainer.dispose_result(built)
	var helper:=MapFixture.new();helper.folder=folder;helper.content_root=folder
	var records:Array=[placed("first",model,[10,2,-4],[0,37,0],[1,2,.5]),placed("second",model,[-20,1,4],[0,-30,0],[2,1,1],"walk")]
	var fixture_map:=helper.fixture("map",records);var path:String=fixture_map.path
	var indexed:=Index.build(path,folder,records)
	check(indexed.ok,"real reference map writes and builds dependency directory")
	var loaded:=Index.read_for_loading(path,folder)
	check(loaded.ok and loaded.proof!=null,"disk index reader issues exact sealed ownership proof")
	if not loaded.ok:helper.free();finish(errors);return
	var req:=request(loaded.index,[1,0])
	var plan:=await worker(Prepare.plan.bind(loaded.index,req,path,folder,loaded.proof))
	check(plan.ok and plan.candidates.size()==1 and plan.positions==[0,1],"plan deduplicates shared model and restores original record order")
	if not plan.ok:print(plan);helper.free();finish(errors);return
	var denied:=Prepare.prepare(plan,plan.estimated_bytes)
	check(not denied.ok and denied.reason=="worker_required","main thread cannot prepare or grant a collision batch")
	var empty:=Prepare.Batch.new()
	check(empty.map_path().is_empty() and empty.map_sha().is_empty() and empty.instances().is_empty() and empty.retained_bytes()==0,"unsealed typed shell exposes no map authority")
	denied=await worker(Prepare.plan.bind(loaded.index,req,path,folder,null))
	check(not denied.ok and denied.reason=="index_proof","caller-provided index without actual reader proof is refused")
	denied=await worker(Prepare.plan.bind(loaded.index.duplicate(true),req,path,folder,loaded.proof))
	check(not denied.ok and denied.reason=="index_proof","copied or altered index cannot borrow proof")
	var altered:=req.duplicate(true);altered[0].compact_record.position[0]+=1
	denied=await worker(Prepare.plan.bind(loaded.index,altered,path,folder,loaded.proof))
	check(not denied.ok and denied.reason=="entry_identity","request cannot rewrite author pose")
	denied=await worker(Prepare.prepare.bind(plan,plan.estimated_bytes-1))
	check(not denied.ok and denied.reason=="budget_not_admitted","complete independently recomputed budget required before decode")
	var forged:=plan.duplicate();forged.estimated_bytes=1
	denied=await worker(Prepare.prepare.bind(forged,1))
	check(not denied.ok and denied.reason=="plan_changed","scalar budget hint cannot lower real resource admission")
	var token:=Drainer.CancelToken.new();token.cancel()
	denied=await worker(Prepare.prepare.bind(plan,plan.estimated_bytes,token))
	check(not denied.ok and denied.cancelled and not denied.has("batch"),"pre-cancel grants no map batch")
	Trace.start();var prepared:=await worker(Prepare.prepare.bind(plan,plan.estimated_bytes));var trace:=Trace.stop()
	check(prepared.ok and prepared.batch is Prepare.Batch and prepared.selected_closure_verified and not prepared.closure_complete,"real selected closure yields typed map-bound batch only")
	if not prepared.ok:print(prepared);helper.free();finish(errors);return
	var batch:Prepare.Batch=prepared.batch;var instances:Array=batch.instances()
	check(batch.map_path()==path and batch.map_sha()==FileAccess.get_sha256(path) and instances.size()==2,"batch binds current exact map SHA and both author instances")
	var parity:=true
	for i:int in instances.size():
		var instance:Dictionary=instances[i];var record:Dictionary=records[i]
		var holder:=Node3D.new();holder.position=Index._vec(record.position);holder.rotation_degrees=Index._vec(record.rotation);holder.scale=Index._vec(record.size)
		var pose:Transform3D=holder.transform;holder.free()
		parity=parity and instance.uuid==record.uuid and instance.record_index==i and instance.record_sha==loaded.index.extras.rmmo_records[i].rmmo_ref.sha256 and instance.record_identity==loaded.index.extras.rmmo_records[i] and instance.pose==pose
		for j:int in expected.size():
			var row:Dictionary=instance.rows[j]
			parity=parity and row.uuid==record.uuid+"__"+expected[j].node_path.replace("/","__") and row.transform==pose*expected[j].transform and row.faces==expected[j].faces and row.collision==("walk" if i==1 else expected[j].collision)
	check(parity,"exact faces namespace poses source/record identities and collision overrides match real importer")
	check(count_label(trace,"collision_product.read")==1 and count_label(trace,"deferred.model_parse")==0 and count_label(trace,"deferred.scene_generate")==0 and count_label(trace,"deferred.cpu_capture")==0,"map adapter reads unique CPU product with zero texture decode or render import")
	instances[0].rows[0].faces[0]=Vector3(999,999,999);instances[0].record_identity.position[0]=999;instances.clear()
	check(batch.instances()[0].rows[0].faces==expected[0].faces and batch.instances()[0].record_identity==loaded.index.extras.rmmo_records[0],"getter containers and face COW cannot mutate sealed batch")
	check(batch.retained_bytes()>0 and batch.retained_bytes()<plan.estimated_bytes and not Library._scenes.has(model),"retained output stays charged without polluting render library")
	var raw_map:=FileAccess.get_file_as_bytes(path);put(path,raw_map+" ".to_utf8_buffer())
	denied=await worker(Prepare.prepare.bind(plan,plan.estimated_bytes));check(not denied.ok and denied.reason=="map_changed","map replacement before work cannot use old proof");put(path,raw_map)
	var resource:=Store._location(loaded.index.extras.rmmo_records[0].rmmo_ref.uri,loaded.index.extras.rmmo_records[0].rmmo_ref.sha256,path,folder)
	var original_resource:=FileAccess.get_file_as_bytes(resource);var corrupt:=original_resource.duplicate();corrupt[-1]^=1
	var mutation:=Mutate.new();mutation.path=resource;mutation.bytes=corrupt
	denied=await worker(Prepare.prepare.bind(plan,plan.estimated_bytes,mutation));check(not denied.ok and denied.reason=="reference_changed" and not denied.has("batch"),"rmres changed after decode is caught by final real closure hash");put(resource,original_resource)
	mutation=Mutate.new();mutation.path=path;mutation.bytes=raw_map+" ".to_utf8_buffer()
	denied=await worker(Prepare.prepare.bind(plan,plan.estimated_bytes,mutation));check(not denied.ok and denied.reason=="map_changed","map changed during product read fails final full SHA");put(path,raw_map)
	var changed:=original_model.duplicate();var json_length:int=changed.decode_u32(12);changed.encode_float(28+json_length+12,2.0)
	mutation=Mutate.new();mutation.path=model;mutation.bytes=changed
	denied=await worker(Prepare.prepare.bind(plan,plan.estimated_bytes,mutation));check(not denied.ok and not denied.has("batch"),"same-length GLB replacement during preparation cannot grant old geometry");put(model,original_model)
	mutation=Mutate.new();mutation.cancel=true
	denied=await worker(Prepare.prepare.bind(plan,plan.estimated_bytes,mutation));check(not denied.ok and denied.cancelled and not denied.has("batch"),"mid-preparation cancellation drops pure CPU result before sealing")
	for field:String in ["surface_paint","event","bridge_mesh"]:
		var unsupported:Dictionary=records[0].duplicate(true);unsupported.uuid=field;unsupported[field]={}
		check(not Prepare._supported_record(unsupported),"unsupported "+field+" cannot enter collision-only record path")
	var painted:Dictionary=records[0].duplicate(true);painted.uuid="painted";painted.color=[.5,.5,.5,1]
	var painted_map:=helper.fixture("painted",[painted]);var painted_index:=Index.build(painted_map.path,folder,[painted]);var painted_loaded:=Index.read_for_loading(painted_map.path,folder)
	check(painted_index.ok and painted_loaded.ok,"actual color-override reference remains valid for ordinary load")
	if painted_loaded.ok:
		var painted_plan:=await worker(Prepare.plan.bind(painted_loaded.index,request(painted_loaded.index,[0]),painted_map.path,folder,painted_loaded.proof))
		var painted_result:=await worker(Prepare.prepare.bind(painted_plan,painted_plan.get("estimated_bytes",0)))
		check(not painted_result.ok and painted_result.reason=="unsupported_record_semantics" and painted_result.fallback_required,"actual rmres material override explicitly falls back before any collision handoff")
	# A source with an interaction meaning not represented by this first adapter
	# cannot produce a v2 Asset even though its GLB geometry is ordinary static.
	var semantic:=folder.path_join("semantic.glb");fixture(semantic)
	rewrite_nodes(semantic,func(data:Dictionary)->void:data.nodes[1].extras.surface_id="seat")
	var semantic_result:=await worker(Builder.build.bind(semantic,folder,Builder.estimate(semantic,folder).estimated_bytes))
	check(not semantic_result.ok and semantic_result.reason=="unsupported_node_semantics:surface_id","real GLB interaction extras refuse descriptor instead of silently disappearing");Drainer.dispose_result(semantic_result)
	var root_mesh:=folder.path_join("root_mesh.glb");fixture(root_mesh)
	rewrite_nodes(root_mesh,func(data:Dictionary)->void:data.nodes[0].mesh=0)
	var root_result:=await worker(Builder.build.bind(root_mesh,folder,Builder.estimate(root_mesh,folder).estimated_bytes))
	check(root_result.ok,"real root Mesh GLB can build a named directory")
	if root_result.ok:
		var root_expected:=expected_entries(root_result.private_preparation.scene);var root_read:=await worker(Cache.read.bind(root_result.candidate,folder,root_result.candidate.estimated_bytes))
		var root_parity:bool=root_read.ok
		for i:int in root_expected.size():root_parity=root_parity and root_read.asset.entries()[i].node_path==root_expected[i].node_path
		check(root_parity,"root GLB mesh named paths match actual generated scene wrapper")
	Drainer.dispose_result(root_result)
	var direct_root:=MeshInstance3D.new();direct_root.name="RootName"
	doc._namespace_asset(direct_root,"direct",direct_root)
	check(Cache._node_path(".") and str(direct_root.get_path_to(direct_root))=="." and Io.extras_of(direct_root).uuid=="direct__.","direct root Mesh production namespace uses literal dot; no fake Asset is sealed")
	direct_root.free()
	check(FileAccess.get_file_as_bytes(model)==original_model and FileAccess.get_file_as_bytes(path)==raw_map,"all authorized inputs restored unchanged after mutation cases")
	prepared.clear();batch=null;helper.free();finish(errors)

func finish(errors:Logger)->void:
	remove_fixture(folder);OS.remove_logger(errors)
	check(errors.errors.is_empty(),"zero unexpected engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_INSTANCE_PREPARATION passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
