extends "res://tools/test_house_editor_incremental_http.gd"
## Final real HTTP acceptance for an immutable combined candidate. Private GPU
## desktop only; Save As targets this process's own newly created cache folder.
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const FORMAL_SHA="779c513dc5433ddbe66d018471a8a505260e161d1656c690a00cde2675fb7a7f"
const INPUT="D:/code/rmmo_runtime/cache/world3d/joint_model_validation_20261011_1791726474152524200/combined/map.gltf"
const INPUT_SHA="f362c6345d6cfcab5f94c003fec1564f339d6f81d6e71ef3b978fe6a2d74ef1c"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
var input_path:=INPUT
var expected_sha:=INPUT_SHA
var output:="D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011/joint_candidate_save.json"
var report:Dictionary={"checks":[],"saves":[],"loads":[],"scope":"Combined candidate HTTP open/edit/Save As/reopen; no formal publication or full texture readback."}
var stage:="arguments"
var manifest:Dictionary={}
var mappings:Dictionary={}
var manifest_path:=""
var manifest_sha:=""
var spec_path:=""
var spec_sha:=""
var catalog_sha:=""
var saved_path:=""
var baseline:Dictionary={}

func check(ok:bool,label:String)->void:
	super.check(ok,label)
	report.checks.append({"ok":ok,"label":label})

func persist()->void:
	report.failures=failed;report.stage=stage;report.operations=operations
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()

func mark(value:String)->void:
	stage=value;print("JOINT_CANDIDATE_STAGE ",value);persist()

func read_object(path:String)->Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>2*1024*1024:return {}
	var value:Variant=JSON.parse_string(file.get_as_text());file.close()
	return value if value is Dictionary else {}

func sha_valid(value:String)->bool:
	if value.length()!=64:return false
	for character in value:
		if character not in "0123456789abcdefABCDEF":return false
	return true

func physics_settle()->void:
	await physics_frame;await physics_frame;await settle()

func open_map(path:String)->bool:
	var began:=Time.get_ticks_usec()
	var pending:=await timed_tool("open_world",{"path":path,"background":true,"discard_changes":true})
	if not pending.get("ok",false):return false
	var next_log:=Time.get_ticks_msec()+10000
	while editor._load_job.active:
		if Time.get_ticks_msec()>=next_log:
			print("JOINT_CANDIDATE_LOAD ",editor._load_job.phase," ",editor._load_job.completed,"/",editor._load_job.total);next_log=Time.get_ticks_msec()+10000
		await process_frame
	var result:Dictionary=editor._load_job.result.duplicate(true)
	report.loads.append({"path":path,"ms":(Time.get_ticks_usec()-began)/1000.,"result":result})
	check(result.get("ok",false),"HTTP open completes: "+path.get_file())
	if not result.get("ok",false):return false
	editor._ground_batches.flush();await physics_settle()
	check(editor._doc.records.size()==4437 and editor._buildings.instances().size()==61,"complete 4437 records and 61 houses loaded")
	return editor._doc.records.size()==4437 and editor._buildings.instances().size()==61

func model_evidence(root_node:Node3D,materials:Dictionary)->Dictionary:
	var answer:={"meshes":0,"surfaces":0,"visible_meshes":0,"material_slots":0,"valid":root_node!=null}
	if root_node==null:return answer
	for mesh_node:MeshInstance3D in Paint.meshes(root_node):
		if mesh_node.mesh==null:answer.valid=false;continue
		answer.meshes+=1
		if mesh_node.is_visible_in_tree():answer.visible_meshes+=1
		for slot in mesh_node.mesh.get_surface_count():
			answer.surfaces+=1
			var material:Material=mesh_node.get_active_material(slot)
			if material==null:answer.valid=false;continue
			answer.material_slots+=1
			if materials.has(material.get_instance_id()):continue
			materials[material.get_instance_id()]={"type":material.get_class(),"textures":0}
			if material is BaseMaterial3D:
				for at in BaseMaterial3D.TEXTURE_MAX:
					var texture:Texture2D=material.get_texture(at)
					if texture!=null:
						materials[material.get_instance_id()].textures+=1
						if texture.get_width()<=0 or texture.get_height()<=0:answer.valid=false
			elif material is ShaderMaterial and material.shader==null:answer.valid=false
	answer.valid=answer.valid and answer.meshes>0 and answer.surfaces>0 and answer.material_slots>0
	return answer

func audit_scene(label:String)->void:
	var changed:Array=manifest.fixtures.combined.changed_ids
	var changed_set:Dictionary={};var expected_paths:Dictionary={}
	for uuid:String in changed:changed_set[uuid]=true
	for old_path:String in mappings:expected_paths[str(mappings[old_path])]=int(manifest.fixtures.combined.changed_paths.get(old_path,-1))
	var seen:Dictionary={};var rows:Dictionary={};var materials:Dictionary={};var valid:=true;var poses:=true;var identity:=true
	for record:Dictionary in editor._doc.records:
		var uuid:String=record.uuid
		if seen.has(uuid):identity=false
		seen[uuid]=true
		var pose:Transform3D=Pose.pose(record)
		poses=poses and pose.is_finite() and not is_zero_approx(pose.basis.determinant())
		if not changed_set.has(uuid):continue
		var path:String=record.get("asset_path","")
		if not expected_paths.has(path):valid=false;continue
		if not rows.has(path):rows[path]={"instances":0,"meshes":0,"surfaces":0,"visible_instances":0,"invalid":[]}
		var row:Dictionary=rows[path];row.instances+=1
		var visual:Node3D=editor._view.get_node_or_null(NodePath(uuid)) as Node3D
		var evidence:=model_evidence(visual,materials)
		row.meshes+=evidence.meshes;row.surfaces+=evidence.surfaces
		var should_show:bool=not record.get("editor_hidden",false) and not record.get("invisible",false)
		var visibility_ok:bool=not should_show or evidence.visible_meshes>0
		if evidence.visible_meshes>0:row.visible_instances+=1
		if not evidence.valid or not visibility_ok:row.invalid.append(uuid);valid=false
	var count:=0
	for path:String in rows:
		count+=int(rows[path].instances)
		valid=valid and rows[path].instances==expected_paths[path]
	var missing_nodes:Array=[]
	for node:Node in editor._view.find_children("*","",true,false):
		if node.get_meta("missing_asset",false):missing_nodes.append(str(node.get_path()))
	check(identity and seen.size()==4437 and poses,label+": every UUID unique and authored transform finite/nondegenerate")
	check(rows.size()==14 and count==690 and valid,label+": all 14 replaced paths and 690 instances have actual mesh/material/visibility")
	check(missing_nodes.is_empty() and editor._doc.missing_assets().is_empty(),label+": no missing-asset placeholder or missing dependency")
	report[label]={"types":rows.size(),"instances":count,"paths":rows,"unique_materials":materials.size(),"missing_nodes":missing_nodes,"poses_valid":poses}

func choose_samples()->Dictionary:
	var result:Dictionary={};var changed:Dictionary={}
	for id:String in manifest.fixtures.combined.changed_ids:changed[id]=true
	var shrub_path:String=mappings.get("D:/code/rmmo_runtime/packs/default/assets/47fd0e87bc7aadae089f7f8593a6062d2f7604eb76c6c84dd8a052a37d075e6c.glb","")
	for record:Dictionary in editor._doc.records:
		if not changed.has(record.uuid) or not editor._record_editable(record) or record.get("prefab_locked",false):continue
		var path:String=record.get("asset_path","")
		if path.contains("bridge_long_pennants") and not result.has("pennant"):result.pennant=record.uuid
		if path==shrub_path and not result.has("shrub"):result.shrub=record.uuid
		if str(record.uuid).begins_with("bridge_grass_") and not result.has("grass"):result.grass=record.uuid
	return result

func find_pick(uuid:String,faces:Array)->Dictionary:
	# Aim at an actual triangle centroid, not an AABB or possibly concave face
	# average. Search is read-only through the same UI/painter business methods;
	# the accepted ray is then exercised through real HTTP pick_surface.
	for face:Dictionary in faces.slice(0,32):
		var resolved:Dictionary=editor._material_tool.resolve(uuid,face.target)
		if not resolved.get("ok",false) or resolved.face.triangles.is_empty():continue
		var data:Dictionary=resolved.data;var tri:int=resolved.face.triangles[0]
		var vertices:PackedVector3Array=data.arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=data.indices
		var center:Vector3=resolved.node.global_transform*((vertices[indices[tri*3]]+vertices[indices[tri*3+1]]+vertices[indices[tri*3+2]])/3.)
		var normal:=Vector3(float(face.normal[0]),float(face.normal[1]),float(face.normal[2])).normalized()
		if not center.is_finite() or not normal.is_finite() or normal.length_squared()<.5:continue
		editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE;editor._camera.near=.005
		editor._camera.position=center+normal*.15
		editor._camera.look_at(center,Vector3.RIGHT if absf(normal.dot(Vector3.UP))>.98 else Vector3.UP)
		await physics_settle()
		var pixel:Vector2=editor._camera.unproject_position(center)
		if not Rect2(Vector2.ZERO,editor._canvas.size).has_point(pixel):continue
		if editor._pick_object(pixel)!=uuid:continue
		var painted:Dictionary=editor._material_tool.pick(pixel)
		if painted.get("ok",false) and painted.get("id")==uuid:return {"screen":[pixel.x,pixel.y],"target":painted.target}
	return {}

func sample_tools(label:String,uuid:String)->void:
	var original:Dictionary=editor._doc._find(uuid).duplicate(true)
	await timed_tool("select_objects",{"ids":[uuid]})
	check(editor._selection_tools.ids.has(uuid),label+": real HTTP selects original UUID")
	var listed:=await timed_tool("list_object_surfaces",{"id":uuid,"limit":200})
	check(listed.get("total",0)>0 and not listed.get("faces",[]).is_empty(),label+": actual paint target enumeration available")
	var hit:Dictionary=await find_pick(uuid,listed.get("faces",[]))
	check(not hit.is_empty(),label+": exact UI ray finds a real candidate triangle")
	if hit.is_empty():return
	var picked:=await timed_tool("pick_surface",{"screen":hit.screen})
	check(picked.get("id")==uuid and equivalent(picked.get("target"),hit.target),label+": HTTP surface pick agrees with UI exact UUID/target")
	await timed_tool("set_object_properties",{"ids":[uuid],"locked":true})
	check(not editor._selection_tools.ids.has(uuid),label+": lock removes protected selection")
	await atomic_reject("set_object_transform",{"id":uuid,"position":original.position})
	await atomic_reject("paint_surface",{"id":uuid,"target":hit.target,"material_id":"builtin:checker"})
	await timed_tool("undo")
	check(equivalent(original,editor._doc._find(uuid)),label+": lock undo restores original record exactly")
	var before_bodies:int=editor._bodies_by_uuid.get(uuid,[]).size()
	await timed_tool("set_object_properties",{"ids":[uuid],"hidden":true});await physics_settle()
	var hidden:Node3D=editor._view.get_node_or_null(NodePath(uuid)) as Node3D
	check(hidden!=null and not hidden.is_visible_in_tree() and editor._bodies_by_uuid.get(uuid,[]).is_empty(),label+": hidden visual has no picking bodies")
	await timed_tool("undo");await physics_settle()
	check(equivalent(original,editor._doc._find(uuid)) and editor._bodies_by_uuid.get(uuid,[]).size()==before_bodies,label+": hide undo restores authored data and picking")
	report.samples[label]={"uuid":uuid,"surface_count":listed.get("total"),"picked":picked,"picking_bodies":before_bodies}

func save_owned()->bool:
	if directory.is_empty() or not Paths.allowed(saved_path,directory) or saved_path==input_path or saved_path==FORMAL:
		check(false,"Save As destination must belong to this fixture");return false
	var began:=Time.get_ticks_usec()
	var pending:=await timed_tool("save_world",{"path":saved_path,"background":true})
	if not pending.get("ok",false):return false
	while editor._save_job.active:await process_frame
	var result:Dictionary=editor._save_job.result.duplicate(true)
	report.saves.append({"ms":(Time.get_ticks_usec()-began)/1000.,"result":result})
	var exported:Dictionary=result.get("timings",{}).get("export",{})
	check(result.get("saved",false) and result.get("path")==saved_path,"real HTTP saves only owned temporary map")
	check(exported.get("mode")=="reference_map" and exported.get("images_written",-1)==0 and exported.get("texture_export_passes",-1)==0,"reference save exports zero images and performs zero texture export passes")
	persist()
	return result.get("saved",false)

func finish()->void:
	check(FileAccess.get_sha256(FORMAL)==FORMAL_SHA,"formal town SHA unchanged")
	check(FileAccess.get_sha256(input_path)==expected_sha,"combined input map SHA unchanged")
	if not manifest_sha.is_empty():check(FileAccess.get_sha256(manifest_path)==manifest_sha and FileAccess.get_sha256(spec_path)==spec_sha,"fixture manifest/spec remain unchanged")
	if not catalog_sha.is_empty():check(FileAccess.get_sha256(Paths.external_root().path_join("packs/default/assets/library.json"))==catalog_sha,"existing asset library remains unchanged")
	stage="finished";persist()
	if is_instance_valid(editor):
		if editor._mcp!=null:editor._mcp.stop()
		editor.queue_free();await settle()
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=null;session.world3d_editor_path=""
	print("JOINT_CANDIDATE_SAVE failures=",failed," report=",output)
	quit(0 if failed==0 else 1)

func run()->void:
	Engine.max_fps=60;rpc_timeout_ms=180000
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):input_path=arg.trim_prefix("--map=")
		elif arg.begins_with("--expected-sha="):expected_sha=arg.trim_prefix("--expected-sha=")
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--picking-lod" or arg.begins_with("--picking-lod="):
			var value:=arg.trim_prefix("--picking-lod=")
			if value not in ["off","on"]:push_error("Expected --picking-lod=off or on");quit(2);return
			preload("res://scripts/world_editor/picking_lod_policy.gd").enabled=value=="on"
		elif arg=="--model-texture-sharing" or arg.begins_with("--model-texture-sharing="):
			var value:=arg.trim_prefix("--model-texture-sharing=")
			if value not in ["off","on"]:push_error("Expected --model-texture-sharing=off or on");quit(2);return
			preload("res://scripts/world3d/model_texture_cache.gd").enabled=value=="on"
		else:push_error("Unknown joint fixture argument: "+arg);quit(2);return
	if not sha_valid(expected_sha):push_error("Expected --expected-sha with exactly 64 hexadecimal characters");quit(2);return
	expected_sha=expected_sha.to_lower();input_path=input_path.replace("\\","/").simplify_path();output=ProjectSettings.globalize_path(output).replace("\\","/").simplify_path()
	if not Paths.allowed(input_path,Paths.external_root().path_join("cache/world3d")) or not FileAccess.file_exists(input_path):push_error("Existing temporary input map required");quit(2);return
	if not Paths.allowed(output,Paths.external_root().path_join("review_artifacts")) or output.get_extension()!="json":push_error("JSON output must remain in runtime review_artifacts");quit(2);return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	root.size=Vector2i(1280,900);root.content_scale_size=root.size
	report.input=input_path;report.input_sha=expected_sha;report.formal_sha=FORMAL_SHA;report.samples={}
	report.picking_lod=preload("res://scripts/world_editor/picking_lod_policy.gd").enabled
	report.model_texture_sharing=preload("res://scripts/world3d/model_texture_cache.gd").enabled
	create_timer(1200).timeout.connect(func():report.timeout=true;persist();quit(2))
	check(FileAccess.get_sha256(input_path)==expected_sha and FileAccess.get_sha256(FORMAL)==FORMAL_SHA,"input and formal SHA match required immutable revisions")
	if failed>0:await finish();return
	var fixture_root:=input_path.get_base_dir().get_base_dir()
	manifest_path=fixture_root.path_join("fixture_manifest.json");spec_path=fixture_root.path_join("fixture_spec.json")
	manifest=read_object(manifest_path);var specification:=read_object(spec_path)
	mappings=specification.get("mappings",{}).get("combined",{})
	var declared:Dictionary=manifest.get("fixtures",{}).get("combined",{})
	check(declared.get("sha256")==expected_sha and declared.get("changed_instances")==690 and declared.get("changed_ids",[]).size()==690 and mappings.size()==14,"SHA-bound combined fixture declares 14 substituted types and 690 UUIDs")
	if failed>0:await finish();return
	manifest_sha=FileAccess.get_sha256(manifest_path);spec_sha=FileAccess.get_sha256(spec_path)
	catalog_sha=FileAccess.get_sha256(Paths.external_root().path_join("packs/default/assets/library.json"))
	directory=Paths.cache_directory("joint_candidate_save_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	saved_path=directory.path_join("saved/map.gltf")
	check(not DirAccess.dir_exists_absolute(directory) and Paths.allowed(saved_path,Paths.external_root().path_join("cache/world3d")),"new isolated output directory cannot overwrite any input")
	if failed>0:await finish();return
	DirAccess.make_dir_recursive_absolute(saved_path.get_base_dir());report.saved_path=saved_path
	var session=preload("res://scripts/net/net.gd").session();var initial:=Doc.new()
	initial.add_box("block",Vector3.ZERO,Vector3.ONE)
	session.world3d_editor_doc=initial;session.world3d_editor_path=directory.path_join("initial_unsaved.gltf")
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var server:=TCPServer.new();port=29910
	while server.listen(port,"127.0.0.1")!=OK:port+=1
	server.stop();check(editor.start_mcp(port).ok,"real loopback 3D HTTP starts")
	var definitions:Array=(await rpc("tools/list")).get("result",{}).get("tools",[])
	check(definitions.size()==preload("res://scripts/world_editor/mcp_schema.gd").tools().size() and definitions.any(func(row):return row.name=="pick_surface"),"current 3D tool discovery matches schema")
	mark("open_combined")
	if not await open_map(input_path):await finish();return
	audit_scene("initial_scene");baseline=editor._doc.recovery_snapshot()
	var samples:=choose_samples()
	check(samples.size()==3,"editable replaced pennant shrub and grass samples found")
	if failed>0:await finish();return
	mark("selection_pick_protection")
	for label:String in ["pennant","shrub","grass"]:await sample_tools(label,str(samples[label]))
	check(equivalent(baseline.records,editor._doc.records) and equivalent(baseline.map_meta,editor._doc.map_meta),"all sample operations restore complete author records and metadata")
	if failed>0:await finish();return
	mark("move_undo_redo")
	var uuid:String=samples.pennant;var original:Dictionary=editor._doc._find(uuid).duplicate(true)
	var position:Array=original.position.duplicate();position[0]=float(position[0])+.125
	await timed_tool("set_object_transform",{"id":uuid,"position":position})
	check(equivalent(editor._doc._find(uuid).position,position),"one replaced model moves by 0.125m with original UUID")
	await timed_tool("undo")
	check(equivalent(baseline.records,editor._doc.records),"movement undo restores every record")
	await timed_tool("redo")
	var moved:Dictionary=editor._doc.recovery_snapshot()
	check(equivalent(editor._doc._find(uuid).position,position),"movement redo retains the same UUID and new pose")
	mark("save_as")
	if not await save_owned():await finish();return
	mark("reopen_saved")
	if not await open_map(saved_path):await finish();return
	check(equivalent(moved.records,editor._doc.records) and equivalent(moved.map_meta,editor._doc.map_meta),"Save As/reopen retains all records metadata UUIDs source paths and moved pose")
	moved.clear();audit_scene("reopened_scene")
	mark("restore_and_save")
	await timed_tool("set_object_transform",{"id":uuid,"position":original.position})
	check(equivalent(baseline.records,editor._doc.records) and equivalent(baseline.map_meta,editor._doc.map_meta),"restore after reopen recovers complete original candidate author data")
	if not await save_owned():await finish();return
	report.final_records=editor._doc.records.size();report.final_houses=editor._buildings.instances().size()
	await finish()
