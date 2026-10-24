extends "res://tools/test_private_publication_packet.gd"
func binding_snapshot(source:Array)->Dictionary:
	var result:Dictionary={}
	for spec:Dictionary in source:
		var supports:Array=[]
		for tile:Dictionary in spec.get("render_supports",[]):supports.append(tile.uuid)
		result[spec.uuid]=[spec.get("render_bounds",{}).duplicate(),supports]
	return result
func ground(mesh:Mesh)->Dictionary:
	var spec:=row("ground",mesh);spec.chunk_min=Vector2i.ZERO;spec.chunk_max=Vector2i(2,2)
	spec.ground_batch_record={"uuid":"ground","kind":"box","surface_id":"ground","size":[32,1,32]}
	return spec
func run()->void:
	var mesh:=CountedMesh.new();var trials:Array=[]
	for repeat:int in 3:
		var initial:=ground(mesh);var index:=Index.build([initial]);var source:=values(mesh)
		var prep:=Prep.new();prep.begin_runtime_owned(source)
		while not prep.advance(500):pass
		var old_bindings:Array=[]
		for spec:Dictionary in source:old_bindings.append(spec.render_supports)
		var began:=Time.get_ticks_usec();var result:=Index.append(index,source,prep);var commit_us:=Time.get_ticks_usec()-began
		check(result.ok,"prepared private building appends with existing terrain")
		var expected:=values(mesh);var reference:=Index.build([ground(mesh)])
		check(Index.append(reference,expected).ok and binding_snapshot(source)==binding_snapshot(expected),"all member bounds and ordered supports match ordinary append")
		var changed:=0
		for i:int in source.size():
			if not is_same(old_bindings[i],source[i].render_supports):changed+=1
		check(changed==0,"new group publication does not rebind every member's private shared support array")
		check(source[0].render_supports.size()==1 and is_same(source[0].render_supports[0],initial),"support retains the original resident terrain owner")
		check(initial.render_dependents.size()==1 and is_same(initial.render_dependents[0],source[0].render_bounds),"reverse dependency points to the shared live building bounds")
		var affected:Array=[]
		for spec:Dictionary in result.affected_existing_specs:affected.append(spec.uuid)
		check(affected==["ground"],"affected existing set excludes all new building members")
		trials.append({"commit_us":commit_us,"member_support_rebindings":changed,"specs":source.size()});prep.dispose()
	print("PRIVATE_GROUP_BINDING ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
