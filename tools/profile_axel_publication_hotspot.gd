extends "res://tools/profile_axel_white_streaming.gd"
## Repeat the real largest-building index/nav transaction for native sampling.
## Source loading and cursor preparation are separately labelled; debugger wall
## times are attribution evidence, never release-engine performance results.
const Index=preload("res://scripts/world3d/stream_index.gd")
const Preparation=preload("res://scripts/world3d/stream_index_preparation.gd")
const Nav=preload("res://scripts/world3d/world_navigation.gd")
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_publication_hotspot.gd"]=FileAccess.get_sha256("res://tools/profile_axel_publication_hotspot.gd")
	return result
func copy_specs(values:Array)->Array:
	var result:Array=[]
	for value:Dictionary in values:
		var copy:=value.duplicate()
		for field:String in Preparation.DERIVED_FIELDS:copy.erase(field)
		result.append(copy)
	return result
func traverse()->void:
	await super.traverse()
	var incoming:Array=[];var resident:Array=[];var record_ids:Dictionary={};var record_shapes:Dictionary={}
	for spec:Dictionary in mesh_map.get_meta("stream_library",[]):
		if str(spec.uuid).begins_with("obj_1033__"):
			incoming.append(spec)
			var record:Dictionary=spec.get("ground_batch_record",{})
			record_ids[str(record.get("uuid",""))]=true
			for key:String in record:record_shapes[key]=int(record_shapes.get(key,0))+1
		else:resident.append(spec)
	check(incoming.size()==2151,"diagnostic repeats the actual complete largest-building namespace")
	if incoming.size()!=2151:return
	report.publication_hotspot={"incoming":incoming.size(),"record_uuid_count":record_ids.size(),"record_fields":record_shapes,"trials":[]}
	print("PUBLICATION_HOTSPOT_BEGIN")
	var repeats:=64
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--hotspot-repeats="):repeats=clampi(arg.trim_prefix("--hotspot-repeats=").to_int(),8,256)
	for turn:int in repeats:
		phase="hotspot_preparation";print("WHITE_TRAVERSAL hotspot_preparation ",turn)
		var base:=copy_specs(resident);var values:=copy_specs(incoming);var index:Dictionary=Index.build(base)
		var prep:=Preparation.new();prep.begin_owned(values)
		while not prep.advance(2000):await process_frame
		var nav:=Nav.new();root.add_child(nav);nav.set_process(false);nav.set_physics_process(false)
		nav.streaming_geometry=true;nav.map=NavigationServer3D.map_create()
		check(nav.append_specs(base).ok,"resident navigation context prepared %d"%turn)
		phase="hotspot_commit";print("WHITE_TRAVERSAL hotspot_commit ",turn)
		var began:=Time.get_ticks_usec();var result:Dictionary=Index.append(index,values,prep);var index_us:=Time.get_ticks_usec()-began
		began=Time.get_ticks_usec();var appended:Dictionary=nav.append_specs(values);var nav_us:=Time.get_ticks_usec()-began
		check(result.ok and appended.ok,"real prepared index and navigation publish %d"%turn)
		report.publication_hotspot.trials.append({"index_us":index_us,"navigation_us":nav_us})
		phase="hotspot_retirement";print("WHITE_TRAVERSAL hotspot_retirement ",turn)
		prep.dispose();nav.free();await process_frame
