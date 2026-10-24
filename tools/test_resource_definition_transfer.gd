extends "res://tools/test_map_resource_store.gd"
## Large private decoded definitions: independent instances need N-1 copies,
## while the last consumer can own the original allocation.
func run()->void:
	directory=Paths.cache_directory("definition_transfer_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	path=directory.path_join("map.gltf");DirAccess.make_dir_recursive_absolute(path+".resources")
	var nested:Array=[]
	for i:int in 12000:nested.append({"index":i,"nested":[i,i+1,i+2]})
	var points:=PackedVector3Array();points.resize(12000)
	for i:int in points.size():points[i]=Vector3(i,i%3,i%7)
	var compact:=put_resource({"kind":"box","payload":nested,"vertices":points})
	var rows:Array=[]
	for i:int in 4:
		var row:Dictionary=compact.duplicate(true);row.uuid="instance_%d"%i;row.rmmo_state={"building":{"id":row.uuid,"floor":i}};rows.append(row)
	var trials:Array=[]
	for count:int in [1,4,1,4]:
		var began:=Time.get_ticks_usec();var result:Dictionary=Store.read_records(rows.slice(0,count),path,Paths.external_root(),null,1,true)
		trials.append({"instances":count,"us":Time.get_ticks_usec()-began,"profile":result.get("read_profile",{})})
		check(result.ok and result.records.size()==count,"read complete private definition set")
		if not result.ok:break
		for i:int in count:
			check(result.records[i].payload==nested and result.records[i].vertices==points and result.records[i].uuid==rows[i].uuid and result.records[i].building.floor==i,"exact geometry, nested values and per-instance state")
		result.records[0].payload[0].nested[0]=-1;result.records[0].vertices[0]=Vector3.ONE;result.records[0].building.floor=-1
		check(nested[0].nested[0]==0 and points[0]==Vector3.ZERO and rows[0].rmmo_state.building.floor==0,"result never mutates caller containers")
		for i:int in range(1,count):check(result.records[i].payload[0].nested[0]==0 and result.records[i].vertices[0]==Vector3.ZERO,"hydrated consumers retain private packed and nested arrays")
		if "--baseline" not in OS.get_cmdline_user_args():check(result.read_profile.definition_transfers==1 and result.read_profile.definition_copies==count-1,"last consumer transfers private decoded ownership")
		if "--baseline" not in OS.get_cmdline_user_args():check(result.read_profile.compact_state_validation_skips==count,"trusted instance state is not recursively recertified")
	# Diagnostic cache outputs are already private copies; consuming one cannot
	# mutate a later authenticated cache hit either.
	var strict:Dictionary=Store.read_records(rows.slice(0,1),path,Paths.external_root(),null,1,false)
	strict.records[0].payload[0].nested[0]=-2
	var reread:Dictionary=Store.read_records(rows.slice(0,1),path,Paths.external_root(),null,1,false)
	check(reread.ok and reread.records[0].payload[0].nested[0]==0,"diagnostic read remains independent after transfer")
	var bad:Dictionary=rows[0].duplicate(true);bad.rmmo_state={"uuid":"replacement"}
	check(not Store.read_records([bad],path,Paths.external_root(),null,1,true).ok,"trusted state cannot override instance identity")
	bad=rows[0].duplicate(true);bad.rmmo_state={"event":{"unsupported":Vector3.ONE}}
	check(not Store.read_records([bad],path,Paths.external_root(),null,1,false).ok,"explicit diagnostics retain recursive JSON-state checks")
	DirAccess.remove_absolute(directory.path_join(compact.rmmo_ref.uri));DirAccess.remove_absolute(path+".resources");DirAccess.remove_absolute(directory)
	print("RESOURCE_DEFINITION_TRANSFER ",JSON.stringify({"trials":trials,"failures":failed}));quit(1 if failed else 0)
