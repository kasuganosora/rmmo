extends SceneTree
## Run only via tools/run_godot_background.py. Temporary GLBs, no formal maps.
const Preparation = preload("res://scripts/world3d/model_parse_preparation.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1
func write_fixture(path: String, color: Color, unknown_contract: bool = false) -> void:
	var binary := PackedFloat32Array([0,0,0, 1,0,0, 0,1,0, 0,0,1, 0,0,1, 0,0,1]).to_byte_array()
	binary.append_array(PackedFloat32Array([1,0,0,0, 1,0,0,0, 1,0,0,0]).to_byte_array())
	binary.append_array(PackedByteArray([0,0,0,0, 0,0,0,0, 0,0,0,0]))
	binary.append_array(PackedFloat32Array([0,1, 0,0,0, 0,1,0]).to_byte_array())
	var pixels := Image.create(2,2,false,Image.FORMAT_RGBA8); pixels.fill(color)
	var png := pixels.save_png_to_buffer(); binary.append_array(png)
	var data := {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0,1,2]}],
		"nodes":[{"name":"FlagA","mesh":0,"skin":0,"weights":[.75],"extras":{"rmmo_collision":"none","rmmo_wind":{"profile":"cloth","anchor":"top"}}},{"name":"FlagB","mesh":0,"skin":0,"translation":[2,0,0],"weights":[.25]},{"name":"Bone"}],
		"skins":[{"joints":[2],"skeleton":2}],"animations":[{"name":"Wave","samplers":[{"input":4,"output":5}],"channels":[{"sampler":0,"target":{"node":2,"path":"translation"}}]}],
		"meshes":[{"weights":[.2],"primitives":[{"attributes":{"POSITION":0,"WEIGHTS_0":2,"JOINTS_0":3},"targets":[{"POSITION":1}],"material":0}]}],
		"materials":[{"name":"ExactPBR","pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":.65},"doubleSided":true}],"textures":[{"source":0}],"images":[{"bufferView":6,"mimeType":"image/png"}],
		"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]},{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"},{"bufferView":2,"componentType":5126,"count":3,"type":"VEC4"},{"bufferView":3,"componentType":5121,"count":3,"type":"VEC4"},{"bufferView":4,"componentType":5126,"count":2,"type":"SCALAR","min":[0],"max":[1]},{"bufferView":5,"componentType":5126,"count":2,"type":"VEC3"}],
		"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":36},{"buffer":0,"byteOffset":72,"byteLength":48},{"buffer":0,"byteOffset":120,"byteLength":12},{"buffer":0,"byteOffset":132,"byteLength":8},{"buffer":0,"byteOffset":140,"byteLength":24},{"buffer":0,"byteOffset":164,"byteLength":png.size()}],"buffers":[{"byteLength":binary.size()}]}
	if unknown_contract: data.extras = {"uri":"custom-contract.bin"}
	var encoded := JSON.stringify(data).to_utf8_buffer()
	while encoded.size() % 4: encoded.append(32)
	while binary.size() % 4: binary.append(0)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67); file.store_32(2); file.store_32(28+encoded.size()+binary.size())
	file.store_32(encoded.size()); file.store_32(0x4e4f534a); file.store_buffer(encoded)
	file.store_32(binary.size()); file.store_32(0x004e4942); file.store_buffer(binary); file.close()

func capture(node: Node) -> Dictionary:
	var value := {"name":str(node.name),"class":node.get_class(),"extras":node.get_meta("extras",{}),"children":[]}
	if node is Node3D: value.transform = node.transform
	if node is MeshInstance3D:
		value.skeleton = str(node.skeleton); value.blends=[]; value.surfaces=[]; value.binds=[]
		for i in node.mesh.get_blend_shape_count(): value.blends.append(node.get_blend_shape_value(i))
		for i in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(i)
			var surface := {"arrays":node.mesh.surface_get_arrays(i),"morphs":node.mesh.surface_get_blend_shape_arrays(i)}
			if material is StandardMaterial3D:
				surface.material=[material.albedo_color,material.metallic,material.roughness,material.cull_mode]
				if material.albedo_texture != null:
					var image: Image = material.albedo_texture.get_image()
					surface.image=[image.get_size(),image.get_format(),image.get_data()]
			value.surfaces.append(surface)
		if node.skin != null:
			for i in node.skin.get_bind_count(): value.binds.append([node.skin.get_bind_bone(i),str(node.skin.get_bind_name(i)),node.skin.get_bind_pose(i)])
	if node is Skeleton3D:
		value.bones=[]
		for i in node.get_bone_count(): value.bones.append([node.get_bone_name(i),node.get_bone_parent(i),node.get_bone_rest(i)])
	if node is AnimationPlayer:
		value.animations=[]
		for name_ in node.get_animation_list():
			var animation: Animation = node.get_animation(name_)
			var tracks := []
			for track in animation.get_track_count():
				var keys := []
				for key in animation.track_get_key_count(track): keys.append([animation.track_get_key_time(track,key),animation.track_get_key_value(track,key)])
				tracks.append([animation.track_get_type(track),str(animation.track_get_path(track)),keys])
			value.animations.append([str(name_),animation.length,tracks])
	for child in node.get_children(): value.children.append(capture(child))
	return value

func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	var directory := Paths.cache_directory("model_parse_gpu_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var paths := [directory.path_join("blue.glb"),directory.path_join("red.glb")]
	write_fixture(paths[0],Color(.3,.6,.9,1)); write_fixture(paths[1],Color(.9,.2,.1,1))
	var serial: Dictionary = Preparation.new().run(paths,Callable(),1)
	var parallel: Dictionary = Preparation.new().run(paths,Callable(),2)
	check(serial.error == OK and parallel.error == OK,"serial and dual model parse succeed")
	check(parallel.parallel_eligible_count == 2 and parallel.parallel_batches == 1,"actual standalone containers qualify for parallel parsing")
	if serial.error == OK and parallel.error == OK:
		check(parallel.entries[0].document != parallel.entries[1].document and parallel.entries[0].state != parallel.entries[1].state,"document and state remain independent")
		for i in paths.size():
			var original: Node = Io.generate_scene(serial.entries[i].document,serial.entries[i].state)
			var candidate: Node = Io.generate_scene(parallel.entries[i].document,parallel.entries[i].state)
			check(original != null and candidate != null,"main-thread scene generation succeeds")
			if original != null and candidate != null:
				check(var_to_bytes(capture(original)) == var_to_bytes(capture(candidate)),"serial/parallel exact structure, mesh, morph, pixels, skin, animation and extras parity")
				var meshes: Array = preload("res://scripts/world3d/surface_materials.gd").meshes(candidate)
				check(meshes.size() == 2 and is_equal_approx(meshes[0].get_blend_shape_value(0),.75) and is_equal_approx(meshes[1].get_blend_shape_value(0),.25),"distinct per-node morph defaults preserved")
				check(candidate.find_children("*","Skeleton3D",true,false).size() > 0 and candidate.find_children("*","AnimationPlayer",true,false).size() > 0,"fixture actually exercises skeleton and animation generation")
				if not meshes.is_empty():
					var material: StandardMaterial3D = meshes[0].get_active_material(0)
					var pixel := material.albedo_texture.get_image().get_pixel(0,0)
					check(pixel.b > pixel.r if i == 0 else pixel.r > pixel.b,"parallel models retain their own embedded texture")
			if original != null: original.free()
			if candidate != null: candidate.free()
	var unknown := directory.path_join("unknown.glb")
	write_fixture(unknown,Color.WHITE,true)
	var conservative: Dictionary = Preparation.new().run([unknown,paths[0]])
	check(conservative.error == OK and conservative.parallel_eligible_count == 1 and conservative.parallel_batches == 0,"unknown URI contract retains serial compatibility without overlap")
	DirAccess.remove_absolute(unknown)
	for path in paths: DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("MODEL_PARSE_PREPARATION_GPU failures=",failures)
	quit(0 if failures == 0 else 1)
