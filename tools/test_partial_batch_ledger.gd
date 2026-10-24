extends "res://tools/test_incremental_batch_bins.gd"
## Strict exactly-once packing for unchanged per-bucket completed prefixes.
## Changed membership/order is checked against a full sorted rebuild instead.
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/"
var reports:Array=[]

func _initialize()->void:
	create_timer(90.0).timeout.connect(func():push_error("PARTIAL_BATCH_LEDGER watchdog timeout");quit(124))
	run.call_deferred()

func make_mesh(vertices:int=3,material:Material=null)->Mesh:
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var points:=PackedVector3Array();points.resize(vertices)
	for at:int in mini(vertices,3):points[at]=[Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD][at]
	arrays[Mesh.ARRAY_VERTEX]=points;mesh.surfaces=[arrays];mesh.bounds=AABB(Vector3.ZERO,Vector3.ONE)
	mesh.materials=[material if material!=null else StandardMaterial3D.new()]
	return mesh

func fixture(count:int=160)->Dictionary:
	var host:=Node3D.new();root.add_child(host)
	var mesh:=make_mesh();var nodes:Array=[]
	for at:int in count:nodes.append(building_source(host,mesh,"middle_%04d"%at,"house"))
	var batch:=CountingBatch.new();host.add_child(batch);batch.set_process(false)
	var oracle:=Batch.new();host.add_child(oracle);oracle.set_process(false)
	return {"host":host,"mesh":mesh,"nodes":nodes,"batch":batch,"oracle":oracle}

func until_bin(batch:Node)->void:
	var guard:=0
	while not batch._preparation.is_empty() and batch._preparation.phase!="bin" and guard<100000:
		batch._prepare_step(1);guard+=1
	check(not batch._preparation.is_empty() and batch._preparation.phase=="bin","arrive at incomplete bin stage")

func pack_more(batch:Node,count:int)->void:
	var target:int=batch.packed_source_visits+count;var guard:=0
	while not batch._preparation.is_empty() and batch._preparation.phase=="bin" and batch.packed_source_visits<target and guard<100000:
		batch._prepare_step(1);guard+=1
	check(not batch._preparation.is_empty() and batch._preparation.phase=="bin","pause within a partially packed bucket")

func snapshot(batch:Node)->Dictionary:
	var output:Dictionary={}
	for key:String in batch.groups:
		var group:Dictionary=batch.groups[key];var names:Array=[]
		for node:Node in group.members:names.append(str(node.name))
		output[key]={"members":names,"vertices":group.vertices,"keys":group.keys,"signature":group.signature,"origin":group.origin,"category":group.category,"merge_base":group.merge_base}
	return output

func compare(f:Dictionary,label:String)->void:
	drain(f.batch);f.oracle.request_sync(f.nodes);drain(f.oracle)
	check(snapshot(f.batch)==snapshot(f.oracle),label+" equals fresh sorted membership, signatures, limits and origins")
	var safe:=true
	for group:Dictionary in f.batch.groups.values():
		safe=safe and group.vertices<=Batch.Geometry.MAX_VERTICES
		for node:Node in group.members:safe=safe and is_instance_valid(node) and not node.is_queued_for_deletion()
	check(safe,label+" contains only live owners within MAX_VERTICES")

func finish(f:Dictionary,label:String)->void:
	reports.append({"case":label,"sources":f.nodes.size(),"prepared":f.batch.prepared_source_visits,"packed":f.batch.packed_source_visits,"last_generation_cpu_ms":f.batch.last_sync_ms,"max_slice_ms":f.batch.max_prepare_slice_ms,"reused_rows":f.batch.bin_ledger_reused_rows,"invalidated_buckets":f.batch.bin_ledger_invalidated_buckets,"invalidated_rows":f.batch.bin_ledger_invalidated_rows})
	f.batch.clear(false);f.oracle.clear(false);f.host.free()

func unchanged_prefix()->void:
	var f:=fixture();f.batch.request_residency_sync(f.nodes,[],true)
	for update:int in 8:
		until_bin(f.batch);pack_more(f.batch,8)
		var prefix:="aaa" if update%2==0 else "zzz"
		for part:int in 8:f.nodes.append(building_source(f.host,f.mesh,"%s_%02d_%02d"%[prefix,update,part],"other_%02d"%update))
		f.batch.request_residency_sync(f.nodes,[],true)
	compare(f,"unrelated out-of-order arrivals")
	check(f.batch.prepared_source_visits==f.nodes.size(),"unchanged sources are prepared exactly once")
	check(f.batch.packed_source_visits==f.nodes.size(),"unchanged partial buckets pack each source exactly once")
	finish(f,"unrelated_prefix")

func same_bucket_tail()->void:
	var f:=fixture();f.batch.request_residency_sync(f.nodes,[],true)
	for update:int in 8:
		until_bin(f.batch);pack_more(f.batch,8)
		for part:int in 8:f.nodes.append(building_source(f.host,f.mesh,"zzz_%02d_%02d"%[update,part],"house"))
		f.batch.request_residency_sync(f.nodes,[],true)
	compare(f,"same bucket later arrivals")
	check(f.batch.packed_source_visits==f.nodes.size(),"same-bucket arrivals after completed prefix pack each source exactly once")
	finish(f,"same_bucket_tail")

func reordered_limits()->void:
	var f:=fixture(0)
	for at:int in 4:f.nodes.append(building_source(f.host,make_mesh(20000 if at%2==0 else 22000,f.mesh.materials[0]),"middle_%02d"%at,"house"))
	f.batch.request_residency_sync(f.nodes,[],true);until_bin(f.batch);pack_more(f.batch,2)
	f.nodes.append(building_source(f.host,make_mesh(12000,f.mesh.materials[0]),"aaa_earlier","house"))
	f.batch.request_residency_sync(f.nodes,[],true);compare(f,"earlier source with vertex limits")
	check(f.batch.packed_source_visits>f.nodes.size(),"earlier source explicitly invalidates changed packing instead of false completed skip")
	check(f.batch.groups.size()==2,"earlier insertion changes both capped output memberships exactly")
	finish(f,"earlier_vertex_limits")

func completed_tail()->void:
	var f:=fixture(80);f.batch.request_residency_sync(f.nodes,[],true);drain(f.batch)
	var group:Dictionary=f.batch.groups.values()[0]
	var old_members:Array=group.members;var old_signature:Array=group.signature
	var old_generation:int=group.generation
	for at:int in 16:f.nodes.append(building_source(f.host,f.mesh,"zzz_%03d"%at,"house"))
	f.batch.request_residency_sync(f.nodes,[],true);until_bin(f.batch);pack_more(f.batch,8)
	check(old_members.size()==80 and old_signature.size()==80,"completed draw retains immutable membership/signature while later generation is packing")
	compare(f,"completed same-bucket append")
	check(f.batch.packed_source_visits==96,"completed prefix is not packed again for later same-bucket members")
	check(f.batch.groups.values()[0].generation!=old_generation,"changed completed membership publishes a new group generation")
	finish(f,"completed_tail")

func invalidation()->void:
	for change:String in ["pose","geometry","material","metadata"]:
		var f:=fixture(40);f.batch.request_residency_sync(f.nodes,[],true);until_bin(f.batch);pack_more(f.batch,12)
		var node:MeshInstance3D=f.nodes[0]
		match change:
			"pose":node.position.x=513
			"geometry":node.mesh=make_mesh(33000,f.mesh.materials[0])
			"material":
				var material:=StandardMaterial3D.new();material.albedo_color=Color(.2,.7,.1);node.material_override=material
			"metadata":node.get_meta("ground_batch_record").building.floor=1
		f.batch.invalidate_source(node);f.batch.request_residency_sync(f.nodes,[],true)
		compare(f,"explicit "+change+" invalidation")
		check(f.batch.packed_source_visits>40,"invalidated "+change+" generation cannot skip its old completed rows")
		finish(f,change)

func replacement_and_return()->void:
	var f:=fixture(40);f.batch.request_residency_sync(f.nodes,[],true);until_bin(f.batch);pack_more(f.batch,12)
	var other:=Node3D.new();f.host.add_child(other)
	var replacement:=building_source(other,make_mesh(30000,f.mesh.materials[0]),str(f.nodes[0].name),"house")
	f.nodes.append(replacement);f.batch.request_residency_sync(f.nodes,[],true)
	compare(f,"same UUID different source identity")
	check(f.batch.packed_source_visits>40,"same-name replacement revokes only valid completion ownership")
	finish(f,"replacement")
	f=fixture(40);f.batch.request_residency_sync(f.nodes,[],true);until_bin(f.batch);pack_more(f.batch,12)
	var id:=str(f.nodes[0].name);f.nodes[0].free();f.nodes.remove_at(0)
	f.batch.request_residency_sync(f.nodes,[],true);compare(f,"freed source and removed root")
	f.nodes.append(building_source(f.host,f.mesh,id,"house"));f.batch.request_residency_sync(f.nodes,[],true)
	compare(f,"same UUID returns with a new owner")
	f.batch.clear(false);check(f.batch._preparation.is_empty() and f.batch._residency_bins.is_empty(),"clear releases the generation ledger")
	f.batch.request_residency_sync(f.nodes,[],true);compare(f,"reload after clear")
	finish(f,"unload_return_clear")

func vanished_component()->void:
	for packed:bool in [true,false]:
		var f:=fixture(3);var components:Array=f.nodes.duplicate()
		var imported:=Node3D.new();imported.name="imported";f.host.add_child(imported)
		imported.set_meta("model_component_batch_sources",components);f.nodes=[imported]
		f.batch.request_residency_sync(f.nodes,[],true);until_bin(f.batch);pack_more(f.batch,2)
		components[0 if packed else 2].free()
		drain(f.batch)
		f.nodes.append(building_source(f.host,f.mesh,"zzz_after_free","house"))
		f.batch.request_residency_sync(f.nodes,[],true)
		compare(f,"vanished %s component with retained imported root"%("packed" if packed else "pending"))
		check(f.batch.groups.size()==1 and f.batch.groups.values()[0].members.size()==3,"dead component cannot suppress the surviving imported group on next append")
		var pending_count:=0
		for values:Dictionary in f.batch._residency_bins.get("bin_pending",{}).values():pending_count+=values.size()
		check(pending_count==0,"dead pending component leaves no unfinished ledger owner")
		finish(f,"vanished_packed" if packed else "vanished_pending")

func excluded_edit()->void:
	var f:=fixture(40);var selected:String=str(f.nodes[0].name)
	f.batch.request_sync(f.nodes,[selected])
	while not f.batch._preparation.is_empty() and f.batch._preparation.phase!="prepare":f.batch._prepare_step(1)
	for at:int in 8:f.batch._prepare_step(1)
	f.nodes[0].position.x=513;f.batch.invalidate_source(f.nodes[0])
	drain(f.batch);f.oracle.request_sync(f.nodes,[selected]);drain(f.oracle)
	check(snapshot(f.batch)==snapshot(f.oracle) and f.batch.groups.size()==1,"editing an excluded selection does not cancel the remaining pending editor sync")
	finish(f,"excluded_editor_edit")

func retired_singleton()->void:
	for kind:String in ["building","fortification"]:
		var f:=fixture(1);var source:Node=f.nodes[0]
		if kind=="fortification":
			var record:Dictionary=source.get_meta("ground_batch_record");record.erase("building");record.fortification={}
		var imported:=Node3D.new();f.host.add_child(imported)
		imported.set_meta("model_component_batch_sources",[source]);f.nodes=[imported]
		f.batch.request_residency_sync(f.nodes,[],true);until_bin(f.batch);pack_more(f.batch,1)
		# The immutable runtime owner revokes membership before destroying a
		# source, exactly like WorldStream. Arbitrary unannounced mutation is
		# outside that contract and must not add validation to every hot append.
		f.batch.retire_sources([source]);source.free()
		check(f.batch._preparation.is_empty() and f.batch._residency_bins.is_empty(),"singleton retirement revokes private and completed ledger owners before free")
		for at:int in 2:
			var node:=building_source(f.host,f.mesh,"zzz_single_%d"%at,"house")
			if kind=="fortification":
				var record:Dictionary=node.get_meta("ground_batch_record");record.erase("building");record.fortification={}
			f.nodes.append(node)
		f.batch.request_residency_sync(f.nodes,[],true);compare(f,"retired "+kind+" singleton with retained root")
		check(f.batch.groups.size()==1 and f.batch.groups.values()[0].members.size()==2,"retired "+kind+" singleton cannot suppress returned live members")
		finish(f,"retired_singleton_"+kind)

func run()->void:
	if "--legacy-ledger" in OS.get_cmdline_user_args():Batch.resumable_bin_ledger_enabled=false
	if "--singleton-only" in OS.get_cmdline_user_args():retired_singleton()
	else:unchanged_prefix();same_bucket_tail();reordered_limits();completed_tail();invalidation();replacement_and_return();vanished_component();excluded_edit();retired_singleton()
	var label:="candidate"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):label=argument.trim_prefix("--label=").validate_filename()
	var result:={"label":label,"failures":failures,"reports":reports,"source_sha256":FileAccess.get_sha256("res://scripts/world3d/ground_batcher.gd")}
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+"partial_batch_ledger_"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("PARTIAL_BATCH_LEDGER ",JSON.stringify(result));quit(1 if failures else 0)
