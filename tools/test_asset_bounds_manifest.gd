extends SceneTree
const Manifest = preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
var failures := 0
var passed := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ",label)
	if ok: passed += 1
	else: failures += 1
func data() -> Dictionary:
	return {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"translation":[10,2,0],"children":[1]},{"mesh":0,"scale":[2,1,1]}],"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[-1,0,-2],"max":[1,4,2]}],"bufferViews":[{"buffer":0,"byteLength":36}],"buffers":[{"byteLength":36}]}
func write(path: String, value: Dictionary) -> void:
	var bytes := JSON.stringify(value).to_utf8_buffer()
	while bytes.size()%4: bytes.append(32)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67); file.store_32(2); file.store_32(bytes.size()+64)
	file.store_32(bytes.size());file.store_32(0x4e4f534a);file.store_buffer(bytes)
	file.store_32(36);file.store_32(0x004e4942)
	file.store_buffer(PackedFloat32Array([-1,0,-2,1,4,2,0,1,0]).to_byte_array());file.close()
func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	if "--town" in OS.get_cmdline_user_args(): town(); return
	var directory := Paths.cache_directory("bounds_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("model.glb"); write(path,data())
	var result := Manifest.read(path)
	check(result.known and result.local_bounds == AABB(Vector3(8,2,-2),Vector3(4,4,4)),"node hierarchy, translation and local scale bounds")
	check(result.mesh_nodes.size()==1 and result.mesh_nodes[0].id=="node:1" and result.mesh_nodes[0].transform.origin==Vector3(10,2,0),"stable mesh node index and model local transform")
	var pose := {"position":[100,0,0],"rotation":[0,90,0],"size":[2,3,4],"bounds_position":[999,999,999],"bounds_size":[0,0,0]}
	var placed := Manifest.apply_record(result,pose)
	var expected: AABB = Transform3D(Basis.from_euler(Vector3(0,PI/2,0)).scaled_local(Vector3(2,3,4)),Vector3(100,0,0))*result.local_bounds
	check(placed.known and placed.world_bounds.is_equal_approx(expected) and result.world_bounds==result.local_bounds,"record scale applies to source geometry, authored bounds ignored, manifest immutable")
	var modified := data(); modified.nodes[0]={"matrix":[0,0,-1,0,0,1,0,0,1,0,0,0,5,0,0,1],"children":[1]}
	var matrix := Manifest.from_json(modified,36)
	check(matrix.known and matrix.local_bounds.is_equal_approx(AABB(Vector3(3,0,-2),Vector3(4,4,4))),"column-major affine matrix transforms correct corners")
	for mutation in ["skin","animation","morph","sparse","min","parent","cycle","scene_parent","scene_index","matrix_trs","perspective","quaternion","overflow","accessor_range","uri","unknown_extension","unknown_node","required_extension","nonfinite_bounds","reversed_bounds","fractional_index","stride","view_range","duplicate_scene_root","primitive_mode"]:
		modified=data()
		match mutation:
			"skin": modified.nodes[1].skin=0
			"animation": modified.animations=[{}]
			"morph": modified.meshes[0].primitives[0].targets=[{}]
			"sparse": modified.accessors[0].sparse={}
			"min": modified.accessors[0].erase("min")
			"parent": modified.nodes[0].children=[1,1]
			"cycle": modified.nodes[1].children=[0]
			"scene_parent": modified.scenes[0].nodes=[1]
			"scene_index": modified.scene=9
			"matrix_trs": modified.nodes[0].matrix=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
			"perspective": modified.nodes[0]={"matrix":[1,0,0,1,0,1,0,0,0,0,1,0,0,0,0,1],"children":[1]}
			"quaternion": modified.nodes[0].rotation=[0,0,0,2]
			"overflow": modified.nodes[0].scale=[1e12,1e12,1e12]
			"accessor_range": modified.accessors[0].count=4
			"uri": modified.buffers[0].uri="other.bin"
			"unknown_extension": modified.nodes[1].extensions={"EXT_unknown":{}}
			"unknown_node": modified.nodes[1].transform=[0]
			"required_extension": modified.extensionsRequired=["KHR_materials_transmission"]
			"nonfinite_bounds": modified.accessors[0].min=[NAN,0,0]
			"reversed_bounds": modified.accessors[0].min=[3,0,0]
			"fractional_index": modified.nodes[1].mesh=.5
			"stride": modified.bufferViews[0].byteStride=10
			"view_range": modified.bufferViews[0].byteLength=40
			"duplicate_scene_root": modified.scenes[0].nodes=[0,0]
			"primitive_mode": modified.meshes[0].primitives[0].mode=9
		check(not Manifest.from_json(modified,36).known,"unknown/eager: "+mutation)
	modified=data(); modified.materials=[{"extensions":{"KHR_materials_specular":{"specularFactor":.5}}}]; modified.extensionsUsed=["KHR_materials_specular"]
	check(Manifest.from_json(modified,36).known,"optional static material metadata does not alter geometry eligibility")
	modified=data();modified.extensionsUsed=null;modified.extensionsRequired=null
	check(Manifest.from_json(modified,36).known,"native null extension declarations enable no extensions")
	modified=data();modified.nodes[0].extras={"rmmo_format":"rmmo_gltf_map","rmmo_records":[]}
	check(not Manifest.from_json(modified,36).known,"native map identity is eager rather than worker-safe")
	modified=data();modified.nodes[1].extras={"wrapped":{"rmmo_records":[]}}
	check(not Manifest.from_json(modified,36).known,"nested native identity cannot evade qualification")
	var changed_pose:=pose.duplicate();changed_pose.tree_settings={}
	check(not Manifest.apply_record(result,changed_pose).known,"record geometry overrides cannot borrow unchanged model bounds")
	modified=data(); modified.nodes.append({"translation":[500,0,0],"mesh":0}); modified.scenes.append({"nodes":[2]}); modified.scene=1
	check(Manifest.from_json(modified,36).local_bounds==AABB(Vector3(499,0,-2),Vector3(2,4,4)),"selected scene only; other valid root excluded")
	modified.nodes.append({"children":[4]}); modified.nodes.append({"children":[3]})
	check(not Manifest.from_json(modified,36).known,"unreachable cyclic graph also rejected")
	pose.size=[INF,1,1]; check(not Manifest.apply_record(result,pose).known,"nonfinite record transform eager")
	FileAccess.open(path,FileAccess.WRITE).store_string("broken")
	check(not Manifest.read(path).known and not Manifest.read(path.get_basename()+".gltf").known,"malformed file and external glTF eager")
	DirAccess.remove_absolute(path);DirAccess.remove_absolute(directory)
	print("ASSET_BOUNDS_MANIFEST passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)

func town() -> void:
	var source = preload("res://scripts/world3d/document_source_snapshot.gd").read_file("D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf")
	var Cursor = preload("res://scripts/world3d/document_open_cursor.gd")
	var native: int = Cursor.native_root(source._data)
	if native<0: quit(1);return
	var extra: Dictionary = source._data.nodes[native].extras
	var restored: Dictionary = Cursor.hydrate_references(extra,source._path,Paths.external_root())
	if not restored.ok: print(restored);quit(1);return
	var spawn: Array = extra.get("spawn",[0,.9,4])
	var center := Vector2i(floori(float(spawn[0])/32),floori(float(spawn[2])/32))
	var manifests := {}; var near := [{},{},{}]; var eager := {}; var issues := {}; var instances := 0; var nearest := []
	var started := Time.get_ticks_usec()
	for record: Dictionary in restored.extras.rmmo_records:
		if record.get("kind")!="asset" or record.has("house_prefab"): continue
		instances+=1
		var path: String=record.asset_path
		if not manifests.has(path): manifests[path]=Manifest.read(path)
		var row: Dictionary=Manifest.apply_record(manifests[path],record)
		if not row.known:
			eager[path]=true;issues[path]=row.reason
			for bag: Dictionary in near: bag[path]=true
			continue
		var bounds: AABB=row.world_bounds
		var x_distance := maxf(maxf(bounds.position.x-float(spawn[0]),float(spawn[0])-bounds.end.x),0)
		var z_distance := maxf(maxf(bounds.position.z-float(spawn[2]),float(spawn[2])-bounds.end.z),0)
		nearest.append({"uuid":record.uuid,"path":path,"distance_xz":Vector2(x_distance,z_distance).length(),"bounds_min":[bounds.position.x,bounds.position.y,bounds.position.z],"bounds_max":[bounds.end.x,bounds.end.y,bounds.end.z]})
		var low:=Vector2i(floori(bounds.position.x/32),floori(bounds.position.z/32));var high:=Vector2i(floori(bounds.end.x/32),floori(bounds.end.z/32))
		for radius in range(1,4):
			if low.x<=center.x+radius and high.x>=center.x-radius and low.y<=center.y+radius and high.y>=center.y-radius:near[radius-1][path]=true
	var known:=0
	for row: Dictionary in manifests.values():
		if row.known: known+=1
	nearest.sort_custom(func(a,b):return a.distance_xz<b.distance_xz)
	var report:={"spawn":spawn,"chunk":[center.x,center.y],"unique_models":manifests.size(),"known_models":known,"unknown_models":manifests.size()-known,"instances":instances,"unknown_reasons":issues,"near_unique_radii_1_2_3":near.map(func(bag):return bag.size()),"eager_unique":eager.size(),"manifest_and_placement_ms":(Time.get_ticks_usec()-started)/1000.,"nearest_instances":nearest.slice(0,3),"source_unchanged":source.matches_disk()}
	print(JSON.stringify(report))
	FileAccess.open("D:/code/rmmo_runtime/review_artifacts/game_asset_import_audit_20261008/town_bounds.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit(0 if report.source_unchanged else 1)
