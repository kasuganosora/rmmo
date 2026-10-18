extends "res://tools/profile_axel_white_streaming.gd"
const Index=preload("res://scripts/world3d/stream_index.gd")
const Preparation=preload("res://scripts/world3d/stream_index_preparation.gd")
const Nav=preload("res://scripts/world3d/world_navigation.gd")
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_publication_transaction.gd"]=FileAccess.get_sha256("res://tools/profile_axel_publication_transaction.gd")
	return result
func copy_specs(values:Array)->Array:
	var copies:Array=[]
	for value:Dictionary in values:
		var copy:Dictionary=value.duplicate()
		for field:String in Preparation.DERIVED_FIELDS:copy.erase(field)
		copies.append(copy)
	return copies
func nav_state(nav:Node)->Dictionary:
	return {"specs":nav._specs.duplicate(),"ids":nav._spec_ids.duplicate(),"doors":nav._doors.duplicate(),"bounds":nav._bounds,"has_bounds":nav._has_bounds,"geometry":nav._spec_geometry.duplicate(),"users":nav._geometry_users.duplicate()}
func traverse()->void:
	await super.traverse()
	var repeats:=8
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--transaction-repeats="):repeats=clampi(arg.trim_prefix("--transaction-repeats=").to_int(),8,256)
	var incoming:Array=[];var resident:Array=[]
	for spec:Dictionary in mesh_map.get_meta("stream_library",[]):
		if str(spec.uuid).begins_with("obj_1033__"):incoming.append(spec)
		else:resident.append(spec)
	check(incoming.size()==2151,"transaction benchmark uses all 2151 actual largest-building parts")
	if incoming.size()!=2151:return
	var data:Dictionary={}
	for key:StringName in mesh_map.get_meta_list():
		if str(key).begins_with("stream_"):data[str(key)]=mesh_map.get_meta(key)
	var ids:Array=[]
	for spec:Dictionary in incoming:ids.append(spec.uuid)
	var old_workers:=Index.retirement_schema_workers
	var expected_retire:Dictionary={}
	report.retirement_transaction={"specs":data.stream_library.size(),"selected":ids.size(),"trials":[]}
	for turn:int in repeats:
		var workers:=4 if turn%4 in [1,2] else 0
		Index.retirement_schema_workers=workers
		var start:=Time.get_ticks_usec();var result:Dictionary=Index.validate_owned_retire(data,data.stream_library,ids);var elapsed:=Time.get_ticks_usec()-start
		if turn==0:expected_retire=result
		check(result==expected_retire and result.ok,"same real ownership retirement decision for workers=%d"%workers)
		report.retirement_transaction.trials.append({"workers":workers,"us":elapsed})
		print("RETIREMENT_TRANSACTION ",report.retirement_transaction.trials.back())
	Index.retirement_schema_workers=old_workers
	var schema:RefCounted=preload("res://scripts/world3d/retirement_schema_preparation.gd").new()
	var schema_started:=Time.get_ticks_usec();schema.begin(data.stream_library)
	while not schema.advance(1000):pass
	report.retirement_prepared={"prepare_us":Time.get_ticks_usec()-schema_started,"profile":schema.profile.duplicate(),"trials":[]}
	Index.retirement_schema_workers=4
	for turn:int in 8:
		var prepared_schema:=turn%4 in [1,2]
		var start:=Time.get_ticks_usec()
		var result:Dictionary=Index._owned_retire_plan(data,data.stream_library,ids,false,schema if prepared_schema else null)
		var elapsed:=Time.get_ticks_usec()-start
		check(result==expected_retire,"prepared/unprepared real retirement preserves complete validation %d"%turn)
		report.retirement_prepared.trials.append({"prepared":prepared_schema,"us":elapsed})
		print("RETIREMENT_PREPARED ",report.retirement_prepared.trials.back())
	Index.retirement_schema_workers=old_workers;schema=null
	var saved:bool=Preparation.native_snapshot_validation_enabled
	var expected:Dictionary={};var expected_nav:Dictionary={}
	report.publication_transaction={"incoming":incoming.size(),"resident":resident.size(),"trials":[],"note":"Fixed actual white-map Mesh/author inputs; isolated index/navigation copies. ABBA; cloning, preparation, base build and equality checks excluded. No gameplay frame timing claim."}
	for turn:int in repeats:
		var fast:=turn%4 in [1,2] and "--ordinary-validation-only" not in OS.get_cmdline_user_args()
		Preparation.native_snapshot_validation_enabled=fast
		var base:=copy_specs(resident);var values:=copy_specs(incoming)
		var index:Dictionary=Index.build(base)
		var prepare_start:=Time.get_ticks_usec()
		var prep:=Preparation.new();prep.begin_owned(values)
		while not prep.advance(1000):pass
		var prepare_us:=Time.get_ticks_usec()-prepare_start
		if fast:check(prep.valid_owned_snapshot(values),"native snapshot exactly covers the actual building")
		check(prep.error.is_empty(),"actual private fragment prepared for trial %d"%turn)
		var nav:=Nav.new();root.add_child(nav);nav.set_process(false);nav.set_physics_process(false)
		nav.streaming_geometry=true;nav.map=NavigationServer3D.map_create()
		check(nav.append_specs(base).ok,"private navigation accepts the resident context")
		var start:=Time.get_ticks_usec();var result:Dictionary=Index.append(index,values,prep);var index_us:=Time.get_ticks_usec()-start
		start=Time.get_ticks_usec();var nav_result:Dictionary=nav.append_specs(values);var nav_us:=Time.get_ticks_usec()-start
		check(result.ok and nav_result.ok,"actual index and navigation transaction succeeds %d"%turn)
		var snapshot:=nav_state(nav)
		if turn==0:expected=index;expected_nav=snapshot
		else:check(index==expected and snapshot==expected_nav,"complete indexes, dependencies and navigation state equal the serial reference %d"%turn)
		report.publication_transaction.trials.append({"turn":turn,"native_snapshot":fast,"index_us":index_us,"navigation_us":nav_us,"prepare_us":prepare_us})
		print("PUBLICATION_TRANSACTION ",report.publication_transaction.trials.back())
		var dispose_start:=Time.get_ticks_usec();prep.dispose();var dispose_us:=Time.get_ticks_usec()-dispose_start
		report.publication_transaction.trials.back().dispose_us=dispose_us
		nav.free();Preparation.native_snapshot_validation_enabled=saved
		await process_frame
	Preparation.native_snapshot_validation_enabled=saved
	expected={};expected_nav={}
