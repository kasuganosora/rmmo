extends SceneTree
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Components=preload("res://scripts/world3d/model_components.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const Settings=preload("res://scripts/world3d/editor_view_settings.gd")
const Bounds=preload("res://scripts/world3d/asset_bounds_manifest.gd")
var checks:Array=[]
var failed:=0

func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"check":label})
	if not ok:failed+=1;push_error(label)

func make_model()->Node3D:
	var model:=Node3D.new();model.name="Authored"
	model.set_meta("extras",{"rmmo_model_components":{"version":1},"rmmo_building":{"version":1,"regions":[{"id":"lower","floor":0,"min":[-3,.2,-4],"max":[3,3.2,4]},{"id":"upper","floor":1,"min":[-3,3.4,-4],"max":[3,6.4,4]}]}})
	for i in 4:
		var mesh:=MeshInstance3D.new();mesh.name="Piece%d"%i
		mesh.mesh=BoxMesh.new();mesh.mesh.size=Vector3(2,.15,1)
		mesh.position=Vector3(0,.2 if i<2 else 3.4,0)
		var extra:={"uuid":"Piece%d"%i,"rmmo_part":{"floor":0 if i<2 else 1,"floor_y":.2 if i<2 else 3.4,"role":"door" if i==1 else "floor","part":"level_%d"%i},"rmmo_collision":"block"}
		if i==1:
			mesh.mesh.size=Vector3(1,2,.08);mesh.position=Vector3(.5,1.2,4)
			extra.rmmo_hinge={"id":"front_door","pivot":[-.5,-1,0],"angle":100,"open":0.0}
		mesh.set_meta("extras",extra);model.add_child(mesh)
	return model

func _initialize()->void:call_deferred("run")
func run()->void:
	if "--candidate-audit" in OS.get_cmdline_user_args():audit_candidates();return
	var model:=make_model();root.add_child(model)
	var descriptor:=Imported.describe(model);descriptor.source_sha="a".repeat(64)
	check(Imported.valid_descriptor(descriptor),"complete explicit model descriptor accepted")
	var r:={"uuid":"house","kind":"asset","position":[7,2,-9],"rotation":[0,37,0],"size":[2,1.5,.7],"model_building":descriptor}
	check(Imported.valid_record(r),"rotated nonuniform imported model valid")
	var expected:=Transform3D(Basis.from_euler(Vector3(0,deg_to_rad(37),0)).scaled_local(Vector3(2,1.5,.7)),Vector3(7,2,-9))
	check(Imported.frame(r).is_equal_approx(expected),"record frame applies source-local scale before rotation")
	var bad:=r.duplicate(true);bad.model_building_states={"missing":.5}
	check(not Imported.valid_record(bad),"unknown hinge ID cannot be persisted")
	bad=r.duplicate(true);bad.model_building_states={"front_door":NAN}
	check(not Components.valid(bad),"nonfinite authored state rejected")
	bad=r.duplicate(true);bad.model_component_states={"front_door":1}
	check(not Components.valid(bad),"new contract cannot silently use legacy state field")
	check(Components.valid({"kind":"asset","model_component_states":{"legacy":1.0}}),"old guild state contract remains valid")
	bad=r.duplicate(true);bad.model_building.regions[0].max[0]=-4
	check(not Imported.valid_record(bad),"inverted room bounds rejected")
	bad=r.duplicate(true);bad.size=[-1,1,1]
	check(not Imported.valid_record(bad),"mirrored building cannot silently invert room volumes")
	var damaged:=make_model();damaged.get_child(0).get_meta("extras").erase("rmmo_part")
	check(Imported.describe(damaged).is_empty(),"partial mesh semantics reject whole opt-in")
	damaged.free()
	var originals:Dictionary={}
	for node:Node3D in model.get_children():originals[str(node.name)]=node.transform
	r.model_building_states={"front_door":1.0}
	Components.apply(model,r)
	check(not model.has_meta("model_components_error"),"generic adaptation works without guild delivery tag")
	var rows:=Components.rows(model)
	check(rows.size()==1 and rows[0].id=="front_door" and rows[0].open==1.0,"shared component API lists actual opened independent door")
	for node:MeshInstance3D in model.get_children():
		var e:Dictionary=node.get_meta("extras")
		check(e.building.id=="house","every visual carries exact authored building owner")
		check(node.get_meta("ground_batch_record").building.floor==e.rmmo_part.floor,"render batches preserve each explicit floor")
		if e.has("fixture"):
			check(node.transform.is_equal_approx(Fixtures.pose(originals.Piece1,e.fixture,1)),"door uses its local real hinge under parent transform")
		else:check(node.transform==originals[str(node.name).trim_prefix("house__")],"unrelated floors do not move with door")
	var floor_settings:={"isolation":true,"base_height":6.5,"floor_height":2,"outside":"hide"}
	check(Settings.contains(r,floor_settings),"upper floor selection retains containing asset")
	check(not Imported.floor_in_view(r,{"floor_y":.2},floor_settings),"lower door not editable from isolated upper floor")
	check(Imported.floor_in_view(r,{"floor_y":3.4},floor_settings),"scaled upper floor uses correct world elevation")
	var map:=Node3D.new();root.add_child(map);map.set_meta("extras",{"rmmo_records":[r]})
	var cutaway=preload("res://scripts/world3d/building_cutaway.gd").new();cutaway.bind(map)
	check(cutaway.locate(expected*Vector3(0,.2,0)).get("floor",-1)==0,"cutaway resolves actual lower room")
	check(cutaway.locate(expected*Vector3(0,3.4,0)).get("floor",-1)==1,"cutaway resolves actual upper room")
	check(cutaway.locate(expected*Vector3(0,.2,5)).is_empty(),"outside platform is not an invented room")
	await initial_stream_cutaway()
	var box:=AABB(Vector3(-.15,-1,-.06),Vector3(1.8,2.2,.18))
	for angle in [-173.0,-95.0,77.0,180.0]:
		for initial in [0.0,.35,1.0]:
			var hinge:={"pivot":[-.05,-1,0.03],"angle":angle,"open":initial}
			var swept:=Bounds._hinge_bounds(box,hinge)
			check(swept.known,"finite actual accessor hinge sweep")
			var contained:=true
			for i in 101:
				var pose:=Fixtures.pose(Transform3D.IDENTITY,hinge,float(i)/100-initial)
				for c in 8:
					if not swept.bounds.grow(.00001).has_point(pose*box.get_endpoint(c)):contained=false
			check(contained,"continuous door sweep covers sampled corner motion %s/%s"%[angle,initial])
	check(not Bounds._hinge_bounds(box,{"pivot":[0,0,0],"angle":INF,"open":0}).known,"invalid dynamic bounds rejected")
	source_contract()
	view_collision_policy()
	map.free();model.free()
	var directory:="D:/code/rmmo/review_artifacts/axel_landmarks_20261016/pipeline"
	DirAccess.make_dir_recursive_absolute(directory)
	var file:=FileAccess.open(directory+"/component_logic.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed},"\t"));file.close()
	print("IMPORTED_COMPONENT_LOGIC checks=",checks.size()," failures=",failed)
	quit(0 if failed==0 else 1)

func source_contract()->void:
	var maker=preload("res://tools/test_asset_bounds_manifest.gd").new()
	var data:Dictionary=maker.data()
	data.nodes[0].extras={"rmmo_model_components":{"version":1},"rmmo_building":{"version":1,"regions":[{"id":"interior","floor":0,"min":[-3,0,-3],"max":[3,5,3]}]}}
	data.nodes[1].extras={"uuid":"front_leaf","rmmo_part":{"floor":0,"floor_y":0,"role":"door","part":"front"},"rmmo_hinge":{"id":"front","pivot":[-1,0,-2],"angle":100,"open":0}}
	var directory:="D:/code/rmmo/review_artifacts/axel_landmarks_20261016/pipeline"
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory+"/source_contract_fixture.glb"
	maker.write(path,data);maker.free()
	var digest:=FileAccess.get_sha256(path);var descriptor:=Imported.source_descriptor(path,digest)
	check(Imported.valid_descriptor(descriptor),"source JSON float version yields complete bounded descriptor")
	var record:={"uuid":"fixture","kind":"asset","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"asset_path":path,"model_building":descriptor}
	check(Imported.verify_source(record),"actual source bytes certify declared rooms, members and fixtures")
	var changed:=record.duplicate(true);changed.model_building.regions[0].max[0]+=10
	check(not Imported.verify_source(changed),"valid source SHA does not authorize a forged room")
	var manifest:=Bounds.read(path);var contained:bool=manifest.known
	if manifest.known:
		var row:Dictionary=manifest.mesh_nodes[0]
		for i in 101:
			var pose:Transform3D=row.transform*Fixtures.pose(Transform3D.IDENTITY,data.nodes[1].extras.rmmo_hinge,float(i)/100)
			for corner in 8:
				if not row.bounds.grow(.00001).has_point(pose*row.mesh_bounds.get_endpoint(corner)):contained=false
	check(contained,"real GLB JSON path includes all continuous door sweep corners")
	data.nodes[0].extras.rmmo_model_components="bad"
	check(Bounds.from_json(data,36).known,"malformed unrelated opt-in marker cannot crash static bounds parser")
	FileAccess.open(path,FileAccess.WRITE).store_string("changed")
	check(not Imported.verify_source(record),"cached descriptor cannot hide changed source bytes")
	DirAccess.remove_absolute(path)

func view_collision_policy()->void:
	var editor=preload("res://scripts/world_editor/world_editor.gd").new()
	var model:=make_model();editor.add_child(model)
	var mesh:MeshInstance3D=model.get_child(0)
	mesh.visible=false;mesh.set_meta("editor_floor_excluded",true);mesh.set_meta("editor_floor_physical",true)
	check(editor._body_node_enabled(mesh) and editor._body_layers(mesh)==1<<20,"floor-hidden physical mesh retains only walk collision")
	mesh.visible=true
	check(editor._body_layers(mesh)==1<<20,"dimmed outside-floor mesh is not selectable")
	mesh.set_meta("editor_floor_excluded",false)
	check(editor._body_layers(mesh)==(1 | 1<<20),"visible current-floor part remains selectable and physical")
	model.visible=false;model.set_meta("editor_floor_excluded",true);model.set_meta("editor_floor_physical",true)
	check(editor._body_node_enabled(model) and editor._body_layers(mesh)==1<<20,"asset wholly outside isolated floor keeps physical descendants only")
	mesh.get_meta("extras").rmmo_collision="none"
	check(editor._body_layers(mesh)==0,"hidden nonphysical pane creates no invisible pick surface")
	editor.free()

func initial_stream_cutaway()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var source:=make_model();var description:=Imported.describe(source);description.source_sha="a".repeat(64);source.free()
	var record:={"uuid":"initial","kind":"asset","position":[100,0,100],"rotation":[0,0,0],"size":[1,1,1],"model_building":description}
	scene.set_meta("extras",{"rmmo_records":[record]})
	var box:=BoxMesh.new();box.size=Vector3(4,.2,4)
	var upper:={"uuid":"initial__slab","mesh":box,"transform":Transform3D(Basis.IDENTITY,Vector3(100,3.4,100)),"extras":{"building":{"id":"initial","floor":1,"role":"floor","part":"upper"}}}
	# A lamp/LOD has semantic membership without a merge record; late append
	# must use the same path as initial bind and preserve its authored visibility.
	var lamp:=upper.duplicate(true);lamp.uuid="initial__lamp";lamp.extras.building.role="furniture";lamp.extras.rmmo_model_light={}
	scene.set_meta("stream_library",[upper])
	var mesh:=MeshInstance3D.new();mesh.mesh=box;mesh.transform=upper.transform;scene.add_child(mesh)
	var lamp_mesh:=MeshInstance3D.new();lamp_mesh.mesh=box;lamp_mesh.transform=upper.transform;lamp_mesh.visible=false;scene.add_child(lamp_mesh)
	var body:=StaticBody3D.new();body.transform=upper.transform;body.set_meta("uuid",upper.uuid);scene.add_child(body)
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=box.size;body.add_child(shape)
	scene.set_meta("stream_meshes",{upper.uuid:mesh,lamp.uuid:lamp_mesh});scene.set_meta("stream_bodies",{upper.uuid:body})
	var cut:=preload("res://scripts/world3d/building_cutaway.gd").new();cut.bind(scene);cut.enabled=true
	check(cut.buildings.initial.parts.size()==1,"initial loaded imported members registered before any arrival callback")
	cut.append_specs(scene,[lamp])
	check(cut.buildings.initial.parts.has(lamp.uuid),"unbatched authored lamp participates in incremental cutaway")
	await physics_frame;await physics_frame
	var room:Dictionary=cut.locate(Vector3(100,.2,100))
	var space:=scene.get_world_3d().direct_space_state
	cut.update(room,Vector3(100,1.8,100),Vector3(100,5,100),space,[],.016)
	check(not mesh.visible and cut.hidden.has(upper.uuid) and cut.hidden.has(lamp.uuid),"actual initial ray obstruction hides imported upper slab and semantic members")
	check(body.collision_layer==1 and cut.excluded.has(body.get_rid()),"camera cutaway leaves physical collision unchanged")
	cut.restore()
	check(mesh.visible and not lamp_mesh.visible,"restore retains originally hidden nonbatched members")
	scene.set_meta("stream_library",[upper,lamp]);cut.bind(scene)
	check(cut.buildings.initial.parts.size()==2,"rebind reconstructs complete already-loaded membership")
	cut.update(cut.locate(Vector3(100,.2,100)),Vector3(100,1.8,100),Vector3(100,5,100),space,[],.016)
	check(not mesh.visible,"cutaway remains effective after rebind without a new arrival")
	cut.restore();scene.free()

func audit_candidates()->void:
	var result:Array=[]
	for entry:Array in [["church","v3"],["guardhouse","v4"],["watermill","v9"]]:
		var path:="D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/%s/%s/axel_%s.glb"%[entry[0],entry[1],entry[0]]
		for argument:String in OS.get_cmdline_user_args():
			if argument.begins_with("--"+str(entry[0])+"="):path=argument.substr(argument.find("=")+1)
		var digest:=FileAccess.get_sha256(path);var descriptor:=Imported.source_descriptor(path,digest)
		check(Imported.valid_descriptor(descriptor),"complete exported source descriptor "+entry[0])
		var row:={"asset":entry[0],"path":path,"sha256":digest,"ok":not descriptor.is_empty(),"member_count":descriptor.get("members",{}).size(),"fixtures":descriptor.get("fixtures",{}).size(),"rooms":descriptor.get("regions",[]).size()}
		result.append(row);print(JSON.stringify(row))
	var file:=FileAccess.open("D:/code/rmmo/review_artifacts/axel_landmarks_20261016/pipeline/source_contracts.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"candidates":result,"failed":failed},"\t"));file.close()
	quit(0 if failed==0 else 1)
