extends "res://tools/profile_white_native_asset.gd"
## Reproduce a resident large template being replaced after a stream revisit.
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
func alive(watch:WeakRef)->bool:return watch.get_ref()!=null
func reject_invalid(replacement:PackedScene,watch:WeakRef)->bool:
	return not Library.cache_packed(SOURCE,replacement,"invalid") and watch.get_ref()==Library._scenes[SOURCE]
func install_large(digest:String)->Dictionary:
	# Setup is outside the timed replacement. A synchronous helper also leaves
	# no suspended function-state owner of the old template in the test itself.
	var packet:Dictionary=Native.read(SOURCE,digest,"D:/code/rmmo_runtime",true);Drainer.synchronize_transfer()
	check(packet.get("hit",false),"real native largest building loaded")
	var packed:PackedScene=packet.packed;var watches:Array=[];var state:=packed.get_state()
	for i:int in state.get_node_count():
		for j:int in state.get_node_property_count(i):
			if state.get_node_property_name(i,j)==&"mesh":watches.append(weakref(state.get_node_property_value(i,j)))
	Library.cache_packed(SOURCE,packed,digest)
	return {"template":weakref(packed),"meshes":watches}
func run()->void:
	var output:="";var expect_sync:="--expect-sync" in OS.get_cmdline_user_args()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	check(DisplayServer.get_name()!="headless","real private desktop GPU")
	var digest:=FileAccess.get_sha256(SOURCE)
	var watches:Dictionary=install_large(digest)
	var node:=Node3D.new();var replacement:=PackedScene.new();replacement.pack(node);node.free()
	check(reject_invalid(replacement,watches.template),"rejected replacement keeps old template")
	var began:=Time.get_ticks_usec();check(Library.cache_packed(SOURCE,replacement,digest),"replacement accepted")
	var elapsed:=Time.get_ticks_usec()-began
	check(Library._scenes[SOURCE]==replacement,"new template is available immediately")
	check(not alive(watches.template) if expect_sync else alive(watches.template),"old owner follows expected synchronous or deferred lifetime")
	var service:Node=root.get_node_or_null(Retirement.NODE_NAME)
	if not expect_sync:
		check(service!=null and service.pending.size()==1,"one retirement ticket owns replaced template")
		Library.cache_packed(SOURCE,replacement,digest)
		check(service.pending.size()==1,"same template assignment adds no retirement work")
		var deadline:=Time.get_ticks_msec()+15000
		while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check(service.pending.is_empty() and service.known.is_empty(),"retirement drains all owners")
	Drainer.synchronize_transfer()
	check(not alive(watches.template) and watches.meshes.all(func(w:WeakRef):return not alive(w)),"old template and every old GPU mesh release")
	Library.evict_cached_scene(SOURCE)
	check(FileAccess.get_sha256(SOURCE)==digest,"formal source unchanged")
	var report:={"failures":failures,"replacement_us":elapsed,"meshes":watches.meshes.size(),"expected_sync":expect_sync,"retirement":service.profile if service!=null else {}}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TEMPLATE_REPLACEMENT ",elapsed," us failures=",failures);quit(1 if failures else 0)
