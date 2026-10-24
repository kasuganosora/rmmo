extends SceneTree
## Diagnostic magnitudes, not a visual quality threshold or acceptance test.
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
func _initialize()->void:run.call_deferred()
func meshes(packed:PackedScene)->Array:
	var result:Array=[];var seen:Dictionary={};var state:=packed.get_state()
	for i:int in state.get_node_count():
		for j:int in state.get_node_property_count(i):
			if state.get_node_property_name(i,j)!=&"mesh":continue
			var value:Variant=state.get_node_property_value(i,j)
			if not value is ArrayMesh or seen.has(value.get_instance_id()):continue
			seen[value.get_instance_id()]=true;result.append(value)
	return result
func run()->void:
	var previous:="";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--previous="):previous=arg.trim_prefix("--previous=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(previous)).models[0]
	var current:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(old.index))
	var before:=meshes(ResourceLoader.load(old.product,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP))
	var after:=meshes(ResourceLoader.load(Native.directory("D:/code/rmmo_runtime").path_join(current.payload_sha+".scn"),"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP))
	var report:={"old_sha":old.manifest.payload_sha,"new_sha":current.payload_sha,"meshes":before.size(),"channels":{},"lod_changes":0,"face_changes":0,"bounds_changes":0,"errors":[]}
	if before.size()!=after.size():report.errors.append("mesh count")
	for i:int in mini(before.size(),after.size()):
		var a:Dictionary=before[i].get_meta(Native.META);var b:Dictionary=after[i].get_meta(Native.META)
		report.lod_changes+=int(var_to_bytes(a.lods)!=var_to_bytes(b.lods));report.face_changes+=int(a.faces!=b.faces)
		report.bounds_changes+=int(before[i].get_aabb()!=after[i].get_aabb())
		if a.surfaces.size()!=b.surfaces.size():report.errors.append("surface count "+str(i));continue
		for slot:int in a.surfaces.size():
			for channel:int in Mesh.ARRAY_MAX:
				var left:Variant=a.surfaces[slot][channel];var right:Variant=b.surfaces[slot][channel]
				if var_to_bytes(left)==var_to_bytes(right):continue
				var key:=str(channel)
				if not report.channels.has(key):report.channels[key]={"surfaces":0,"values":0,"max_abs":0.}
				var row:Dictionary=report.channels[key];row.surfaces+=1
				if typeof(left)!=typeof(right) or left==null or left.size()!=right.size():report.errors.append("channel shape "+str([i,slot,channel]));continue
				for at:int in left.size():
					if left[at]==right[at]:continue
					row.values+=1
					var delta:Variant=left[at]-right[at]
					if delta is Vector3:row.max_abs=maxf(row.max_abs,maxf(absf(delta.x),maxf(absf(delta.y),absf(delta.z))))
					elif delta is Vector2:row.max_abs=maxf(row.max_abs,maxf(absf(delta.x),absf(delta.y)))
					elif delta is float or delta is int:row.max_abs=maxf(row.max_abs,absf(delta))
					else:report.errors.append("unmeasured delta type "+str(channel));break
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("NATIVE_CHANNEL_DELTA ",JSON.stringify(report));quit(1 if not report.errors.is_empty() else 0)
