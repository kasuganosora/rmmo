extends SceneTree
## Offline, reviewable migration. Default prepares only private artefacts.
## --review requires the private desktop GPU runner. --publish is explicit,
## consumes the reviewed plan, and uses the document's atomic/conflict save.
const MAP="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/bridge_lod_update_20261011"
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Lod=preload("res://scripts/world3d/bridge_lod_preparation.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Structure=preload("res://scripts/world3d/structure_prefab.gd")
const GPU=preload("res://tools/bridge_lod_assertions.gd")
var map_path:=MAP
var out_path:=OUT
var failures:Array=[]

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	if not ok:failures.append(label);push_error(label)
	return ok
func write_json(name:String,value:Variant)->bool:
	var file:=FileAccess.open(out_path.path_join(name),FileAccess.WRITE)
	if not check(file!=null,"Open artefact "+name):return false
	file.store_string(JSON.stringify(value,"  "));file.close();return true
func read_json(name:String)->Dictionary:
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(out_path.path_join(name)))
	return value if value is Dictionary else {}
func exact(a:Variant,b:Variant)->bool:
	# JSON normalizes numeric types; compare numeric values without tolerance.
	if (a is int or a is float) and (b is int or b is float):return a==b
	if typeof(a)!=typeof(b):return false
	if a is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not exact(a[key],b[key]):return false
		return true
	if a is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not exact(a[i],b[i]):return false
		return true
	return a==b
func source()->Dictionary:
	if not check(Paths.allowed(map_path),"Map is inside the content root"):return {}
	var sha:=FileAccess.get_sha256(map_path)
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var index:int=Cursor.native_root(data)
	if not check(index>=0,"Current native reference map"):return {}
	var extras:Dictionary=data.nodes[index].extras
	var ids:Dictionary={}
	for edge:Dictionary in extras.get("editor_layout",{}).get("roads",{}).get("edges",[]):
		if edge.has("stone_bridge"):ids[edge.stone_bridge.id]=true
	var chosen:Array=[];var untouched:Array=[]
	for record:Dictionary in extras.rmmo_records:
		if ids.has(record.uuid):chosen.append(record)
		else:untouched.append(record)
	if not check(chosen.size()==ids.size() and not chosen.is_empty(),"Every road-bound bridge has an authoritative record"):return {}
	var loaded:=Store.read_records(chosen,map_path,Paths.external_root())
	if not check(loaded.ok,"Bridge resource bytes/SHA/envelopes valid"):return {}
	if not check(FileAccess.get_sha256(map_path)==sha,"Map unchanged during read"):return {}
	return {"sha256":sha,"records":loaded.records,"compact":chosen,"non_bridge_compact":untouched,"record_count":extras.rmmo_records.size()}
func collision_hash(mesh:Dictionary)->String:
	var cpu:=Cpu.new();cpu.surfaces=mesh.surfaces;cpu.box_size=mesh.box_size
	return Store._sha(cpu.collision_faces().to_byte_array())
func invariants(original:Dictionary,candidate:Dictionary)->Dictionary:
	if not check(Frozen.valid(original) and Frozen.valid(candidate),"Frozen schema/size caps valid for %s (candidate raw bytes %s)"%[str(original.get("uuid","")),str(candidate.get("house_prefab",{}).get("length",-1))]):return {}
	var a:=original.duplicate(true);var b:=candidate.duplicate(true)
	a.erase("house_prefab");b.erase("house_prefab")
	if not check(exact(a,b),"Only the frozen payload changes: "+str(original.uuid)):return {}
	var before:=Frozen.decode(original.house_prefab);var after:=Frozen.decode(candidate.house_prefab)
	if not check(Cook.valid_data(before) and Cook.valid_data(after) and before.entries.size()==1 and after.entries.size()==1,"Valid single bridge CPU packets"):return {}
	var r0:int=before.entries[0][1][0];var c0:int=before.entries[0][1][1]
	var r1:int=after.entries[0][1][0];var c1:int=after.entries[0][1][1]
	if not check(c0==c1 and var_to_bytes(before.meshes[c0])==var_to_bytes(after.meshes[c1]),"Collision row exact"):return {}
	if not check(var_to_bytes(before.materials)==var_to_bytes(after.materials),"Material definitions exact"):return {}
	if not check(var_to_bytes(before.meshes[r0].surfaces)==var_to_bytes(after.meshes[r1].surfaces),"Every base surface channel exact"):return {}
	var original_render:Dictionary=before.meshes[r0].duplicate(true);var candidate_render:Dictionary=after.meshes[r1].duplicate(true)
	original_render.erase("lods");candidate_render.erase("lods")
	if not check(var_to_bytes(original_render)==var_to_bytes(candidate_render),"Render bounds, material slots and all non-LOD fields exact"):return {}
	# Reconstruct the original packet by removing only LOD indices and the
	# optional render/source split, then compare every serialized field.
	var restored:=after.duplicate(true)
	if r0==c0 and r1!=r0:
		if not check(r1==before.meshes.size() and after.meshes.size()==before.meshes.size()+1,"Only one render row appended"):return {}
		restored.meshes.remove_at(r1);restored.entries[0][1][0]=r0
	else:
		if not check(r1==r0,"Existing render identity preserved"):return {}
		if before.meshes[r0].has("lods"):restored.meshes[r0].lods=before.meshes[r0].lods
		else:restored.meshes[r0].erase("lods")
	if not check(var_to_bytes(restored)==var_to_bytes(before),"All non-LOD frozen data exact"):return {}
	var surfaces:Array=[];var base_total:=0;var lod_bytes:=0
	for slot in after.meshes[r1].surfaces.size():
		var arrays:Array=after.meshes[r1].surfaces[slot]
		var count:int=arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size()
		base_total+=count/3
		var levels:Array=[];var all_lods:Array=after.meshes[r1].get("lods",[])
		var selected:Dictionary=all_lods[slot] if slot<all_lods.size() else {}
		var edges:=selected.keys();edges.sort()
		for edge in edges:
			levels.append({"edge_length":edge,"triangles":selected[edge].size()/3});lod_bytes+=selected[edge].size()*4
		surfaces.append({"surface":slot,"base_triangles":count/3,"lods":levels})
	var before_hash:=collision_hash(before.meshes[c0]);var after_hash:=collision_hash(after.meshes[c1])
	if not check(before_hash==after_hash,"Expanded collision faces exact"):return {}
	return {"base_exact":true,"collision_exact":true,"materials_exact":true,"other_frozen_data_exact":true,"collision_sha256":before_hash,"base_triangles":base_total,"surfaces":surfaces,"lod_index_bytes":lod_bytes,"render_source_split":r1!=r0,"duplicated_base_surface_bytes":var_to_bytes(before.meshes[r0].surfaces).size() if r1!=r0 else 0,"raw_before":int(original.house_prefab.length),"raw_after":int(candidate.house_prefab.length),"raw_delta":int(candidate.house_prefab.length)-int(original.house_prefab.length)}
func prepare()->void:
	var current:=source()
	if current.is_empty():return
	var rows:Array=[]
	for i in current.records.size():
		var original:Dictionary=current.records[i];var mark:=Time.get_ticks_usec()
		var made:=Lod.derive_record(original)
		if not check(made.ok,"Derive "+str(original.uuid)):return
		var stats:=invariants(original,made.record)
		if stats.is_empty():
			write_json("prepare_failure.json",{"ok":false,"uuid":original.uuid,"source_sha256":current.sha256,"candidate_raw_bytes":made.record.get("house_prefab",{}).get("length",-1),"failures":failures,"formal_map_unchanged":FileAccess.get_sha256(map_path)==current.sha256})
			return
		var encoded:=Store._encode(Store._definition(made.record))
		if not check(encoded.ok,"Encode derived bridge definition"):return
		stats.outer_bytes_before=int(current.compact[i].rmmo_ref.length);stats.outer_bytes_after=encoded.length
		stats.outer_bytes_delta=encoded.length-stats.outer_bytes_before
		stats.derive_and_validate_ms=(Time.get_ticks_usec()-mark)/1000.0
		var row:Dictionary={"uuid":original.uuid,"changed":made.changed,"source_ref":current.compact[i].rmmo_ref,"source_record_token":City.token(original),"source_prefab_sha256":original.house_prefab.sha256,"candidate_token":City.token(made.record),"candidate_prefab_sha256":made.record.house_prefab.sha256,"candidate_record":made.record,"stats":stats}
		rows.append(row)
		print("BRIDGE_LOD_PREPARED ",JSON.stringify({"uuid":row.uuid,"changed":row.changed,"stats":stats}))
	if not check(FileAccess.get_sha256(map_path)==current.sha256,"Original map still unchanged"):return
	write_json("plan.json",{"version":1,"map_path":map_path,"source_sha256":current.sha256,"scope":"all road-bound stone bridges; publication also verifies the complete hydrated bridge set","record_count":current.record_count,"bridge_count":rows.size(),"non_bridge_compact_token":City.token(current.non_bridge_compact),"non_bridge_compact":current.non_bridge_compact,"bridges":rows})
	print("BRIDGE_LOD_PLAN count=",rows.size()," map_unchanged=true path=",out_path.path_join("plan.json"))
func verified_plan()->Dictionary:
	var plan:=read_json("plan.json")
	if not check(plan.get("version")==1 and plan.get("map_path")==map_path and plan.get("bridges") is Array,"Prepared plan for this map"):return {}
	var current:=source()
	if current.is_empty():return {}
	if not check(current.sha256==plan.source_sha256 and current.record_count==int(plan.record_count),"Plan source map SHA/count unchanged"):return {}
	if not check(exact(current.non_bridge_compact,plan.non_bridge_compact),"Every non-bridge compact record exactly unchanged"):return {}
	if not check(current.records.size()==plan.bridges.size(),"Bridge set unchanged"):return {}
	var originals:Dictionary={}
	for i in current.records.size():
		var record:Dictionary=current.records[i];var row:Dictionary=plan.bridges[i]
		if not check(record.uuid==row.uuid and City.token(record)==row.source_record_token and record.house_prefab.sha256==row.source_prefab_sha256 and exact(current.compact[i].rmmo_ref,row.source_ref),"Source bridge identity unchanged"):return {}
		if not check(City.token(row.candidate_record)==row.candidate_token and row.candidate_record.house_prefab.sha256==row.candidate_prefab_sha256,"Candidate identity unchanged"):return {}
		if invariants(record,row.candidate_record).is_empty():return {}
		originals[record.uuid]=record
	plan.originals=originals;return plan
func rss_bytes()->int:
	# True process working set, not Godot's unrelated allocator counter.
	var output:Array=[]
	var error:=OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-Command","(Get-Process -Id %d).WorkingSet64"%OS.get_process_id()],output,true)
	return str(output[0]).strip_edges().to_int() if error==0 and not output.is_empty() else -1
func implementation_sha256()->Dictionary:
	var result:Dictionary={}
	for path in ["res://tools/prepare_bridge_lod_update.gd","res://tools/bridge_lod_assertions.gd","res://scripts/world3d/bridge_lod_preparation.gd","res://scripts/world3d/ground_cpu_mesh.gd","res://scripts/world3d/runtime_mesh_cache.gd","res://scripts/world3d/house_prefab.gd","res://scripts/world3d/surface_materials.gd"]:
		result[path]=FileAccess.get_sha256(path)
	return result
func review_configuration()->Dictionary:
	var settings:Dictionary={}
	for property:Dictionary in ProjectSettings.get_property_list():
		var name:String=property.name
		if name.begins_with("rendering/"):settings[name]=var_to_str(ProjectSettings.get_setting(name))
	return {"engine":Engine.get_version_info(),"rendering_settings":settings,"size":[1500,900],"fov":55.0,"far":1200.0,"sun_degrees":[-40,-25,0],"sun_energy":1.5,"ambient_energy":0.6,"lod_threshold":float(ProjectSettings.get_setting("rendering/mesh_lod/lod_change/threshold_pixels",1.0))}
func validate_review(report:Dictionary,plan:Dictionary)->bool:
	if not check(exact(report.get("implementation_sha256"),implementation_sha256()) and exact(report.get("configuration"),review_configuration()),"Review proof matches current implementation and rendering configuration"):return false
	if not check(report.get("views") is Array and report.views.size()==plan.bridges.size()*6,"Every bridge has all six comparison images"):return false
	var indexed:Dictionary={};var known:Dictionary={}
	for bridge:Dictionary in plan.bridges:known[bridge.uuid]=true
	for view:Dictionary in report.views:
		if not check(known.has(view.get("uuid")) and view.get("case") in ["original","candidate"] and view.get("pose") in ["near","far","arch"],"Review row belongs to the prepared bridge set"):return false
		var key:String=view.uuid+"/"+view.case+"/"+view.pose
		if not check(not indexed.has(key),"Each bridge/case/pose occurs exactly once"):return false
		indexed[key]=view
		if not check(view.get("gpu_lods_verified",false) and int(view.get("visible_primitives",0))>0,"Actual visible bridge triangles for "+key):return false
		var expected:String=view.uuid+"_"+view.case+"_"+view.pose+".png"
		if not check(view.get("png")==expected and FileAccess.get_sha256(out_path.path_join(expected))==view.get("image_sha256") and not str(view.get("image_sha256","")).is_empty(),"Review image bytes unchanged for "+key):return false
	var reductions:Array=[]
	for bridge:Dictionary in plan.bridges:
		var evidence:Dictionary={"uuid":bridge.uuid,"poses":[]}
		for pose in ["near","far","arch"]:
			var original:Dictionary=indexed.get(bridge.uuid+"/original/"+pose,{})
			var candidate:Dictionary=indexed.get(bridge.uuid+"/candidate/"+pose,{})
			if not check(not original.is_empty() and not candidate.is_empty(),"Complete paired pose "+pose):return false
			if not check(original.camera_eye==candidate.camera_eye and original.camera_target==candidate.camera_target and original.lod_threshold==0.0 and candidate.lod_threshold==report.default_lod_threshold and candidate.lod_threshold>0.0,"Identical camera with disabled/or default LOD"):return false
			if pose=="far" and not check(candidate.visible_primitives<original.visible_primitives,"Far renderer actually uses fewer triangles for "+str(bridge.uuid)):return false
			evidence.poses.append({"pose":pose,"base_triangles":original.visible_primitives,"lod_triangles":candidate.visible_primitives,"remaining_ratio":float(candidate.visible_primitives)/float(original.visible_primitives)})
		reductions.append(evidence)
	report.triangle_comparisons=reductions
	return true
func review()->void:
	# Re-running review first revokes the old success, including on an early
	# malformed source/GPU failure. A partial new run cannot authorize publish.
	if not write_json("review.json",{"ok":false,"state":"in_progress"}):return
	if not check(DisplayServer.get_name()!="headless","Review requires private desktop GPU runner"):return
	var plan:=verified_plan()
	if plan.is_empty():return
	var report:Dictionary={"plan_sha256":FileAccess.get_sha256(out_path.path_join("plan.json")),"map_sha256":plan.source_sha256,"implementation_sha256":implementation_sha256(),"configuration":review_configuration(),"command_line":OS.get_cmdline_args(),"avatar":false,"views":[],"rss_note":"Process working set sampled after each view; sequential caches shared, not an independent memory A/B","default_lod_threshold":float(ProjectSettings.get_setting("rendering/mesh_lod/lod_change/threshold_pixels",1.0))}
	root.size=Vector2i(1500,900)
	var view:=SubViewport.new();view.size=root.size;view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var mesh:=MeshInstance3D.new();view.add_child(mesh)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.24,.30,.34);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.6;view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-25,0);sun.light_energy=1.5;sun.shadow_enabled=true;view.add_child(sun)
	var camera:=Camera3D.new();camera.far=1200;camera.fov=55;view.add_child(camera);camera.current=true
	for row:Dictionary in plan.bridges:
		var original:Dictionary=plan.originals[row.uuid]
		for case_name in ["original","candidate"]:
			var record:Dictionary=original if case_name=="original" else row.candidate_record
			var data:=Frozen.decode(record.house_prefab);var render_id:int=data.entries[0][1][0]
			var entry:=Frozen.geometry(record)
			if not check(not entry.is_empty(),"Restore review bridge"):return
			mesh.mesh=entry.mesh.restore();mesh.transform=Transform3D.IDENTITY
			var lods:Array=data.meshes[render_id].get("lods",[])
			if lods.is_empty():
				for slot in mesh.mesh.get_surface_count():lods.append({})
			if not check(GPU.matches(mesh.mesh,lods),"Actual uploaded GPU LOD indices match frozen record"):return
			view.mesh_lod_threshold=0.0 if case_name=="original" else report.default_lod_threshold
			var bounds:AABB=mesh.mesh.get_aabb();var center:=bounds.get_center();var span:=maxf(bounds.size.x,bounds.size.z)
			var poses:=[{"name":"near","eye":Vector3(.70,.35,.85)*span,"target":center},{"name":"far","eye":Vector3(2.4,1.2,3.0)*span,"target":center},{"name":"arch","eye":Vector3(0,-.015,.5)*span,"target":center+Vector3(0,-.03,0)*span}]
			for pose:Dictionary in poses:
				camera.position=center+pose.eye;camera.look_at(pose.target)
				for frame in 12:await process_frame;await RenderingServer.frame_post_draw
				var picture:String=row.uuid+"_"+case_name+"_"+pose.name+".png"
				if not check(view.get_texture().get_image().save_png(out_path.path_join(picture))==OK,"Save "+picture):return
				report.views.append({"uuid":row.uuid,"case":case_name,"pose":pose.name,"png":picture,"image_sha256":FileAccess.get_sha256(out_path.path_join(picture)),"camera_eye":var_to_str(camera.position),"camera_target":var_to_str(pose.target),"lod_threshold":view.mesh_lod_threshold,"gpu_lods_verified":true,"visible_primitives":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"shadow_primitives":view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"rss_bytes":rss_bytes()})
		mesh.mesh=null
	view.queue_free();await process_frame
	check(FileAccess.get_sha256(map_path)==plan.source_sha256,"Review left source map unchanged")
	validate_review(report,plan)
	report.ok=failures.is_empty();report.state="complete" if report.ok else "failed";report.failures=failures;write_json("review.json",report)
	print("BRIDGE_LOD_REVIEW views=",report.views.size()," ok=",report.ok)
func expected_metadata(before:Dictionary,candidates:Dictionary)->Dictionary:
	var result:=before.duplicate(true);var layout:Dictionary=result.get("editor_layout",{})
	var original_roads:Dictionary=layout.get("roads",{}).duplicate(true)
	for edge:Dictionary in layout.get("roads",{}).get("edges",[]):
		if edge.has("stone_bridge") and candidates.has(edge.stone_bridge.id):edge.stone_bridge.signature=City.token(candidates[edge.stone_bridge.id])
	for region:Dictionary in layout.get("waterways",[]):
		for part:Dictionary in region.parts:
			if candidates.has(part.id):part.signature=City.token(candidates[part.id])
	if layout.has("road_surface") and not exact(original_roads,layout.roads):layout.road_surface.graph_token=City.token(layout.roads)
	return result
func publish()->void:
	var plan:=verified_plan()
	if plan.is_empty():return
	var reviewed:=read_json("review.json")
	if not check(reviewed.get("ok",false) and reviewed.get("plan_sha256")==FileAccess.get_sha256(out_path.path_join("plan.json")),"Publish requires completed GPU review of this exact plan"):return
	if not validate_review(reviewed,plan):return
	var doc=Doc.open_file(map_path)
	if not check(doc!=null and doc.save_signature(map_path)==plan.source_sha256,"Full document opened at reviewed source SHA"):return
	var candidates:Dictionary={}
	for row:Dictionary in plan.bridges:candidates[row.uuid]=row.candidate_record
	var before:Array=doc.records.duplicate(true);var bridge_count:=0
	for index in doc.records.size():
		var record:Dictionary=doc.records[index]
		if record.has("bridge_mesh"):
			bridge_count+=1
			if not check(candidates.has(record.uuid),"Plan covers every bridge in complete document"):return
		if not candidates.has(record.uuid):continue
		if not check(exact(record,plan.originals[record.uuid]),"Hydrated original bridge exact"):return
		doc.records[index]=candidates[record.uuid].duplicate(true)
	if not check(bridge_count==candidates.size(),"Complete bridge count exact"):return
	for i in before.size():
		if not candidates.has(before[i].uuid) and not check(exact(before[i],doc.records[i]),"Non-bridge authored record exact before save"):return
	var expected_meta:=expected_metadata(doc.map_meta,candidates)
	Structure.refresh_bindings(doc.map_meta,doc.records)
	if not check(exact(doc.map_meta,expected_meta),"Only necessary bridge binding signatures/road graph token change in metadata"):return
	if not check(FileAccess.get_sha256(map_path)==plan.source_sha256,"Source SHA immediately before atomic save"):return
	if not check(doc.save(map_path)==OK,"Atomic document save with source conflict baseline"):return
	var reopened=Doc.open_file(map_path)
	if not check(reopened!=null and reopened.records.size()==before.size(),"Published document reopens"):return
	if not check(exact(reopened.map_meta,expected_meta),"Published metadata exactly matches the permitted update"):return
	for i in before.size():
		var expected:Dictionary=candidates.get(before[i].uuid,before[i])
		if not check(exact(reopened.records[i],expected),"Every saved authored record exactly matches expected"):return
	write_json("published.json",{"ok":true,"source_sha256":plan.source_sha256,"published_sha256":FileAccess.get_sha256(map_path),"bridge_count":bridge_count,"non_bridge_records_exact":true,"metadata_exact":true,"save_metrics":doc.last_save_metrics})
	print("BRIDGE_LOD_PUBLISHED bridges=",bridge_count," non_bridge_records_exact=true")
func run()->void:
	var mode:="prepare"
	for arg in OS.get_cmdline_user_args():
		if arg=="--review" or arg=="--publish":
			if not check(mode=="prepare","Choose only one explicit mode"):quit(1);return
			mode=arg.trim_prefix("--")
		elif arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
		elif arg.begins_with("--out="):out_path=arg.trim_prefix("--out=")
		else:check(false,"Unknown argument "+arg)
	if not failures.is_empty():quit(1);return
	if not check(Paths.allowed(out_path) and out_path.replace("\\","/").contains("/review_artifacts/"),"Output confined to private review artefacts"):quit(1);return
	DirAccess.make_dir_recursive_absolute(out_path)
	match mode:
		"prepare":prepare()
		"review":await review()
		"publish":publish()
	if mode=="review" and not failures.is_empty():
		var review_state:=read_json("review.json");review_state.ok=false;review_state.state="failed";review_state.failures=failures;write_json("review.json",review_state)
	quit(0 if failures.is_empty() else 1)
