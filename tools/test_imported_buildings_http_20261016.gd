extends "res://tools/test_world3d_city_layout.gd"
## Run serially through run_godot_background.py for GPU/native review. This test
## owns temporary maps/library only and never publishes to the town or catalog.
## --only=guardhouse|church|watermill and --<name>=absolute.glb allow exact reruns.
## --formal-library reads existing default library/source/native products only;
## it writes temporary maps, never imports/copies assets or updates the catalog.
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Components=preload("res://scripts/world3d/model_components.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Walk=preload("res://scripts/world_editor/walk_mode.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const SOURCE_ROOT="D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016"
const REPORT_ROOT="D:/code/rmmo_runtime/review_artifacts/axel_landmarks_20261016/pipeline"
var checks:Array=[]
var source_evidence:Array=[]
var walk_evidence:Array=[]
var context:="HTTP"
var finalizing:=false
var previous_content_override:=""
var isolated_content_root:=""
var formal_library:=false
var formal_catalog_path:=""
var formal_catalog_sha:=""

func check(value:bool,label:String)->void:
	checks.append({"ok":value,"check":context+": "+label})
	super.check(value,context+": "+label)
	DirAccess.make_dir_recursive_absolute(REPORT_ROOT)
	var progress:=FileAccess.open(REPORT_ROOT.path_join("http_progress.json"),FileAccess.WRITE)
	progress.store_string(JSON.stringify({"context":context,"latest":label,"checks":checks.size(),"failed":failed,"failures":checks.filter(func(row):return not row.ok),"ticks_ms":Time.get_ticks_msec()}));progress.close()

func source_for(name_:String)->Dictionary:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--"+name_+"="):
			var path:=argument.get_slice("=",1)
			return {"path":path,"sha256":FileAccess.get_sha256(path)}
	var base:=SOURCE_ROOT.path_join(name_)
	if name_=="guardhouse":
		var current:Variant=JSON.parse_string(FileAccess.get_file_as_string(base.path_join("latest_candidate.json")))
		if current is Dictionary:return {"path":current.glb,"sha256":current.glb_sha256}
	var design:Variant=JSON.parse_string(FileAccess.get_file_as_string(base.path_join("design.json")))
	if not design is Dictionary:return {}
	if name_=="church":return {"path":design.source.glb,"sha256":design.source.sha256}
	return {"path":design.candidate_glb.file,"sha256":design.candidate_glb.sha256}

func idle()->bool:
	var end:=Time.get_ticks_msec()+240000
	while Time.get_ticks_msec()<end:
		await process_frame
		if editor!=null and not editor.saving() and (editor._load_job==null or not editor._load_job.active):
			await settle();return true
	return false

func component_rows(id:String)->Array:
	var model:Node=editor._view.get_node_or_null(NodePath(id))
	return Components.rows(model) if model!=null else []

func component_state(id:String,component:String)->float:
	for row:Dictionary in component_rows(id):
		if row.id==component:return float(row.open)
	return -1.0

func check_colliders(id:String)->void:
	var bodies:Array=editor._bodies_by_uuid.get(id,[]);var valid:=not bodies.is_empty()
	for body:StaticBody3D in bodies:
		var visual:Node3D=body.get_meta("visual",null)
		if not is_instance_valid(visual) or not body.global_transform.is_equal_approx(visual.global_transform):valid=false
	check(valid,"published editor colliders follow actual moving mesh transforms")

func check_native_view(id:String)->void:
	var actual:Array=[];var holder:Node=editor._view.get_node_or_null(NodePath(id))
	if holder!=null:
		for node:Node in holder.find_children("*","",true,false):
			var owner:Variant=node.get_meta("_compiled_resource_owner") if node.has_meta("_compiled_resource_owner") else null
			if owner is PackedScene and owner.get_meta("compiled_asset_validated",false):actual.append(node.name)
	check(not actual.is_empty(),"live editor instance retains an actually verified native PackedScene owner")

func walk_members(id:String)->Array:
	var ids:Array=[]
	for body:StaticBody3D in editor._bodies_by_uuid.get(id,[]):
		if body.collision_layer & Walk.WALK_MASK:
			var mesh:Node3D=body.get_meta("visual")
			ids.append(str(mesh.get_meta("extras",{}).get("uuid")))
	ids.sort();return ids

func check_floor_collision(id:String,expected_walk:Array,all_excluded:bool=false)->void:
	check(not expected_walk.is_empty() and walk_members(id)==expected_walk,"floor view preserves every authored WALK collision member")
	var hidden_count:=0;var correct:=true;var no_zero:=true
	for body:StaticBody3D in editor._bodies_by_uuid.get(id,[]):
		var mesh:Node3D=body.get_meta("visual")
		if body.collision_layer==0:no_zero=false
		if all_excluded or mesh.get_meta("editor_floor_excluded",false):
			hidden_count+=1
			if body.collision_layer & 1:correct=false
			if not (body.collision_layer & Walk.WALK_MASK):correct=false
	check(hidden_count>0 and correct,"hidden or dimmed meshes retain only WALK, never picking")
	check(no_zero,"nonphysical hidden glass produces no useless zero-layer body")

func check_visibility(id:String,lower_y:float,upper_y:float)->void:
	var lower:=0;var upper:=0;var hidden_lower:=0;var visible_upper:=0;var roof_hidden:=0
	for node:MeshInstance3D in editor._view.get_node(NodePath(id)).find_children("*","MeshInstance3D",true,false):
		var part:Dictionary=node.get_meta("extras",{}).get("rmmo_part",{})
		if not Imported.valid_part(part):continue
		if part.role in ["roof","ceiling"]:
			if not node.visible:roof_hidden+=1
			continue
		if is_equal_approx(float(part.floor_y),lower_y):
			lower+=1
			if not node.visible:hidden_lower+=1
		if is_equal_approx(float(part.floor_y),upper_y):
			upper+=1
			if node.visible:visible_upper+=1
	check(lower>0 and hidden_lower==lower,"isolated upper floor hides actual lower body, floor and furniture meshes")
	check(upper>0 and visible_upper>0,"isolated upper floor retains its own actual meshes")
	check(roof_hidden>0,"roof above active height band hides independently")

func walk_routes(name_:String)->Dictionary:
	# Actual author-supplied local Godot floor points, not capsule teleports.
	# Each approach and stair run is reached continuously by production physics.
	match name_:
		"guardhouse":return {"start":[0,.3,6.1],"inside":[0,.3,2.0],"upper":[[ -5.05,.3,2.0],[-5.05,2.1,-2.4],[-3.12,2.1,-2.4],[-3.12,3.9,2.2],[-1.8,3.9,2.2]]}
		"church":return {"start":[0,.3,12.3],"inside":[0,.3,10.2],"upper":[[0,.3,.3],[-6,.3,.3],[-6,.3,-4.85],[-8.95,.3,-4.85],[-8.95,1.8,-8.43],[-6.65,1.8,-8.43],[-6.65,3.3,-4.87],[-7.8,3.3,-4.87]]}
		"watermill":return {"start":[-1.5,0,6.6],"inside":[-1.5,0,4.0],"upper":[[-2.1,0,3.95],[-3.4,0,3.95],[-3.94,0,3.35],[-3.94,3.8,-4.15],[-3.94,3.8,-4.7]]}
	return {}

func route_vec(point:Array)->Vector3:return Vector3(point[0],point[1],point[2])

func walk_to(target:Vector3,frame:Transform3D,label:String)->bool:
	var walker:Node=editor._walk_mode;var trace:Array=[];var stalled:=0;var horizontal_hits:Array=[]
	for burst in 60:
		if not walker.active:break
		var current:Vector3=walker.body.position
		var flat:=Vector3(target.x-current.x,0,target.z-current.z)
		if flat.length()<.12 and absf(target.y-current.y)<.20 and walker.body.is_on_floor():
			walk_evidence.append({"asset":context,"segment":label,"target":Walk._xyz(target),"actual":Walk._xyz(current),"local_actual":Walk._xyz(frame.affine_inverse()*current),"grounded":true,"reached":true,"trace":trace})
			check(true,"actual capsule reaches "+label);return true
		var direction:=flat.normalized()
		var result:=await call_tool("move_editor_walk",{"direction":[direction.x,-direction.z],"duration":clampf(flat.length()/3.5,.025,.35)})
		if not result.get("ok",false):break
		for tick in 180:
			await physics_frame
			if walker.active:
				for hit_index in walker.body.get_slide_collision_count():
					var hit:KinematicCollision3D=walker.body.get_slide_collision(hit_index)
					if absf(hit.get_normal().y)>.7:continue
					var hit_body:Node=hit.get_collider() as Node
					var hit_visual:Node=hit_body.get_meta("visual",null) if hit_body!=null else null
					horizontal_hits.append({"normal":Walk._xyz(hit.get_normal()),"local_position":Walk._xyz(frame.affine_inverse()*hit.get_position()),"extras":hit_visual.get_meta("extras",{}) if hit_visual!=null else {}})
					if horizontal_hits.size()>8:horizontal_hits.pop_front()
			if not walker.active or walker._seconds<=0:break
		for tick in 6:await physics_frame
		if not walker.active:break
		var position:Vector3=walker.body.position
		trace.append({"local":Walk._xyz(frame.affine_inverse()*position),"grounded":walker.body.is_on_floor()})
		stalled=stalled+1 if position.distance_to(current)<.02 else 0
		if stalled>=4:break
	var actual:Vector3=walker.body.position if walker.active else Vector3.INF
	var contacts:Array=[]
	if walker.active:
		for i in walker.body.get_slide_collision_count():
			var contact:KinematicCollision3D=walker.body.get_slide_collision(i)
			var collider:Node=contact.get_collider() as Node
			var visual:Node=collider.get_meta("visual",null) if collider!=null else null
			contacts.append({"normal":Walk._xyz(contact.get_normal()),"position":Walk._xyz(contact.get_position()),"extras":visual.get_meta("extras",{}) if visual!=null else {}})
	walk_evidence.append({"asset":context,"segment":label,"target":Walk._xyz(target),"actual":Walk._xyz(actual),"local_actual":Walk._xyz(frame.affine_inverse()*actual),"reached":false,"trace":trace,"contacts":contacts,"last_horizontal_contacts":horizontal_hits})
	print("WALK_PATH_BLOCKED ",JSON.stringify(walk_evidence[-1]))
	check(false,"actual capsule reaches "+label);return false

func review_walk(name_:String,id:String)->void:
	var original_size:Array=editor._doc._find(id).get("size",[1,1,1]).duplicate()
	if "--walk-unit-scale" in OS.get_cmdline_user_args():await call_tool("set_object_transform",{"id":id,"size":[1,1,1]})
	var route:=walk_routes(name_);var frame:=Imported.frame(editor._doc._find(id))
	var states:Array=component_rows(id).duplicate(true)
	for row:Dictionary in states:
		if row.open!=1.0:await call_tool("set_building_component_state",{"id":id,"component_id":row.id,"open":1.0})
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var start:Vector3=frame*route_vec(route.start)
	var entered:=await call_tool("set_editor_walk_mode",{"enabled":true,"position":Walk._xyz(start)})
	if entered.get("ok",false):
		await call_tool("set_editor_walk_view",{"yaw":0,"pitch":-15,"distance":3.5})
		for tick in 12:await physics_frame
		var okay:=await walk_to(frame*route_vec(route.inside),frame,"main entrance inward")
		if okay:okay=await walk_to(start,frame,"main entrance outward")
		if okay:okay=await walk_to(frame*route_vec(route.inside),frame,"main entrance inward before stair approach")
		for i in route.upper.size():
			if not okay:break
			okay=await walk_to(frame*route_vec(route.upper[i]),frame,"upper route waypoint "+str(i))
		if okay:
			for tick in 60:await physics_frame
			check(editor._walk_mode.body.is_on_floor() and absf(editor._walk_mode.body.position.y-(frame*route_vec(route.upper[-1])).y)<.20,"actual capsule remains supported on reached upper floor")
		await call_tool("set_editor_walk_mode",{"enabled":false})
	check(editor._doc._undo.size()==history and equivalent(before,editor._doc.recovery_snapshot()),"real capsule traversal does not edit source geometry or author history")
	for row:Dictionary in states:
		if component_state(id,row.id)!=float(row.open):await call_tool("set_building_component_state",{"id":id,"component_id":row.id,"open":row.open})
	if "--walk-unit-scale" in OS.get_cmdline_user_args():await call_tool("set_object_transform",{"id":id,"size":original_size})

func review_formal_core(id:String,source:Dictionary,map_path:String)->void:
	check(editor._doc._find(id).asset_path==source.path,"formal readback places the actual catalog source path without a temporary source copy")
	var listed:=await call_tool("list_building_components",{"id":id})
	var rows:Array=listed.get("components",[])
	check(not rows.is_empty(),"formal source retains independent editable doors")
	if rows.is_empty():return
	var component:String=rows[0].id
	await call_tool("select_objects",{"ids":[id]})
	check(editor._selection_tools.ids==[id] and editor._inspector.model_component_panel.visible,"formal instance is selectable and exposes shared UI component controls")
	var previous:=component_state(id,component);var desired:=1.0 if previous<.5 else 0.0
	var history:int=editor._doc._undo.size()
	await call_tool("set_building_component_state",{"id":id,"component_id":component,"open":desired})
	check(component_state(id,component)==desired and editor._doc._undo.size()==history+1,"formal door opening is a single shared transaction")
	check_colliders(id)
	await call_tool("undo");check(component_state(id,component)==previous,"formal native door undo restores previous pose")
	await call_tool("redo");check(component_state(id,component)==desired,"formal native door redo restores changed pose")
	await call_tool("set_object_properties",{"ids":[id],"locked":true})
	await atomic_reject("set_building_component_state",{"id":id,"component_id":component,"open":previous})
	await call_tool("set_object_properties",{"ids":[id],"locked":false})
	await call_tool("save_world")
	await call_tool("open_world",{"path":map_path})
	check(await idle(),"temporary map referencing formal native source reopens")
	check_native_view(id)
	check(editor._doc._find(id).asset_path==source.path and component_state(id,component)==desired,"formal original source and actual changed hinge survive save/reopen")
	check_colliders(id)
	check(FileAccess.get_sha256(source.path)==source.sha256,"formal GLB remains byte-identical")
	check(FileAccess.get_sha256(formal_catalog_path)==formal_catalog_sha,"formal catalog remains byte-identical")

func review_one(name_:String,library:Variant)->void:
	context=name_
	var source:=source_for(name_)
	check(not source.is_empty() and FileAccess.file_exists(source.get("path","")),"candidate source exists")
	if source.is_empty() or not FileAccess.file_exists(source.get("path","")):return
	check(FileAccess.get_sha256(source.path)==source.sha256,"candidate matches recorded complete GLB SHA")
	if FileAccess.get_sha256(source.path)!=source.sha256:return
	# Candidate mode imports into a fully isolated content root. Formal mode
	# verifies the existing catalog/native source and never calls import_file.
	var imported:Dictionary
	if formal_library:
		var matches:Array=library.entries.filter(func(entry):return str(entry.get("asset_path","")).replace("\\","/").simplify_path()==str(source.path).replace("\\","/").simplify_path())
		check(matches.size()==1,"formal default library discovers exactly the requested original source")
		if matches.size()!=1:return
		var identity:Dictionary=Library._verified_compiled_identity(source.path)
		check(not identity.is_empty() and identity.get("source_sha")==source.sha256,"formal global native identity verifies source and payload SHA")
		imported={"ok":true,"entry":matches[0],"compiled_asset":{"ok":not identity.is_empty(),"reused":true,"identity":identity}}
	else:imported=library.import_file(source.path)
	check(imported.ok,"production AssetLibrary source available")
	if not imported.ok:print(imported);return
	var entry:Dictionary=imported.entry
	var compilation:Dictionary=imported.get("compiled_asset",{})
	check(compilation.get("ok",false),"production native compilation succeeds; raw GLB fallback is not native acceptance")
	if not compilation.get("ok",false):
		source_evidence.append({"name":name_,"source":source,"imported_path":entry.asset_path,"compiled":compilation,"cache_directory":Compiled.directory(),"cache_index":Compiled.index_path(entry.asset_path)})
		print("NATIVE_REQUIRED ",JSON.stringify(source_evidence[-1]));return
	check(Imported.valid_descriptor(entry.get("model_building")),"native scene supplies explicit room and member contract")
	if not Imported.valid_descriptor(entry.get("model_building")):return
	var native_index:=Compiled.index_path(entry.asset_path)
	source_evidence.append({"name":name_,"source":source,"imported_path":entry.asset_path,"imported_sha256":FileAccess.get_sha256(entry.asset_path),"descriptor":entry.model_building,"compiled":compilation,"cache_index":native_index,"native_manifest":JSON.parse_string(FileAccess.get_file_as_string(native_index))})
	var map_path:=directory.path_join(name_+".gltf")
	var empty:=Doc.new();check(empty.save(map_path)==OK,"new isolated map saved")
	await call_tool("open_world",{"path":map_path,"discard_changes":true})
	check(await idle(),"editor load completed before operations")
	# Unowned temporary maps intentionally clear the editor's scope on open.
	# Use a fresh catalog reader so that clearing it cannot mutate the separate
	# importer owner used by later candidates in this test.
	editor._assets=Library.new(library.directory);editor._shared_assets=[];editor._refresh_palette()
	var placed:=await call_tool("place_asset",{"asset_id":entry.asset_path,"position":[0,0,0]})
	if placed.get("ids",[]).is_empty():return
	var id:String=placed.ids[0]
	check(await idle(),"actual model and picking geometry ready")
	check_native_view(id)
	check(editor._doc.records.size()==1 and editor._doc._find(id).has("model_building"),"one author record retains full native building semantics")
	if formal_library:
		await review_formal_core(id,source,map_path);return
	await call_tool("set_object_transform",{"id":id,"rotation":[0,23,0],"size":[1.1,1,.9]})
	var listed:=await call_tool("list_building_components",{"id":id})
	var closed:Array=listed.get("components",[]).filter(func(row):return is_zero_approx(float(row.open)))
	check(not closed.is_empty(),"actual model has independent closed hinged components")
	if closed.is_empty():return
	var component:String=closed[0].id
	await call_tool("select_objects",{"ids":[id]})
	check(editor._inspector.model_component_panel.visible,"shared UI exposes actual imported doors")
	var history:int=editor._doc._undo.size()
	await call_tool("set_building_component_state",{"id":id,"component_id":component,"open":1.0})
	check(editor._doc._undo.size()==history+1 and component_state(id,component)==1.0,"HTTP opening is one undo transaction with real transformed members")
	check_colliders(id)
	await atomic_reject("set_building_component_state",{"id":id,"component_id":"missing_component","open":1.0})
	await atomic_reject("set_building_component_state",{"id":id,"component_id":component,"open":2.0})
	await call_tool("undo");check(component_state(id,component)==0.0,"undo restores closed native door")
	await call_tool("redo");check(component_state(id,component)==1.0,"redo restores opened native door")
	await call_tool("set_object_properties",{"ids":[id],"locked":true})
	await atomic_reject("set_building_component_state",{"id":id,"component_id":component,"open":0.0})
	await call_tool("set_object_properties",{"ids":[id],"locked":false})
	await call_tool("set_object_properties",{"ids":[id],"hidden":true})
	await atomic_reject("set_building_component_state",{"id":id,"component_id":component,"open":0.0})
	await call_tool("set_object_properties",{"ids":[id],"hidden":false})
	var record:Dictionary=editor._doc._find(id)
	var levels:Array=[]
	for part:Dictionary in record.model_building.members.values():
		var value:float=part.floor_y
		if part.role=="floor" and not levels.has(value):levels.append(value)
	levels.sort()
	check(levels.size()>=2,"actual building describes at least two independently viewable levels")
	if levels.size()>=2:
		var before:Dictionary=record.duplicate(true)
		var physical_before:=walk_members(id)
		var base:float=(Imported.frame(record)*Vector3(0,levels[1],0)).y
		var band:float=(levels[2]-levels[1]) if levels.size()>2 else maxf(1.0,levels[1]-levels[0])
		await call_tool("set_floor_view",{"isolation":true,"base_height":base,"floor_height":band,"outside":"hide"})
		check(equivalent(editor._doc._find(id),before),"floor isolation changes no authored geometry, hinge state or collision contract")
		check_visibility(id,levels[0],levels[1])
		check_floor_collision(id,physical_before)
		await call_tool("select_objects",{"ids":[id]})
		check(editor._selection_tools.ids==[id],"upper level remains selectable as its single containing building")
		var lower:Array=(await call_tool("list_building_components",{"id":id})).get("components",[]).filter(func(row):return is_equal_approx(float(row.floor_y),float(levels[0])))
		check(not lower.is_empty() and lower.all(func(row):return not row.get("editable",true)),"lower floor controls disabled in isolated upper view")
		if not lower.is_empty():await atomic_reject("set_building_component_state",{"id":id,"component_id":lower[0].id,"open":.5})
		await call_tool("set_floor_view",{"outside":"dim"})
		check_floor_collision(id,physical_before)
		await call_tool("set_floor_view",{"base_height":1000,"outside":"hide"})
		check_floor_collision(id,physical_before,true)
		await atomic_reject("select_objects",{"ids":[id]})
		await atomic_reject("set_building_component_state",{"id":id,"component_id":component,"open":.5})
		await call_tool("save_world")
		await call_tool("open_world",{"path":map_path})
		check(await idle(),"floor-excluded building reopens through sliced load-job publication")
		check_native_view(id)
		check_floor_collision(id,physical_before,true)
		editor._assets=Library.new(library.directory);editor._shared_assets=[];editor._refresh_palette()
		await call_tool("set_floor_view",{"isolation":false})
		check_colliders(id)
	await review_walk(name_,id)
	# Real UI signal reaches the same business operation as HTTP.
	await call_tool("set_building_component_state",{"id":id,"component_id":component,"open":0.0})
	await call_tool("select_objects",{"ids":[id]})
	editor._inspector.model_component_panel.refresh()
	var button:Button=null
	for child:Node in editor._inspector.model_component_panel.get_children():
		if child is Button and child.text.ends_with(component.get_file()):button=child;break
	check(button!=null and not button.disabled,"shared UI has enabled button for tested actual hinge")
	if button!=null:
		history=editor._doc._undo.size();button.pressed.emit();await settle()
		check(editor._doc._undo.size()==history+1 and component_state(id,component)==1.0,"UI button commits exactly the same one-step opening transaction")
	var second:=await call_tool("place_asset",{"asset_id":entry.asset_path,"position":[50,0,0]})
	if not second.get("ids",[]).is_empty():
		var second_id:String=second.ids[0]
		check(component_state(second_id,component)==0.0 and component_state(id,component)==1.0,"two instances sharing native source keep independent door state")
		var first_ids:=Imported.member_ids(editor._doc._find(id));var second_ids:=Imported.member_ids(editor._doc._find(second_id))
		check(first_ids.all(func(member):return member not in second_ids),"every duplicated native mesh has an independent instance identity")
	await call_tool("save_world")
	await call_tool("open_world",{"path":map_path})
	check(await idle(),"saved real native map fully reopens")
	check_native_view(id)
	check(editor._doc._find(id).get("model_building_states",{}).get(component)==1.0 and component_state(id,component)==1.0,"new state field and transformed actual hinge survive resource save/reopen")
	check(not editor._doc._find(id).has("model_component_states"),"new models do not rewrite the legacy guild state field")
	check_colliders(id)
	check(FileAccess.get_sha256(source.path)==source.sha256,"candidate source remains byte-identical after HTTP and UI operations")

func run()->void:
	if "--source-preflight-only" in OS.get_cmdline_user_args():
		for name_:String in ["guardhouse","church","watermill"]:
			context=name_;var source:=source_for(name_)
			check(not source.is_empty() and FileAccess.get_sha256(source.get("path",""))==source.get("sha256"),"exact source SHA before native import")
			if source.is_empty():continue
			var descriptor:=Imported.source_descriptor(source.path,source.sha256)
			check(Imported.valid_descriptor(descriptor),"actual GLB source has complete stable UUID/room/hinge contract")
			if not descriptor.is_empty():
				source_evidence.append({"name":name_,"source":source,"cpu_source_descriptor":descriptor})
				check(descriptor.members.values().any(func(part):return part.role=="roof") and not descriptor.fixtures.is_empty(),"actual source retains roof semantics and moving fixtures")
		finish();return
	create_timer(1800).timeout.connect(func():check(false,"bounded whole test timeout");finish())
	Engine.max_fps=60;root.size=Vector2i(1100,800);rpc_timeout_ms=240000
	formal_library="--formal-library" in OS.get_cmdline_user_args()
	if not formal_library:
		var manager:=root.get_node("AssetManager")
		previous_content_override=manager.content_root_override
		isolated_content_root=Paths.external_root().path_join("review_fixtures/landmarks_http_%d"%Time.get_ticks_usec())
		DirAccess.make_dir_recursive_absolute(isolated_content_root)
		manager.content_root_override=isolated_content_root
	else:
		formal_catalog_path=Paths.external_root().path_join("packs/default/assets/library.json")
		formal_catalog_sha=FileAccess.get_sha256(formal_catalog_path)
	directory=Paths.cache_directory("imported_buildings_http_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var start:=directory.path_join("empty.gltf");var doc:=Doc.new();check(doc.save(start)==OK,"temporary initial map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=start;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor)
	check(await idle(),"initial editor ready")
	var probe:=TCPServer.new();port=29990
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"current 3D real loopback HTTP service starts")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var names:Array=(await rpc("tools/list")).get("result",{}).get("tools",[]).map(func(item):return item.name)
	for name_:String in ["list_building_components","set_building_component_state","set_floor_view","place_asset","save_world","open_world","set_editor_walk_mode","move_editor_walk","set_editor_walk_view"]:check(names.has(name_),"current 3D discovery includes "+name_)
	var library:=Library.new(formal_catalog_path.get_base_dir() if formal_library else directory.path_join("assets"));var only:=""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):only=argument.trim_prefix("--only=")
	if not only.is_empty() and only not in ["guardhouse","church","watermill"]:check(false,"invalid --only selector");finish();return
	for name_:String in ["guardhouse","church","watermill"]:
		if only.is_empty() or only==name_:await review_one(name_,library)
	finish()

func finish()->void:
	if finalizing:return
	finalizing=true
	DirAccess.make_dir_recursive_absolute(REPORT_ROOT)
	var report:Dictionary={"checks":checks,"failed":failed,"passed":checks.size()-failed,"sources":source_evidence,"walk_evidence":walk_evidence,"temporary_directory":directory,"isolated_content_root":isolated_content_root,"native_required":true,"formal_library_readback":formal_library,"formal_catalog_path":formal_catalog_path,"formal_catalog_sha_before":formal_catalog_sha,"formal_catalog_sha_after":FileAccess.get_sha256(formal_catalog_path) if formal_library else "","test_script_sha":FileAccess.get_sha256("res://tools/test_imported_buildings_http_20261016.gd"),"formal_map_modified":false,"formal_catalog_modified":false,"display_server":DisplayServer.get_name()}
	var destination:=REPORT_ROOT.path_join("http_%d.json"%Time.get_ticks_usec())
	var file:=FileAccess.open(destination,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	if is_instance_valid(editor):
		if editor._mcp!=null:editor._mcp.stop()
		editor.queue_free()
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=null;session.world3d_editor_path=""
	if not isolated_content_root.is_empty():root.get_node("AssetManager").content_root_override=previous_content_override
	print("IMPORTED_BUILDINGS_HTTP failed=",failed," report=",destination," fixture=",directory)
	quit(0 if failed==0 else 1)
