extends SceneTree
const House=preload("res://scripts/world3d/house_prefab.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var failures:=0
var output:=""
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--legacy":Retirement.background_decoded_release_enabled=false
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fill()->void:
	for i:int in 24:
		var surfaces:Array=[]
		for j:int in 256:
			var points:=PackedVector3Array();points.resize(2048);points.fill(Vector3(i,j,7))
			surfaces.append([points])
		var packet:Dictionary={"issuer":House._decode_issuer,"data":{"meshes":surfaces},"length":256*2048*12,"collision_faces":[],"encoded":"","geometry_keys":[],"local_bounds":{}}
		packet.make_read_only();House._decoded[str(i)]=packet;House._decoded_bytes+=packet.length
func run()->void:
	var rows:Array=[]
	for trial:int in 2:
		fill();var borrowed:Dictionary=House._decoded["0"]
		var ids:Dictionary={}
		for i:int in 24:ids[str(i)]=true
		var began:=Time.get_ticks_usec();House.evict_geometry(ids);var eviction:=Time.get_ticks_usec()-began
		check(House._decoded.is_empty() and House._decoded_bytes==0,"logical cache eviction is immediate")
		var service:Node=root.get_node("ResourceRetirement");service.set_process(false)
		var maximum:=0;var start:=Time.get_ticks_usec()
		while not service.pending.is_empty():
			began=Time.get_ticks_usec();var done:bool=service._advance(service.pending[0],1000)
			maximum=maxi(maximum,Time.get_ticks_usec()-began)
			if done:service._finish_front()
			else:await process_frame
		if Retirement.background_decoded_release_enabled:check(service.profile.get("geometry_last_thread_id",OS.get_main_thread_id())!=OS.get_main_thread_id(),"decoded data releases on worker")
		check(borrowed.is_read_only() and borrowed.data.meshes.size()==256 and borrowed.data.meshes[100][0][-1]==Vector3(0,100,7),"shared immutable borrower survives untouched")
		rows.append({"trial":trial,"logical_bytes":24*256*2048*12,"eviction_us":eviction,"main_max_us":maximum,"drain_wall_us":Time.get_ticks_usec()-start,"profile":service.profile.duplicate(true)})
		borrowed={};service.free()
	var report:={"failures":failures,"runs":rows}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DECODED_RETIREMENT_STRESS ",JSON.stringify(report));quit(1 if failures else 0)
