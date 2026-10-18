extends "res://tools/test_stream_index_retire.gd"
## Fixed ownership shape, identical resources and ABBA ordering. The control
## directory contains a separately archived revision, not a runtime fallback.
const Prep=preload("res://scripts/world3d/stream_index_preparation.gd")
const Nav=preload("res://scripts/world3d/world_navigation.gd")
var output:=""
func run()->void:
	var control:=""
	var candidate:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--control-root="):control=arg.trim_prefix("--control-root=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--candidate-root="):candidate=arg.trim_prefix("--candidate-root=")
	if control.is_empty():push_error("Explicit archived --control-root is required");quit(1);return
	var scripts:Array=[{"index":load(control.path_join("stream_index.gd")),"prep":load(control.path_join("stream_index_preparation.gd")),"nav":load(control.path_join("world_navigation.gd"))},{"index":Index,"prep":Prep,"nav":Nav}]
	if not candidate.is_empty():scripts[1]={"index":load(candidate.path_join("stream_index.gd")),"prep":load(candidate.path_join("stream_index_preparation.gd")),"nav":load(candidate.path_join("world_navigation.gd"))}
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,16,2)
	var incoming:Array=[];var resident:Array=[];var ids:Array=[]
	var record:Dictionary={"uuid":"guild","kind":"asset","building":{"id":"guild"},"surface_paint":[]}
	for i:int in 2151:
		var extra:Dictionary={"building":{"id":"guild_group%d"%(i%156),"floor":i%4},"rmmo_collision":"none" if i%7==0 else ""}
		var item:=spec("guild__part%d"%i,Vector2i(50,50),Vector2i(51,51),record,extra);item.mesh=mesh
		incoming.append(item);ids.append(item.uuid)
	for i:int in 2507:
		var item:=spec("keep%d"%i,Vector2i.ZERO,Vector2i.ZERO,{"kind":"asset"});item.mesh=mesh;resident.append(item)
	var library:Array=resident+incoming;var full:=Index.build(library)
	var report:Dictionary={"incoming":incoming.size(),"resident":resident.size(),"trials":[],"checks":0,"failures":0,"control":control}
	var expected:Dictionary={};var expected_nav:Dictionary={};var expected_retire:Dictionary={}
	for turn:int in 12:
		var variant:int=1 if turn%4 in [1,2] else 0;var impl:Dictionary=scripts[variant]
		var base:Array=copy_rows(resident);var values:Array=copy_rows(incoming)
		var data:Dictionary=impl.index.build(base)
		var prep:RefCounted=impl.prep.new();var start:=Time.get_ticks_usec();prep.begin_owned(values)
		while not prep.advance(0):pass
		var prepare_us:=Time.get_ticks_usec()-start
		check(prep.error.is_empty(),"complete fixed private projection")
		start=Time.get_ticks_usec();var result:Dictionary=impl.index.append(data,values,prep);var index_us:=Time.get_ticks_usec()-start
		var nav:Node=impl.nav.new();root.add_child(nav);nav.set_process(false);nav.set_physics_process(false);nav.streaming_geometry=true;nav.map=NavigationServer3D.map_create()
		check(nav.append_specs(base).ok,"same resident navigation catalogue")
		start=Time.get_ticks_usec();var added:Dictionary=nav.append_specs(values);var navigation_us:=Time.get_ticks_usec()-start
		var state:Dictionary={"specs":nav._specs.duplicate(),"ids":nav._spec_ids.duplicate(),"doors":nav._doors.duplicate(),"bounds":nav._bounds,"geometry":nav._spec_geometry.duplicate(),"users":nav._geometry_users.duplicate()}
		start=Time.get_ticks_usec();var retired:Dictionary=impl.index.validate_owned_retire(full,library,ids);var retirement_us:=Time.get_ticks_usec()-start
		check(result.ok and added.ok and retired.ok,"all transactions accept the complete namespace")
		if turn==0:expected=data;expected_nav=state;expected_retire=retired
		else:check(data==expected and state==expected_nav and retired==expected_retire,"every index/dependency, navigation owner, bound and retirement decision equals control")
		report.trials.append({"turn":turn,"variant":variant,"prepare_us":prepare_us,"index_us":index_us,"navigation_us":navigation_us,"retirement_us":retirement_us})
		print("HOTLOOP_TRANSACTION ",report.trials.back());prep.dispose();nav.free()
	expected={};expected_nav={}
	report.checks=checks;report.failures=failures
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STREAM_TRANSACTION_HOTLOOPS checks=",checks," failures=",failures);quit(1 if failures else 0)
func copy_rows(values:Array)->Array:
	var result:Array=[]
	for item:Dictionary in values:
		var copy:=item.duplicate()
		for field:String in Prep.DERIVED_FIELDS:copy.erase(field)
		result.append(copy)
	return result
