extends "res://tools/test_sliced_batch_collection.gd"
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
class CountingBatch extends "res://scripts/world3d/ground_batcher.gd":
	var collected:=0
	var prepared:=0
	func _prepare_step(budget_usec:int)->void:
		var collecting:bool=not _preparation.is_empty() and _preparation.phase=="collect"
		var cursor:int=_preparation.get("cursor",0);var size:int=_preparation.get("items",[]).size()
		super._prepare_step(budget_usec)
		if collecting:collected+=int(_preparation.cursor)-cursor if not _preparation.is_empty() and _preparation.phase=="collect" else size-cursor
	func _prepare_node(node:Node,desired:Dictionary,excluded:Array)->void:
		prepared+=1;super._prepare_node(node,desired,excluded)
func request(batch:Node,nodes:Array,resume:bool,excluded:Array=[])->void:
	if resume and batch.has_method("request_residency_sync"):batch.call("request_residency_sync",nodes,excluded)
	else:batch.request_sync(nodes,excluded)
func drain(batch:Node)->void:
	var guard:=0
	while not batch._preparation.is_empty() and guard<100000:batch._prepare_step(1);guard+=1
	check(batch._preparation.is_empty(),"preparation converges on positive bounded slices")
func groups_of(batch:Node)->Dictionary:
	var result:Dictionary={}
	for key:String in batch.groups:
		result[key]=[]
		for member:Node in batch.groups[key].members:result[key].append(str(member.name))
	return result
func add_source(host:Node3D,mesh:Mesh,id:String)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=id;node.mesh=mesh
	node.set_meta("ground_batch_record",{"uuid":id,"kind":"box","size":[1,1,1],"building":{"id":"house","floor":0,"part":id,"role":"wall"}})
	host.add_child(node);return node
func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]);mesh.surfaces=[arrays];mesh.bounds=AABB(Vector3(0,0,-1),Vector3(1,0,1));mesh.materials=[StandardMaterial3D.new()]
	var nodes:Array=[]
	for i:int in 4288:nodes.append(add_source(host,mesh,"row_%05d"%i))
	var reports:Array=[];var expected:Dictionary={}
	for resume:bool in [false,true,true,false]:
		var batch:=CountingBatch.new();host.add_child(batch);batch.set_process(false)
		var started:=Time.get_ticks_usec();request(batch,nodes.slice(0,4000),resume)
		for update:int in 24:
			for slice:int in 128:batch._prepare_step(1)
			request(batch,nodes.slice(0,4000+12*(update+1)),resume)
		drain(batch)
		var actual:=groups_of(batch)
		if expected.is_empty():expected=actual
		check(actual==expected,"streaming additions retain exact final bins, member order and exclusions")
		reports.append({"resume":resume,"us":Time.get_ticks_usec()-started,"collected":batch.collected,"prepared":batch.prepared})
		batch.clear(false);batch.free()
	var batch:=CountingBatch.new();host.add_child(batch);batch.set_process(false)
	var initial:=nodes.slice(0,300)
	request(batch,initial,true)
	while batch._preparation.phase=="collect":batch._prepare_step(1)
	for i:int in 20:batch._prepare_step(1)
	check(batch._preparation.phase=="prepare","late addition arrives during partial grouping")
	var late:=add_source(host,mesh,"aaa_late");initial.append(late)
	request(batch,initial,true);drain(batch)
	var oracle:=Batch.new();host.add_child(oracle);oracle.set_process(false);oracle.request_sync(initial);drain(oracle)
	check(groups_of(batch)==groups_of(oracle),"new lexically earlier source reorders partially prepared bins correctly")
	batch.clear(false);oracle.clear(false)
	request(batch,initial,true);batch._prepare_step(1)
	var replacement:=initial.slice(1);replacement[1].free();replacement.remove_at(1)
	request(batch,replacement,true,["row_00004"]);drain(batch);oracle.request_sync(replacement,["row_00004"]);drain(oracle)
	check(groups_of(batch)==groups_of(oracle),"removal, freed node and changed exclusion supersede the old snapshot")
	request(batch,initial,true);batch._prepare_step(1);batch.release_sources([late]);check(batch._preparation.is_empty(),"editor source replacement cancels incremental collection")
	request(batch,initial,true);batch.clear(false);check(batch._preparation.is_empty(),"clear drops every retained root and cursor")
	var imported:=Node3D.new();imported.name="imported";host.add_child(imported)
	var components:Array=nodes.slice(0,2200);imported.set_meta("model_component_batch_sources",components)
	request(batch,[imported],true,["imported"]);batch._prepare_step(1)
	for i:int in 20:batch._prepare_step(1)
	var cursor:int=batch._preparation.component_cursor
	check(cursor>0 and cursor<components.size(),"runtime addition interrupts a partially expanded imported model")
	request(batch,[imported,late],true,["imported"])
	check(batch._preparation.component_cursor==cursor,"append preserves the component cursor")
	var actual:=collect(batch)
	oracle.request_sync([imported,late],["imported"]);var reference:=collect(oracle)
	check(actual.names==reference.names and actual.excluded==reference.excluded,"resumed model collection retains exact names and whole-model exclusions")
	batch.clear(false);oracle.clear(false)
	if batch.has_method("request_residency_sync"):check(reports[1].collected==4288 and reports[1].collected<reports[0].collected,"each runtime root is collected once across a publication burst")
	oracle.clear(false);oracle.free();batch.free();host.free()
	print("RESUMABLE_BATCH_COLLECTION ",JSON.stringify({"trials":reports,"failures":failures}));quit(1 if failures else 0)
