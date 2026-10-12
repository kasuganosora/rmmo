extends SceneTree
const Graph = preload("res://scripts/world3d/gltf_delta_graph.gd")
var failed := 0
var passed := 0

class SaveCacheDouble:
	extends RefCounted
	var entries := {"new_instance":true,"unrelated":true}
	func remove(id: String) -> void: entries.erase(id)
class DocumentDouble:
	extends RefCounted
	var _save_meshes := SaveCacheDouble.new()
	func _mesh(_record: Dictionary, effects: bool = true) -> Node3D:
		var node := Node3D.new()
		node.set_meta("effects", effects)
		return node

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS: " if value else "FAIL: ", label)
	if value: passed += 1
	else: failed += 1

func fixture() -> Dictionary:
	return {
		"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}],
		"nodes": [
			{"name":"rmmo_world", "children":[1], "extras":{"rmmo_format":"rmmo_gltf_map"}},
			{"name":"obj_1", "children":[2,3], "camera":0, "extras":{"uuid":"obj_1"}, "extensions":{"KHR_lights_punctual":{"light":0}}},
			{"mesh":0, "skin":0, "extras":{"uuid":"obj_1/mesh","rmmo_streetlamp_instance":"obj_1"}, "extensions":{"EXT_mesh_gpu_instancing":{"attributes":{"TRANSLATION":0}}}},
			{"extras":{"uuid":"obj_10"}}
		],
		"meshes":[{"primitives":[{"attributes":{"POSITION":0}, "indices":1, "material":0, "targets":[{"POSITION":1}], "extensions":{"KHR_draco_mesh_compression":{"bufferView":0,"attributes":{"POSITION":77}}}}]}],
		"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0,"extensions":{"KHR_texture_transform":{"offset":[0,0]}}},"metallicRoughnessTexture":{"index":0}}, "normalTexture":{"index":0}, "occlusionTexture":{"index":0}, "emissiveTexture":{"index":0}, "extensions":{"KHR_materials_clearcoat":{"clearcoatTexture":{"index":0}}, "KHR_materials_unlit":{}}}],
		"textures":[{"source":0,"sampler":0,"extensions":{"KHR_texture_basisu":{"source":0}}}],
		"images":[{"bufferView":0,"mimeType":"image/png"}], "samplers":[{}],
		"accessors":[{"bufferView":0,"componentType":5126,"count":1,"type":"VEC3"},{"componentType":5126,"count":1,"type":"VEC3","sparse":{"count":1,"indices":{"bufferView":0,"componentType":5123},"values":{"bufferView":1}}}],
		"bufferViews":[{"buffer":0,"byteLength":16},{"buffer":0,"byteOffset":16,"byteLength":16}], "buffers":[{"uri":"version/mesh.bin","byteLength":32}],
		"skins":[{"joints":[3],"skeleton":3,"inverseBindMatrices":0}],
		"animations":[
			{"samplers":[{"input":0,"output":1}],"channels":[{"sampler":0,"target":{"node":3,"path":"translation"}},{"sampler":0,"target":{"node":0,"path":"scale"}}]},
			{"samplers":[{"input":0,"output":1}],"channels":[{"sampler":0,"target":{"node":2,"path":"weights"}}]}
		], "cameras":[{"type":"perspective","perspective":{"yfov":1,"znear":0.1}}],
		"extensions":{"KHR_lights_punctual":{"lights":[{"type":"point"}]}},
		"extensionsUsed":["KHR_lights_punctual","KHR_draco_mesh_compression","EXT_mesh_gpu_instancing","KHR_texture_basisu","KHR_texture_transform","KHR_materials_clearcoat","KHR_materials_unlit","KHR_mesh_quantization"]
	}

func unchanged_rejection(document: Dictionary, operation: String, label: String) -> void:
	var before := var_to_bytes(document)
	var result: Dictionary
	if operation == "clone": result = Graph.clone_instance(document, 1, "new")
	elif operation == "remove": result = Graph.remove_instances(document, [1])
	else: result = Graph.validate(document)
	check(not result.ok and var_to_bytes(document) == before and not str(result.get("reason", "")).is_empty(), label)

func cache_freshness() -> void:
	var incremental = load("res://scripts/world3d/incremental_save.gd")
	var paint = load("res://scripts/world3d/surface_materials.gd")
	var prefab = load("res://scripts/world3d/house_prefab.gd")
	var cpu = load("res://scripts/world3d/ground_cpu_mesh.gd")
	var timber = load("res://scripts/world3d/timber_door_mesh.gd")
	var interior = load("res://scripts/world3d/interior_door_mesh.gd")
	var tree = load("res://scripts/world3d/parametric_tree.gd")
	var banner = load("res://scripts/world3d/streetlamp_banner.gd")
	var matching := StandardMaterial3D.new()
	matching.set_meta("runtime_paint_definition", {"texture_path":"changed.png"})
	var unrelated := StandardMaterial3D.new()
	unrelated.set_meta("runtime_paint_definition", {"texture_path":"unrelated.png"})
	paint._materials = {"match":matching,"other":unrelated}
	paint._textures = {"changed.png":true,"changed.png|flip_y":true,"height.png":true,"unrelated.png":true}
	paint.prepared_images = paint._textures.duplicate()
	var changed_mesh = cpu.new(); changed_mesh.materials.append(matching)
	var other_mesh = cpu.new(); other_mesh.materials.append(unrelated)
	prefab._meshes = {"match":{"mesh":changed_mesh,"source":changed_mesh},"other":{"mesh":other_mesh,"source":other_mesh}}
	prefab._render_meshes = {"match":changed_mesh,"other":other_mesh}
	timber._data = {"old":true}; timber._meshes = {"old":changed_mesh}
	interior._data = {"other":true}; interior._meshes = {"other":other_mesh}
	tree.cache = {"unrelated":other_mesh}; banner._meshes = {"unrelated":other_mesh}
	incremental.prepare_materials([{"surface_paint":[{"material":{"texture_path":"changed.png","height_path":"height.png"}}]}])
	check(paint._textures.keys() == ["unrelated.png"] and paint.prepared_images.keys() == ["unrelated.png"], "subset freshness invalidates color normal-flip height inputs only")
	check(paint._materials.keys() == ["other"] and prefab._meshes.keys() == ["other"] and prefab._render_meshes.keys() == ["other"], "subset freshness drops referencing materials and frozen prefab caches")
	check(timber._data.has("old") and interior._data.has("other") and tree.cache.has("unrelated") and banner._meshes.has("unrelated"), "unrelated generator recipe caches remain intact")
	var wood: String = load("res://scripts/asset/art_paths.gd").external_root().path_join("packs/default/assets/materials/wood/solid_timber/texture.png")
	paint._textures[wood] = true; paint.prepared_images[wood] = true
	incremental.prepare_materials([{"building_shape":"timber_door"}])
	check(timber._data.is_empty() and timber._meshes.is_empty() and not paint._textures.has(wood) and not paint.prepared_images.has(wood), "new timber door invalidates implicit geometry and wood inputs")
	check(interior._data.has("other") and interior._meshes.has("other") and paint._textures.has("unrelated.png"), "timber invalidation preserves unrelated interior-door source cache")
	var document := DocumentDouble.new()
	var visual: Node3D = incremental.build_record(document, {"uuid":"new_instance","kind":"asset","house_prefab":{}}, null)
	check(not document._save_meshes.entries.has("new_instance") and document._save_meshes.entries.has("unrelated") and not visual.get_meta("effects"), "new UUID build invalidates only its save mesh and keeps prefab CPU path")
	visual.free()
	# These globals belong only to this isolated test process.
	paint._materials.clear(); paint._textures.clear(); paint.prepared_images.clear()
	prefab._meshes.clear(); prefab._render_meshes.clear()
	timber._data.clear(); timber._meshes.clear(); interior._data.clear(); interior._meshes.clear()
	tree.cache.clear(); banner._meshes.clear()

func godot_single_root() -> void:
	# Exact native export structure, including declaration-only extension and
	# the editor's authoritative wrapper. No fabricated extension payload.
	var native := {"asset":{"version":"2.0"},"extensionsUsed":["GODOT_single_root"],"scene":0,"scenes":[{"nodes":[0],"name":"rmmo_world"}],"nodes":[{"name":"rmmo_world","children":[1],"extras":{"rmmo_format":"rmmo_gltf_map","rmmo_version":1,"rmmo_records":[]}},{"name":"obj_1"}]}
	native = JSON.parse_string(JSON.stringify(native))
	check(typeof(native.scene) == TYPE_FLOAT and typeof(native.scenes[0].nodes[0]) == TYPE_FLOAT, "native export fixtures use real JSON-parsed numeric indexes")
	check(Graph.validate(native).ok, "Godot native single-root declaration is accepted")
	var cloned := Graph.clone_instance(native, 1, "godot_copy")
	check(cloned.ok and native.nodes[0].children.size() == 1 and int(native.nodes[0].children[0]) == 1, "Godot declared root permits an unattached instance clone")
	native.nodes[0].children.append(cloned.root)
	check(Graph.remove_instances(native, [1]).ok and Graph.validate(native).ok, "Godot declared root preserves orphan-node deletion semantics")
	var fragment := native.duplicate(true)
	var roots: Array = fragment.nodes[0].children.duplicate()
	fragment.nodes[0].erase("children"); fragment.nodes[0].erase("extras"); fragment.nodes[0].name = "delta_export_root"
	var appended := Graph.append_fragment(native, fragment, roots)
	check(appended.ok and Graph.validate(native).ok and native.extensionsUsed == ["GODOT_single_root"], "Godot fragment appends without changing target root convention")
	var ordinary: Dictionary = JSON.parse_string(JSON.stringify({"asset":{"version":"2.0"},"nodes":[{},{}],"scene":0,"scenes":[{"nodes":[0,1]}]}))
	appended = Graph.append_fragment(ordinary, fragment, roots)
	check(appended.ok and Graph.validate(ordinary).ok and not "GODOT_single_root" in ordinary.get("extensionsUsed", []), "fragment single-root declaration is not incorrectly promoted onto a multi-root target")
	var invalid := native.duplicate(true)
	invalid.extensions = {"GODOT_single_root":{}}
	check(not Graph.validate(invalid).ok, "Godot single-root payload is rejected per official declaration-only definition")
	invalid = native.duplicate(true); invalid.nodes[0].translation = [1,0,0]
	check(not Graph.validate(invalid).ok, "Godot single-root nonidentity root is rejected")
	invalid.nodes[0].translation = [0,0,0]
	invalid.nodes[0].rotation = [0,0,0,1]
	invalid.nodes[0].scale = [1,1,1]
	invalid = JSON.parse_string(JSON.stringify(invalid))
	check(Graph.validate(invalid).ok, "Godot single-root explicit default root transform is accepted")
	invalid.nodes[0].erase("translation"); invalid.nodes[0].erase("rotation"); invalid.nodes[0].erase("scale")
	invalid.nodes[0].matrix = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
	invalid = JSON.parse_string(JSON.stringify(invalid))
	check(Graph.validate(invalid).ok, "Godot single-root JSON-parsed identity matrix is accepted")
	invalid = native.duplicate(true); invalid.scenes.append({"nodes":[0]})
	check(not Graph.validate(invalid).ok, "Godot single-root multi-scene violation is rejected")
	invalid = native.duplicate(true); invalid.scenes[0].nodes = [1]
	check(not Graph.validate(invalid).ok, "Godot single-root must designate node zero")

func run() -> void:
	var data := fixture()
	check(Graph.validate(data).ok, "valid core, skinned, animated and indexed extensions")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(data))
	check(Graph.clone_instance(parsed, 1, "parsed_copy").ok and Graph.validate(parsed).ok, "JSON-parsed numeric indexes clone safely")
	var before := JSON.stringify(data)
	var clone := Graph.clone_instance(data, 1, "obj_2")
	check(clone.ok and clone.root == 4 and data.nodes.size() == 7, "clone appends only the subtree")
	check(data.nodes[0].children == [1] and data.nodes[4].name == "obj_2", "clone returns unattached root")
	check(data.meshes.size() == 1 and data.materials.size() == 1 and data.images.size() == 1 and data.buffers.size() == 1, "clone reuses expensive shared resources")
	check(data.nodes[6].skin == 1 and data.skins[1].joints == [5] and data.skins[1].skeleton == 5 and data.skins[1].inverseBindMatrices == 0, "clone owns skin and remaps joints without cloning accessor")
	check(data.nodes[4].extras.uuid == "obj_2" and data.nodes[6].extras.uuid == "obj_2/mesh" and data.nodes[5].extras.uuid == "obj_10", "UUID prefix replacement respects boundaries")
	check(data.nodes[6].extras.rmmo_streetlamp_instance == "obj_2" and data.nodes[2].extras.rmmo_streetlamp_instance == "obj_1", "cloned streetlamp owns its independent streaming group")
	check(data.animations.size() == 4 and data.animations[2].channels.size() == 1 and data.animations[2].channels[0].target.node == 5 and data.animations[2].samplers[0].output == 1, "clone copies only matching animation channels")
	check(Graph.validate(data).ok, "cloned graph remains reference-valid")
	check(JSON.stringify(fixture()) == before, "fixture and original subtree inputs are deterministic")
	data.nodes[0].children.append(clone.root)
	var snapshot := JSON.stringify(data)
	check(not Graph.clone_instance(data, 1, "obj_2").ok and JSON.stringify(data) == snapshot, "duplicate UUID rejection is atomic")
	var removed := Graph.remove_instances(data, [1])
	check(removed.ok and removed.removed_animation_count == 1 and data.nodes[0].children == [4], "remove detaches only selected root and drops empty animation")
	check(data.nodes.size() == 7 and data.skins.size() == 2 and data.meshes.size() == 1 and data.animations.size() == 3, "remove retains node skin resource indexes and cloned animation")
	check(data.animations[0].channels.size() == 1 and data.animations[0].channels[0].target.node == 0, "mixed animation retains unrelated channels")
	check(data.nodes[1].name.begins_with("__rmmo_deleted_node_") and data.nodes[4].name == "obj_2", "deleted root relinquishes its name without renaming active clone")
	check(Graph.validate(data).ok, "removed graph remains reference-valid")
	var restored := Graph.clone_instance(data, 4, "obj_1")
	check(restored.ok and restored.root == 7, "previously deleted UUID may be restored despite retained orphan nodes")
	data.nodes[0].children.append(restored.root)
	check(Graph.validate(data).ok and data.nodes[restored.root].name == "obj_1", "restored same-UUID graph is valid and attached")
	var restored_names := 0
	for node in data.nodes:
		if node.get("name", "") == "obj_1": restored_names += 1
	check(restored_names == 1, "restored active UUID is not shadowed by an orphan name")
	data = fixture()
	data.nodes[2].name = "obj_1__mesh"
	data.nodes[3].name = "obj_1__joint"
	data.nodes.append({"name":"__rmmo_deleted_node_1"})
	var skin_before: Dictionary = data.skins[0].duplicate(true)
	removed = Graph.remove_instances(data, [1])
	var names_seen := {}
	var names_unique := true
	for node in data.nodes:
		if not node.has("name"): continue
		if names_seen.has(node.name): names_unique = false
		names_seen[node.name] = true
	check(removed.ok and names_unique and data.nodes[1].name == "__rmmo_deleted_node_1_1" and data.nodes[2].name.begins_with("__rmmo_deleted_node_") and data.nodes[3].name.begins_with("__rmmo_deleted_node_"), "entire deleted subtree uses unique tombstones without colliding with existing names")
	check(data.skins[0] == skin_before and data.nodes[1].children == [2,3], "tombstones preserve node indices hierarchy and skin references")
	data = fixture()
	data.nodes.append({"name":"legacy_restore"})
	var legacy_clone := Graph.clone_instance(data, 1, "legacy_restore")
	check(legacy_clone.ok and data.nodes[4].name.begins_with("__rmmo_deleted_node_") and data.nodes[legacy_clone.root].name == "legacy_restore", "clone reclaims same UUID from an older saved orphan")
	data = fixture()
	data.nodes.append({"name":"secondary_instance"})
	data.scenes.append({"nodes":[4]})
	snapshot = JSON.stringify(data)
	check(not Graph.clone_instance(data, 1, "secondary_instance").ok and JSON.stringify(data) == snapshot, "UUID in another live scene still rejects atomically")
	data = fixture()
	data.animations = [data.animations[1]]
	removed = Graph.remove_instances(data, [1])
	check(removed.ok and not data.has("animations"), "last removed animation does not leave an empty container")
	data = fixture()
	data.nodes.append({"skin":0})
	unchanged_rejection(data, "clone", "external live skin consumer blocks clone")
	unchanged_rejection(data, "remove", "orphan skin consumer still blocks removal")
	data = fixture()
	data.skins[0].joints.append(0)
	unchanged_rejection(data, "clone", "cross-instance joint blocks clone")
	unchanged_rejection(data, "remove", "cross-instance joint blocks removal")
	data = fixture()
	data.skins.append({"joints":[3]})
	unchanged_rejection(data, "remove", "unreferenced external skin with live joint reference blocks removal")
	data = fixture()
	data.scenes.append({"nodes":[1]})
	unchanged_rejection(data, "remove", "second scene cannot retain a removed instance reference")
	data = fixture()
	data.nodes[2].extensions["VENDOR_unknown"] = {"node":3}
	unchanged_rejection(data, "clone", "unknown nested extension is safely rejected")
	data = fixture()
	data.extensionsUsed.append("KHR_animation_pointer")
	unchanged_rejection(data, "remove", "unknown declared extension is safely rejected")
	data = fixture()
	data.nodes[2].extensions["KHR_texture_basisu"] = {"source":0}
	unchanged_rejection(data, "clone", "known extension at unsupported location is rejected")
	data = fixture()
	data.nodes[3].children = [1]
	unchanged_rejection(data, "validate", "cycle rejected without recursion")
	data = fixture()
	data.nodes[0].children.append(2)
	unchanged_rejection(data, "validate", "multiple parents rejected")
	data = fixture()
	data.nodes[1].children = [2,2,3]
	unchanged_rejection(data, "validate", "duplicate child rejected")
	for invalid in [-1, 0.5, true, 99, "0", NAN, INF]:
		data = fixture()
		data.nodes[2].mesh = invalid
		unchanged_rejection(data, "validate", "invalid numeric index %s rejected" % str(invalid))
	data = fixture()
	data.skins[0].joints = false
	unchanged_rejection(data, "validate", "malformed skin array rejected without runtime error")
	data = fixture()
	data.extensions = false
	unchanged_rejection(data, "validate", "malformed root extension dictionary rejected without runtime error")
	data = fixture()
	data.extensions.KHR_lights_punctual = false
	unchanged_rejection(data, "validate", "malformed light extension dictionary rejected without runtime error")
	data = fixture()
	data.extensions.KHR_lights_punctual.lights = false
	unchanged_rejection(data, "validate", "malformed light array rejected without runtime error")
	data = fixture()
	data.nodes[2].extras = {"extensions":{"VENDOR_application_data":{"index":99}}}
	check(Graph.validate(data).ok, "extras are opaque application metadata")
	var fragment := fixture()
	fragment.nodes[0].children = []
	fragment.nodes[0].name = "delta_export_root"
	fragment.nodes[0].erase("extras")
	var fragment_before := JSON.stringify(fragment)
	data = fixture()
	data.nodes.append({"name":"legacy_fragment_root"})
	var legacy_fragment := fragment.duplicate(true)
	legacy_fragment.nodes[1].name = "legacy_fragment_root"
	var legacy_merge := Graph.append_fragment(data, legacy_fragment, [1])
	check(legacy_merge.ok and data.nodes[4].name.begins_with("__rmmo_deleted_node_") and data.nodes[legacy_merge.roots[0]].name == "legacy_fragment_root", "fragment reclaims authored root name from an older saved orphan")
	data = fixture()
	var merged := Graph.append_fragment(data, fragment, [1])
	check(merged.ok and merged.roots == [5] and data.nodes.size() == 8 and data.nodes[0].children == [1] and data.scenes == [{"nodes":[0]}], "append returns mapped roots without attaching or changing scenes")
	check(data.nodes[5].camera == 1 and data.nodes[5].children == [6,7] and data.nodes[6].mesh == 1 and data.nodes[6].skin == 1, "append remaps node graph and resources")
	check(data.skins[1].joints == [7] and data.skins[1].skeleton == 7 and data.skins[1].inverseBindMatrices == 2, "append remaps skin and accessor indexes")
	var primitive: Dictionary = data.meshes[1].primitives[0]
	check(primitive.attributes.POSITION == 2 and primitive.indices == 3 and primitive.material == 1 and primitive.targets[0].POSITION == 3, "append remaps mesh attributes indices material morph targets")
	check(data.materials[1].pbrMetallicRoughness.baseColorTexture.index == 1 and data.materials[1].normalTexture.index == 1 and data.materials[1].extensions.KHR_materials_clearcoat.clearcoatTexture.index == 1, "append remaps core and extension texture info")
	check(data.textures[1].source == 1 and data.textures[1].sampler == 1 and data.textures[1].extensions.KHR_texture_basisu.source == 1 and data.images[1].bufferView == 2, "append remaps textures samplers images")
	check(data.accessors[2].bufferView == 2 and data.accessors[3].sparse.indices.bufferView == 2 and data.accessors[3].sparse.values.bufferView == 3 and data.bufferViews[2].buffer == 1, "append remaps sparse and ordinary buffer indexes")
	check(data.animations[2].samplers[0].input == 2 and data.animations[2].samplers[0].output == 3 and data.animations[2].channels[0].sampler == 0 and data.animations[2].channels[0].target.node == 7, "animation sampler indexes remain local while accessors and targets remap")
	check(primitive.extensions.KHR_draco_mesh_compression.bufferView == 2 and primitive.extensions.KHR_draco_mesh_compression.attributes.POSITION == 77, "Draco buffer remaps and codec attribute ID is preserved")
	check(data.nodes[6].extensions.EXT_mesh_gpu_instancing.attributes.TRANSLATION == 2 and data.nodes[5].extensions.KHR_lights_punctual.light == 1 and data.extensions.KHR_lights_punctual.lights.size() == 2, "instancing and punctual light indexes remap")
	check(data.buffers[1].uri == "version/mesh.bin" and JSON.stringify(fragment) == fragment_before, "append preserves caller-rewritten URI and fragment input")
	check(Graph.validate(data).ok, "appended complete graph passes validation")
	data = fixture()
	snapshot = JSON.stringify(data)
	fragment.nodes[0].children = [1]
	check(not Graph.append_fragment(data, fragment, [1]).ok and JSON.stringify(data) == snapshot, "parented fragment root rejects atomically")
	fragment.nodes[0].children = []
	fragment.extensionsUsed.append("MSFT_lod")
	check(not Graph.append_fragment(data, fragment, [1]).ok and JSON.stringify(data) == snapshot, "unsupported fragment extension rejects atomically")
	data = fixture()
	snapshot = JSON.stringify(data)
	check(not Graph.remove_instances(data, [1,1]).ok and JSON.stringify(data) == snapshot, "duplicate removal root rejects atomically")
	check(not Graph.remove_instances(data, [2]).ok and JSON.stringify(data) == snapshot, "non-instance descendant removal rejects atomically")
	check(not Graph.clone_instance(data, 0, "wrapper_copy").ok and JSON.stringify(data) == snapshot, "authoritative wrapper clone is rejected")
	data.nodes[2].extras = false
	check(Graph.clone_instance(data, 1, "scalar_extras").ok, "non-object extras remain opaque during clone")
	fragment = fixture()
	fragment.nodes[0].children = []
	for name in Graph.MATERIAL_EXTENSIONS:
		var payload := {}
		for field in Graph.MATERIAL_EXTENSIONS[name]: payload[field] = {"index":0,"extensions":{"KHR_texture_transform":{"scale":[1,1]}}}
		fragment.materials[0].extensions[name] = payload
	for name in ["EXT_texture_webp", "EXT_texture_avif"]: fragment.textures[0].extensions[name] = {"source":0}
	data = fixture()
	merged = Graph.append_fragment(data, fragment, [1])
	var textures_ok: bool = merged.ok
	for name in Graph.MATERIAL_EXTENSIONS:
		for field in Graph.MATERIAL_EXTENSIONS[name]: textures_ok = textures_ok and data.materials[1].extensions[name][field].index == 1
	check(textures_ok, "every supported material extension texture field remaps")
	check(data.textures[1].extensions.EXT_texture_webp.source == 1 and data.textures[1].extensions.EXT_texture_avif.source == 1, "alternative image source extensions remap")
	check(Graph.validate(data).ok, "full supported extension combination remains valid")
	cache_freshness()
	godot_single_root()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--validate-file="):
			var actual: Variant = JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--validate-file=")))
			var actual_result: Dictionary = Graph.validate(actual) if actual is Dictionary else {"ok":false,"reason":"Invalid JSON"}
			check(actual_result.ok, "read-only actual exported fixture: " + str(actual_result.get("reason", "")))
	print("GLTF_DELTA_GRAPH_FINISHED passed=%d failures=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
