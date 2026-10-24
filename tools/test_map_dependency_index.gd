extends SceneTree
## Headless CPU-only coverage. All author files and resources are temporary.
const Index = preload("res://scripts/world3d/map_dependency_index.gd")
const Store = preload("res://scripts/world3d/map_resource_store.gd")
const Format = preload("res://scripts/world3d/world_location.gd")
const Cursor = preload("res://scripts/world3d/document_open_cursor.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const ModelFixture = preload("res://tools/test_asset_bounds_manifest.gd")
var passed := 0
var failures := 0
var folder := ""
var content_root := ""
var created: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS: " if value else "FAIL: ", label)
	if value: passed += 1
	else: failures += 1
func box(id: String, x: float, size: float = 2.0) -> Dictionary:
	return {"uuid": id, "kind": "box", "position": [x, 1, 0], "rotation": [0, 0, 0], "size": [size, 2, 2], "surface_id": "block", "collision": "block"}
func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_buffer(bytes); file.close()
func fixture(name_: String, records: Array, metadata: Dictionary = {}) -> Dictionary:
	var path := folder.path_join(name_ + ".gltf")
	var stored: Dictionary = Store.write_records(records, path, content_root)
	if not stored.ok: return {}
	var extras := {"rmmo_format": Format.FORMAT, "rmmo_version": Format.FORMAT_VERSION, "rmmo_storage": Format.STORAGE, "rmmo_unit": "m", "rmmo_records": stored.records, "rmmo_resource_dependencies": stored.dependencies, "spawn": [0, 1, 0], "custom": {"complete_metadata": true}}
	extras.merge(metadata, true)
	var data := {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"extras": extras}]}
	write_bytes(path, JSON.stringify(data).to_utf8_buffer())
	created.append(path); created.append(Index.cache_path(path, content_root))
	for uri in stored.dependencies: created.append(folder.path_join(uri))
	return {"path": path, "extras": JSON.parse_string(JSON.stringify(extras))}
func replace_payload(path: String, value: Dictionary) -> void:
	var bytes := var_to_bytes(value); var output := Index.MAGIC.to_ascii_buffer()
	output.resize(49); output.encode_u64(9, bytes.size())
	var sha := Store._sha(bytes).hex_decode()
	for i in 32: output[17+i] = sha[i]
	output.append_array(bytes); write_bytes(path, output)

func run() -> void:
	# This suite deliberately supplies false stored prefab bounds and altered
	# references. Those assertions exercise the explicit diagnostic contract.
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=true
	content_root = Paths.external_root()
	folder = Paths.cache_directory("dependency_index_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var records: Array = [box("near", 0), box("border", 32, 4), box("far", 600)]
	var global := box("event", 900); global.event = {"type": "custom"}; records.append(global)
	var f := fixture("map", records)
	var digest := FileAccess.get_sha256(f.path)
	var built: Dictionary = Index.build(f.path, content_root, records, digest)
	check(built.ok, "build persistent directory from exact hydrated author snapshot")
	if not built.ok: print(built); quit(1); return
	var read: Dictionary = Index.read(f.path, content_root, digest)
	check(read.ok and read.rows.size() == 4 and not read.closure_complete, "read validates index identity without claiming far resource integrity")
	if not read.ok: print(read); quit(1); return
	var selected := Index.select(read, [AABB(Vector3(-4, -10, -4), Vector3(8, 20, 8))])
	check(selected.ok and selected.record_indices == [0, 3] and selected.deferred_indices == [1, 2], "local demand selects nearby and conservative global in original order")
	check(selected.extras.custom == f.extras.custom and selected.extras.spawn == f.extras.spawn, "subset extras preserve complete author metadata")
	check(selected.deferred_entries[0].compact_record.uuid == "border" and selected.deferred_entries[0].record_index == 1 and selected.deferred_entries[0].bounds == read.rows[1].bounds, "deferred compact records retain exact source index and real bounds")
	check(selected.dependencies.size() == 1 and selected.compact_records.size() == 2, "selected dependency closure deduplicates shared references")
	var hydrated := Cursor.hydrate_references(selected.extras, f.path, content_root)
	check(hydrated.ok and hydrated.extras.rmmo_records[0].uuid == "near" and not selected.selected_closure_verified, "ordinary resource validation verifies selected closure before use")
	var both := Index.select(read, [AABB(Vector3(-4, -1, -4), Vector3(8, 4, 8)), AABB(Vector3(598, -1, -4), Vector3(4, 4, 8))])
	check(both.record_indices == [0, 2, 3], "two demand sources pin origin and destination")
	var border := Index.select(read, [AABB(Vector3(31, -1, -1), Vector3(0, 4, 2))])
	check(border.record_indices == [1, 3] and read.rows[1].chunk_min.x == 0 and read.rows[1].chunk_max.x == 1, "cross-chunk geometry covers both chunks including exact boundary")
	check(Index.select(read, []).record_indices == [3], "no demand retains global records only")
	check(not Index.select(read, [AABB(Vector3.ZERO, Vector3(-1, 1, 1))]).ok, "negative demand extent rejected")
	check(not Index.read(f.path, folder.path_join("unrelated_root")).ok, "out-of-root map rejected")
	check(not Index.read(f.path, content_root, "0".repeat(64)).ok, "caller source SHA mismatch rejected")
	var changed: Array = records.duplicate(true); changed[0].position[0] = 1
	check(not Index.build(f.path, content_root, changed).ok, "unsaved pose cannot be indexed under old author SHA")
	changed = records.duplicate(true); changed[0].collision = "none"
	check(not Index.build(f.path, content_root, changed).ok, "unsaved definition cannot borrow reference SHA")
	var cache: String = Index.cache_path(f.path, content_root)
	var original_cache := FileAccess.get_file_as_bytes(cache)
	var corrupt := original_cache.duplicate(); corrupt[-1] ^= 1; write_bytes(cache, corrupt)
	check(not Index.read(f.path, content_root).ok, "corrupt payload rejects before decode")
	write_bytes(cache, original_cache)
	var payload: Dictionary = bytes_to_var(original_cache.slice(49)); payload.generator = "0".repeat(64); replace_payload(cache, payload)
	check(not Index.read(f.path, content_root).ok, "stale generator rejects even valid envelope checksum")
	payload = bytes_to_var(original_cache.slice(49)); payload.rows[0].order = 99; replace_payload(cache, payload)
	check(not Index.read(f.path, content_root).ok, "row ordering corruption rejects with recomputed checksum")
	write_bytes(cache, original_cache)
	var author_bytes := FileAccess.get_file_as_bytes(f.path); write_bytes(f.path, author_bytes + " ".to_utf8_buffer())
	check(not Index.read(f.path, content_root).ok, "full source bytes invalidate index even when parsed document unchanged")
	write_bytes(f.path, author_bytes)
	# Different definition ensures the missing far file is not a nearby dependency.
	var far_def := box("unique_far", 800); far_def.color = [.1, .2, .3]
	var subset_fixture := fixture("missing_far", [box("near", 0), far_def])
	var subset_index := Index.build(subset_fixture.path, content_root, [box("near", 0), far_def])
	var missing_path: String = folder.path_join(subset_fixture.extras.rmmo_records[1].rmmo_ref.uri)
	var missing_bytes := FileAccess.get_file_as_bytes(missing_path); DirAccess.remove_absolute(missing_path)
	var indexed_missing := Index.read(subset_fixture.path, content_root)
	var near_only := Index.select(indexed_missing, [AABB(Vector3(-2,-2,-2), Vector3(4,4,4))])
	check(subset_index.ok and indexed_missing.ok and Cursor.hydrate_references(near_only.extras, subset_fixture.path, content_root).ok, "index read/local hydration do not open undemanded far resource")
	var far_only := Index.select(indexed_missing, [AABB(Vector3(798,-2,-2), Vector3(4,4,4))])
	check(not Cursor.hydrate_references(far_only.extras, subset_fixture.path, content_root).ok, "missing far dependency fails when demanded; index grants no loading safety")
	write_bytes(missing_path, missing_bytes)
	var model_path := folder.path_join("model.glb"); created.append(model_path)
	var model_fixture := ModelFixture.new(); model_fixture.write(model_path, model_fixture.data())
	var asset := box("large_model", 400); asset.kind = "asset"; asset.asset_path = model_path; asset.size = [1,1,1]
	var model_map := fixture("model_map", [asset])
	var model_index := Index.build(model_map.path, content_root, [asset])
	check(model_index.ok and model_index.rows[0].classification == "spatial" and model_index.rows[0].bounds == AABB(Vector3(408,3,-2), Vector3(4,4,4)), "model bounds come from source hierarchy, never locator proxy dimensions")
	var edited_model := model_fixture.data(); edited_model.nodes[0].translation[0] = -400
	model_fixture.write(model_path, edited_model)
	var replaced := Index.read(model_map.path, content_root)
	check(replaced.ok and replaced.rows[0].classification == "global" and replaced.rows[0].reason == "model_bounds_changed", "changed model geometry becomes global rather than skipping using stale bounds")
	model_fixture.free()
	var terrain := box("terrain", 100)
	terrain.size = [32, 1, 32]; terrain.terrain_mesh = {"version":1,"columns":2,"rows":2,"floor":-2,"heights":[0,1,2,0,1,2,0,1,2],"holes":[false,false,false,false]}
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-10,-1,-3),Vector3(10,1,3),Vector3(0,5,0)])
	var prefab_data := {"materials":[{"null":true}],"meshes":[{"bounds":AABB(Vector3.ZERO,Vector3.ONE),"box_size":Vector3.ZERO,"surfaces":[arrays],"materials":[0]}],"entries":[[[0],[0,0]]],"specs":[]}
	var prefab_bytes := var_to_bytes(prefab_data); var prefab := box("prefab",200)
	prefab.house_prefab = {"version":1,"sha256":Store._sha(prefab_bytes),"length":prefab_bytes.size(),"data":Marshalls.raw_to_base64(prefab_bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	prefab.building = {"id":"test_house","part":"shell","role":"shell","floor":0,"floor_y":0}; prefab.prefab_locked = true; prefab.prefab_materials = []
	var building_meta := {"building_instances":{"test_house":{"version":Index.Blueprint.VERSION,"parameters":Index.Blueprint.defaults(),"position":[200,0,0],"yaw":0,"parts":{"shell":"prefab"},"signatures":{"shell":"test_signature"},"baked":true}}}
	var conservative := fixture("conservative",[terrain,prefab],building_meta); var conservative_index := Index.build(conservative.path,content_root,[terrain,prefab])
	check(conservative_index.ok and conservative_index.rows[0].classification=="global" and conservative_index.rows[0].bounds==AABB(Vector3(84,-1,-16),Vector3(32,4,32)) and conservative_index.rows[0].terrain_halo==24.0, "terrain real height bounds and material/interpolation halo retained conservatively global")
	check(conservative_index.ok and conservative_index.rows[1].classification=="group" and conservative_index.rows[1].bounds==AABB(Vector3(190,0,-3),Vector3(20,6,6)) and conservative_index.rows[1].owner_keys==["building:test_house"], "prefab actual vertex bounds ignore locator and stored mesh proxy; complete building gets a group")
	if not conservative_index.ok: print("GROUP_FIXTURE_ERROR ",conservative_index)
	var component := prefab.duplicate(true); component.uuid="door_part"; component.position=[260,1,0]; component.building.part="door"
	component.fixture={"id":"entry_door","kind":"door","pivot":[10,0,0],"angle":90,"open":0.0}
	var far_house := prefab.duplicate(true); far_house.uuid="far_house"; far_house.position=[2000,1,0]; far_house.building.id="far_house"
	var group_meta := building_meta.duplicate(true)
	group_meta.building_instances.test_house.parts.door="door_part";group_meta.building_instances.test_house.signatures.door="door_signature"
	group_meta.building_instances.far_house=building_meta.building_instances.test_house.duplicate(true)
	group_meta.building_instances.far_house.parts.shell="far_house";group_meta.building_instances.far_house.position=[2000,0,0]
	var grouped_records: Array=[prefab,component,far_house]
	var grouped_fixture:=fixture("grouped",grouped_records,group_meta)
	var grouped_index:=Index.build(grouped_fixture.path,content_root,grouped_records)
	check(grouped_index.ok and grouped_index.groups.size()==2, "complete building groups contain every authored member")
	if not grouped_index.ok:print(grouped_index);quit(1);return
	var near_house:=Index.select(grouped_index,[AABB(Vector3(195,-2,-2),Vector3(4,4,4))])
	check(near_house.record_indices==[0,1] and near_house.deferred_indices==[2], "touching one floor loads all same-house parts but leaves far house deferred")
	check(grouped_index.rows[1].bounds.position.x<251 and grouped_index.rows[1].bounds.end.z>20, "fixture bounds include full hinge sweep rather than current pose only")
	var near_hydrated:=Cursor.hydrate_references(near_house.extras,grouped_fixture.path,content_root)
	var verified:=Index.validate_selected(grouped_index,near_hydrated.extras.rmmo_records)
	check(verified.ok and verified.validation_extras.building_instances.size()==1 and grouped_index.extras.building_instances.size()==2, "selected building uses original validator with filtered registry while full metadata remains intact")
	check(not Index.validate_selected(grouped_index,[near_hydrated.extras.rmmo_records[0]]).ok,"partial building cannot pass selected validation")
	var false_lock: Array=near_hydrated.extras.rmmo_records.duplicate(true); false_lock[0].prefab_locked=false
	check(not Index.validate_selected(grouped_index,false_lock).ok,"hydrated locked status must match full-snapshot proof")
	var moved_state: Array=near_hydrated.extras.rmmo_records.duplicate(true); moved_state[0].building.id="far_house"
	check(not Index.validate_selected(grouped_index,moved_state).ok,"selected resource cannot change source-bound building ownership")
	var group_cache:String=Index.cache_path(grouped_fixture.path,content_root);var group_bytes:=FileAccess.get_file_as_bytes(group_cache)
	payload=bytes_to_var(group_bytes.slice(49));payload.rows[0].prefab_locked=false;replace_payload(group_cache,payload)
	check(not Index.read(grouped_fixture.path,content_root).ok,"forged unlocked proof in a baked group fails complete compact ownership validation")
	payload=bytes_to_var(group_bytes.slice(49));payload.rows[0].group_id="building:far_house";replace_payload(group_cache,payload)
	check(not Index.read(grouped_fixture.path,content_root).ok,"wrong group identity rejects even with a recomputed envelope checksum")
	payload=bytes_to_var(group_bytes.slice(49));payload.groups["building:test_house"].members=[0];replace_payload(group_cache,payload)
	check(not Index.read(grouped_fixture.path,content_root).ok,"group directory cannot drop an authored member")
	write_bytes(group_cache,group_bytes)
	check(Index.read(grouped_fixture.path,content_root).ok,"valid complete group directory roundtrips after tamper fixtures")
	var missing_part_meta:=group_meta.duplicate(true);missing_part_meta.building_instances.test_house.parts.missing="not_present";missing_part_meta.building_instances.test_house.signatures.missing="missing_signature"
	var missing_part:=fixture("missing_part",grouped_records,missing_part_meta)
	check(not Index.build(missing_part.path,content_root,grouped_records).ok,"baked registry with a missing part cannot produce a directory")
	var unlocked_records:Array=grouped_records.duplicate(true);unlocked_records[0].prefab_locked=false
	var unlocked_fixture:=fixture("unlocked",unlocked_records,group_meta)
	check(not Index.build(unlocked_fixture.path,content_root,unlocked_records).ok,"unlocked baked prefab cannot be promoted to a trusted proof")
	var unknown_member:Array=grouped_records.duplicate(true);unknown_member[1].future_geometry_behavior={"unsupported":true}
	var unknown_fixture:=fixture("unknown_member",unknown_member,group_meta);var unknown_index:=Index.build(unknown_fixture.path,content_root,unknown_member)
	check(unknown_index.ok and not unknown_index.groups["building:test_house"].bounds_known and Index.select(unknown_index,[]).record_indices==[0,1],"one unknown component forces its complete building global, never an undersized union")
	var full_header_changed:=FileAccess.get_file_as_bytes(grouped_fixture.path)
	var changed_author:Dictionary=JSON.parse_string(full_header_changed.get_string_from_utf8());changed_author.nodes[0].extras.rmmo_records[0].rmmo_state.building.part="tampered_part"
	write_bytes(grouped_fixture.path,JSON.stringify(changed_author).to_utf8_buffer())
	check(not Index.read(grouped_fixture.path,content_root).ok,"changed compact author ownership invalidates index source identity")
	write_bytes(grouped_fixture.path,full_header_changed)
	var many: Array = [box("near",0)]
	for i in 100: many.append(box("far_%d" % i, 1000+i*40))
	var large := fixture("expanded_far", many); var large_index := Index.build(large.path,content_root,many)
	check(Index.select(large_index,[AABB(Vector3(-2,-2,-2),Vector3(4,4,4))]).compact_records.size()==1, "expanding only distant region leaves initial selected workload unchanged")
	check(FileAccess.get_sha256(f.path) == digest, "author map bytes untouched by index operations")
	# Delete only exact files created by this test; directory removal is nonrecursive.
	for path in created:
		if Paths.allowed(path,content_root) and FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for name in ["map", "missing_far", "model_map", "expanded_far", "conservative", "grouped", "missing_part", "unlocked", "unknown_member"]: DirAccess.remove_absolute(folder.path_join(name+".gltf.resources"))
	DirAccess.remove_absolute(folder)
	print("MAP_DEPENDENCY_INDEX passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
