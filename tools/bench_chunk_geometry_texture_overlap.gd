extends SceneTree
## CPU-only feasibility probe. Does not change the production scheduler or
## create nested workers there. Two fixed workers maximum, the same actual
## map group and unique texture plan in both arms, complete join before reuse.
const Chunk=preload("res://scripts/world3d/chunk_reference_preparation.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Textures=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const GROUPS=["building:building_883dd20afc1eaef90960","building:building_061ac981f7e8922e09fa"]
const BUDGET=1024*1024*1024
var report:Dictionary={"samples":[],"failures":[],"scope":"CPU feasibility only; no GPU, no shared-pool residency, no full-map speedup claim; disk/OS caches retained, decoded prefab cache cleared before each sample"}
var output:String=""

func _initialize()->void:run.call_deferred()

func _geometry(index:Dictionary,entries:Array,path:String,content_root:String,proof:RefCounted)->Dictionary:
	var began:=Time.get_ticks_usec()
	var packet:=Chunk.prepare(index,entries,path,content_root,null,proof,{}, {},0,true)
	return {"start_us":began,"end_us":Time.get_ticks_usec(),"packet":packet}

func _pixels(requested:Dictionary,plan:Dictionary,content_root:String)->Dictionary:
	var began:=Time.get_ticks_usec()
	var packet:=Textures.prepare(requested,plan,content_root,null,true,{},true)
	return {"start_us":began,"end_us":Time.get_ticks_usec(),"packet":packet}

func _serial(index:Dictionary,entries:Array,path:String,content_root:String,proof:RefCounted,requested:Dictionary,plan:Dictionary)->Dictionary:
	return {"geometry":_geometry(index,entries,path,content_root,proof),"pixels":_pixels(requested,plan,content_root)}

func _signature(result:Dictionary)->Dictionary:
	var packet:Dictionary=result.geometry.packet
	var geo:=HashingContext.new();geo.start(HashingContext.HASH_SHA256)
	for key:String in ["records","record_indices","surface_arrays","surface_bounds","terrain_contexts"]:
		geo.update(var_to_bytes(packet.get(key)))
	var prefab_keys:Array=packet.get("prefab_cpu",{}).keys();prefab_keys.sort()
	for key:String in prefab_keys:
		var prepared:Dictionary=packet.prefab_cpu[key]
		for field:String in ["data","collision_faces","geometry_keys"]:geo.update(var_to_bytes(prepared.get(field)))
	var pixels:=HashingContext.new();pixels.start(HashingContext.HASH_SHA256)
	var images:Dictionary=result.pixels.packet.get("images",{})
	var keys:Array=images.keys();keys.sort();var total:=0
	for key:String in keys:
		var item:Image=images[key];var bytes:=item.get_data();total+=bytes.size()
		pixels.update(var_to_bytes([key,item.get_width(),item.get_height(),item.get_format(),item.has_mipmaps(),item.get_meta("runtime_normal_xy",false),item.get_meta("runtime_upload_has_alpha",false)]))
		pixels.update(bytes)
	return {"geometry_sha256":geo.finish().hex_encode(),"pixels_sha256":pixels.finish().hex_encode(),"records":packet.get("records",[]).size(),"prefab_definitions":prefab_keys.size(),"images":images.size(),"image_bytes":total}

func _save()->void:
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty() or FileAccess.file_exists(output):
		push_error("Use a new --output path");quit(1);return
	var content_root:=Paths.external_root()
	var path:=content_root.path_join("packs/default/maps/axel_town/map.gltf")
	var original_sha:=FileAccess.get_sha256(path)
	var loaded:=Index.read_for_loading(path,content_root,"",Index.Snapshot.RETAIN_LIMIT,Index.MAX_BYTES,1,true)
	if not loaded.ok:
		report.failures.append(loaded.reason);_save();quit(1);return
	var index:Dictionary=loaded.index
	for group_id:String in GROUPS:
		if not index.groups.has(group_id):report.failures.append("Missing group "+group_id);continue
		var entries:Array=[];var requested:Dictionary={};var geometry_budget:=0
		for at:int in index.groups[group_id].members:
			var row:Dictionary=index.rows[at]
			entries.append({"record_index":at,"compact_record":index.extras.rmmo_records[at],"bounds":index.groups[group_id].bounds,"group_id":group_id,"asset_path":row.asset_path})
			requested.merge(row.get("prefab_textures",{}),true);geometry_budget+=int(row.get("memory_bytes",0))
		var plan:=Textures.estimate(requested,content_root)
		if plan.rows.is_empty() or int(plan.estimated_bytes)+geometry_budget>BUDGET:
			report.failures.append("Missing pixels or combined reservation exceeds 1 GiB: "+group_id);continue
		var expected:Dictionary={}
		for arm:String in ["A1","B1","B2","A2","A3","B3","B4","A4"]:
			# No active job owns the cache here. This excludes decode-cache warmup
			# as an explanation for the second arm's result.
			Prefab._decode_mutex.lock();Prefab._decoded.clear();Prefab._decoded_bytes=0;Prefab._decode_mutex.unlock()
			var first:=Thread.new();var second:=Thread.new();var result:Dictionary={}
			var began:=Time.get_ticks_usec()
			if arm.begins_with("A"):
				if first.start(_serial.bind(index,entries,path,content_root,loaded.proof,requested,plan))!=OK:report.failures.append("Thread start failed");break
				result=first.wait_to_finish()
			else:
				if first.start(_geometry.bind(index,entries,path,content_root,loaded.proof))!=OK:report.failures.append("Geometry thread start failed");break
				if second.start(_pixels.bind(requested,plan,content_root))!=OK:
					first.wait_to_finish();report.failures.append("Pixels thread start failed");break
				result={"geometry":first.wait_to_finish(),"pixels":second.wait_to_finish()}
			var elapsed:=Time.get_ticks_usec()-began
			if not result.geometry.packet.error.is_empty() or not result.pixels.packet.error.is_empty():
				report.failures.append([group_id,arm,result.geometry.packet.error,result.pixels.packet.error]);_save();break
			var signature:=_signature(result)
			if expected.is_empty():expected=signature
			if signature!=expected:report.failures.append("Geometry or image output/work mismatch: "+group_id+" "+arm)
			var row:Dictionary={"group":group_id,"arm":arm,"elapsed_us":elapsed,"geometry_us":result.geometry.end_us-result.geometry.start_us,"pixels_us":result.pixels.end_us-result.pixels.start_us,"overlap_us":maxi(0,mini(result.geometry.end_us,result.pixels.end_us)-maxi(result.geometry.start_us,result.pixels.start_us)),"signature":signature,"pixel_profile":result.pixels.packet.profile,"read_profile":result.geometry.packet.read_profile,"combined_reservation":geometry_budget+int(plan.estimated_bytes)}
			report.samples.append(row);_save();print("CHUNK_OVERLAP ",JSON.stringify({"group":group_id,"arm":arm,"elapsed_us":elapsed,"geometry_us":row.geometry_us,"pixels_us":row.pixels_us,"overlap_us":row.overlap_us,"work":signature}))
	if FileAccess.get_sha256(path)!=original_sha:report.failures.append("Map changed")
	report.map_sha256=original_sha;_save();print("CHUNK_OVERLAP_COMPLETE failures=",report.failures);quit(0 if report.failures.is_empty() else 1)
