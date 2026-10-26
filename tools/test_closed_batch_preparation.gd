extends "res://tools/test_partial_batch_ledger.gd"
## Unit closure comes from index membership, never the currently arrived tail.
func register(f:Dictionary,declared:Array)->void:
	var by_id:Dictionary={};var houses:Dictionary={}
	for node:Node in declared:
		var owner:String=node.get_meta("ground_batch_record").building.id
		var spec:={"uuid":str(node.name),"render_building":owner}
		by_id[spec.uuid]=spec
		if not houses.has(owner):houses[owner]=[]
		houses[owner].append(spec)
	f.host.set_meta("stream_by_id",by_id);f.host.set_meta("stream_building_groups",houses)

func compare(f:Dictionary,label:String)->void:
	drain(f.batch);f.oracle.request_sync(f.nodes);drain(f.oracle)
	var actual:=snapshot(f.batch);var expected:=snapshot(f.oracle)
	check(actual==expected,label+" equals full sorted membership, signatures, limits and origins")
	if actual!=expected:print("MEMBERSHIP_DIFFERENCE ",var_to_str(actual)," EXPECTED ",var_to_str(expected))

func run()->void:
	Batch.closed_building_preparation_enabled=true
	var f:=fixture(0)
	for house:int in 8:
		for part:int in 32:f.nodes.append(building_source(f.host,f.mesh,"house_%02d_%02d"%[house,part],"h%d"%house))
	register(f,f.nodes)
	f.batch.request_residency_sync(f.nodes,[],true)
	while f.batch.groups.is_empty() and not f.batch._preparation.is_empty():f.batch._prepare_step(1)
	check(not f.batch.groups.is_empty() and f.batch.prepared_source_visits<f.nodes.size(),"first complete unit reaches production before unrelated descriptors finish")
	compare(f,"closed unit pipeline")
	check(f.batch.prepared_source_visits==256 and f.batch.packed_source_visits==256,"each immutable source prepared and packed once")
	var raw_only:=true
	for group:Dictionary in f.batch._residency_bins.desired.values():raw_only=raw_only and not group.has("generation") and not group.has("exit_callback")
	check(raw_only,"early publication keeps raw ledger free of renderer and callback ownership")
	var early_before:int=f.batch.closed_unit_groups_admitted
	f.nodes[0].material_override=StandardMaterial3D.new();f.nodes[0].material_override.albedo_color=Color.RED
	f.batch.invalidate_source(f.nodes[0]);f.oracle.invalidate_source(f.nodes[0]);f.batch.request_residency_sync(f.nodes,[],true)
	compare(f,"material split of an existing drawing")
	check(f.batch.closed_unit_groups_admitted==early_before+1,"only explicitly invalidated house admits a replacement; existing drawings stay intact")
	finish(f,"closed_units")
	f=fixture(0)
	var declared:Array=[]
	for house:int in 2:
		for part:int in 32:declared.append(building_source(f.host,f.mesh,"house_%02d_%02d"%[house,part],"h%d"%house))
	register(f,declared);f.nodes=declared.slice(0,63)
	f.batch.request_residency_sync(f.nodes,[],true)
	while f.batch.groups.is_empty() and not f.batch._preparation.is_empty():f.batch._prepare_step(1)
	check(f.batch.groups.size()==1 and f.batch.groups.values()[0].members.size()==32,"complete house advances while incomplete declared house cannot publish early")
	f.nodes.append(declared[63]);f.batch.request_residency_sync(f.nodes,[],true)
	compare(f,"later completion during unit preparation")
	check(f.batch.prepared_source_visits==64 and f.batch.packed_source_visits==64,"unrelated arrival preserves exactly-once descriptor and packing work")
	# Membership replacement invalidates closure even if the old nodes remain.
	f.batch.clear(false);register(f,f.nodes)
	f.batch.request_residency_sync(f.nodes,[],true)
	while f.batch._preparation.get("phase","")!="bin":f.batch._prepare_step(1)
	f.host.set_meta("stream_building_groups",{})
	while f.batch._preparation.get("phase","") in ["bin","unit_add"]:f.batch._prepare_step(1)
	check(f.batch.groups.is_empty(),"replaced index revokes early publication before admission")
	f.batch.release_sources([f.nodes[0]])
	f.nodes[0].free();f.nodes.remove_at(0);register(f,f.nodes)
	f.batch.request_residency_sync(f.nodes,[],true)
	compare(f,"removal during unit preparation")
	finish(f,"arrival_and_invalidation")
	print("CLOSED_BATCH_PREPARATION ",JSON.stringify({"failures":failures,"reports":reports}));quit(1 if failures else 0)
