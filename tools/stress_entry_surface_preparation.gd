extends SceneTree
## Read-only entry geometry reproduction. No source or map writes; headless.
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Road=preload("res://scripts/world3d/native_road_preparation.gd")
const Bounds=preload("res://scripts/world3d/procedural_surface_bounds.gd")
var failures:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func original(record:Dictionary,context:Dictionary)->Array:
	if record.has("terrain_volume"):return preload("res://scripts/world3d/terrain_volume.gd").arrays(record)
	if record.has("terrain_mesh") and "--bulk-terrain" in OS.get_cmdline_user_args():return preload("res://tools/terrain_surface_bulk_probe.gd").arrays(record,context)
	if record.has("terrain_mesh"):return preload("res://scripts/world3d/terrain_surface.gd").arrays(record,context)
	if record.has("road_mesh"):return preload("res://scripts/world3d/road_surface.gd").arrays(record)
	if record.has("rock_bank"):return preload("res://scripts/world3d/rock_bank_mesh.gd").arrays(record)
	if preload("res://scripts/world3d/channel_mesh_preparation.gd").supports(record):return preload("res://scripts/world3d/channel_surface.gd").arrays(record)
	return []
func digest(value:Variant)->String:
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(var_to_bytes(value));return hash_.finish().hex_encode()
func run()->void:
	var path:="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	controls.discard_map_textures=true;controls.enable_white_materials()
	var root_path:=preload("res://scripts/world3d/map_paths.gd").external_root();var map_sha:=FileAccess.get_sha256(path)
	var directory:=Index.read_for_loading(path,root_path,map_sha,Index.Snapshot.RETAIN_LIMIT,Index.MAX_BYTES,4,true)
	if not directory.ok:
		# Code fingerprints may invalidate this derived directory. Rebuild
		# before timing; the authored map and resources are never edited.
		var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		var full:=Store.read_records(document.nodes[0].extras.rmmo_records,path,root_path,null,4,true)
		check(full.ok,"source records hydrate for derived directory rebuild")
		if not full.ok:quit(1);return
		directory=Index.build_for_loading(path,root_path,full.records,map_sha,4,Index.Snapshot.RETAIN_LIMIT,true,full.get("definition_sizes",{}))
	check(directory.ok,"entry directory is available before timed comparison")
	if not directory.ok:quit(1);return
	var plan:=preload("res://scripts/world3d/entry_plan.gd").create(Vector3(156,8.4,209))
	var selection:=Index.select(directory.index,[plan.core_clip])
	var restored:=Store.read_records(selection.extras.rmmo_records,path,root_path,null,4,true)
	check(restored.ok,"entry selection hydrates")
	if not restored.ok:quit(1);return
	var before:=digest(restored.records);var context:=preload("res://scripts/world3d/terrain_neighbors.gd").new()
	var began:=Time.get_ticks_usec();context.update(restored.records,true,true);var neighbor_us:=Time.get_ticks_usec()-began
	var jobs:Array=[];var counts:Dictionary={};var reference:Dictionary={};var input_sources:Dictionary={}
	for i:int in restored.records.size():
		var record:Dictionary=restored.records[i];var kind:=""
		for field:String in ["terrain_volume","terrain_mesh","road_mesh","rock_bank","channel_mesh"]:
			if record.has(field):kind=field;break
		if kind.is_empty():continue
		var compact:Dictionary=selection.extras.rmmo_records[i]
		input_sources[path.get_base_dir().path_join(compact.rmmo_ref.uri)]=FileAccess.get_sha256(path.get_base_dir().path_join(compact.rmmo_ref.uri))
		jobs.append({"record":record,"context":context.data.get(record.uuid,{}),"kind":kind,"sha":compact.rmmo_ref.sha256,"root":root_path})
		counts[kind]=int(counts.get(kind,0))+1
		var arrays:Array=preload("res://scripts/world3d/terrain_surface.gd").arrays(record,context.data.get(record.uuid,{})) if record.has("terrain_mesh") else original(record,context.data.get(record.uuid,{}));reference[record.uuid]={"sha":digest(arrays),"bounds":Bounds.bounds(arrays)}
	var trials:Array=[]
	for cached:bool in [false,true,true,false]:
		for width:int in [1,3,4,12]:
			var buckets:Array=[];var workers:Array[Thread]=[]
			for i:int in width:buckets.append([])
			for i:int in jobs.size():buckets[i%width].append(jobs[i])
			began=Time.get_ticks_usec()
			for bucket:Array in buckets:
				var task:=func()->Array:
					var result:Array=[]
					for job:Dictionary in bucket:
						var started:=Time.get_ticks_usec();var value:Dictionary={}
						if cached and "--entry-helper" in OS.get_cmdline_user_args():
							value=preload("res://scripts/world3d/entry_surface_preparation.gd").prepare(job.record,job.context,true,job.root,job.sha,true)
							value.cache_hit=value.road_cache_hit
						elif cached and job.kind=="road_mesh":value=Road.prepare(job.record,null,true,job.root,{},job.sha)
						else:value={"arrays":original(job.record,job.context),"cache_hit":false}
						var arrays:Array=value.arrays;var generated_us:=Time.get_ticks_usec()-started
						started=Time.get_ticks_usec();var bounds:AABB=value.get("bounds",AABB())
						if not value.has("bounds"):bounds=Bounds.bounds(arrays)
						result.append({"uuid":job.record.uuid,"kind":job.kind,"arrays":arrays,"bounds":bounds,"geometry_us":generated_us,"bounds_us":Time.get_ticks_usec()-started,"hit":value.get("cache_hit",false)})
					return result
				var worker:=Thread.new()
				check(worker.start(task)==OK,"entry worker starts")
				workers.append(worker)
			var results:Array=[]
			for worker:Thread in workers:results.append_array(worker.wait_to_finish())
			var elapsed:=Time.get_ticks_usec()-began;var types:Dictionary={};var exact:=results.size()==jobs.size()
			for row:Dictionary in results:
				exact=exact and digest(row.arrays)==reference[row.uuid].sha and row.bounds==reference[row.uuid].bounds
				if not types.has(row.kind):types[row.kind]={"geometry_us":0,"bounds_us":0,"hits":0,"jobs":0}
				types[row.kind].geometry_us+=row.geometry_us;types[row.kind].bounds_us+=row.bounds_us;types[row.kind].hits+=int(row.hit);types[row.kind].jobs+=1
			check(exact,"fixed complete entry geometry and exact bounds match at width "+str(width))
			trials.append({"cached":cached,"width":width,"elapsed_us":elapsed,"types":types,"jobs":jobs.size()})
	check(digest(restored.records)==before and FileAccess.get_sha256(path)==map_sha,"source records and map remain unchanged")
	for source:String in input_sources:check(FileAccess.get_sha256(source)==input_sources[source],"source resource remains unchanged")
	var report:={"failures":failures,"counts":counts,"neighbor_us":neighbor_us,"trials":trials,"map_sha256":map_sha,"source_sha256":input_sources}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ENTRY_SURFACE_STRESS ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
