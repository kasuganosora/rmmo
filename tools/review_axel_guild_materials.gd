extends SceneTree
## Isolated GLB/PBR integration check, no project maps or production catalogue.
const OUT = "D:/code/rmmo/review_artifacts/axel_guild_materials_20261011"
var errors: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label)

func run() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var result := doc.append_from_file(OUT + "/axel_guild_materials_v1.glb", state)
	check(result == OK, "GLB import")
	if result != OK:
		quit(1)
		return
	var scene := doc.generate_scene(state)
	check(scene != null, "scene generated")
	if scene == null:
		quit(1)
		return
	root.add_child(scene)
	var json: Dictionary = state.json
	var count := 0
	var hidden_characters := 0
	var hinges := 0
	var material_nodes := 0
	for index in json.get("nodes", []).size():
		var data: Dictionary = json.nodes[index]
		var extras: Dictionary = data.get("extras", {})
		if extras.get("material_pass", "") == "architecture_v1": material_nodes += 1
		var node: Node = state.get_scene_node(index)
		if node == null: continue
		if extras.get("semantic_group", "").begins_with("60_") and node is Node3D:
			node.visible = false
			hidden_characters += 1
		if data.get("name", "").begins_with("Main door hinge"):
			hinges += 1
			# Render pose only; source GLB and exported node transforms remain unchanged.
			node.rotation.y = 0
	check(hinges == 2, "two independent main door hinges preserved")
	check(material_nodes == 1385, "architectural material extras preserved")
	var pbr_count := 0
	var normal_count := 0
	var roughness_count := 0
	var texture_diagnostics: Array = []
	var seen_materials: Dictionary = {}
	var prepared_textures: Dictionary = {}
	for m in json.get("materials", []):
		var pbr: Dictionary = m.get("pbrMetallicRoughness", {})
		if pbr.has("baseColorTexture"): pbr_count += 1
		if pbr.has("metallicRoughnessTexture"): roughness_count += 1
		if m.has("normalTexture"): normal_count += 1
	check(pbr_count >= 8, "base color textures exported")
	check(normal_count >= 8, "OpenGL normal textures exported")
	check(roughness_count >= 6, "roughness textures exported")
	for mesh in json.get("meshes", []):
		for primitive in mesh.get("primitives", []):
			var material: Dictionary = json.materials[primitive.get("material", 0)]
			if material.get("pbrMetallicRoughness", {}).has("baseColorTexture"):
				check(primitive.attributes.has("TEXCOORD_0"), "textured surface UV: " + mesh.get("name", ""))
	for child in scene.find_children("*", "MeshInstance3D", true, false):
		count += 1
		check(child.mesh != null, "imported mesh exists")
		for surface in child.mesh.get_surface_count():
			var mat := child.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat == null or seen_materials.has(mat.get_instance_id()): continue
			seen_materials[mat.get_instance_id()] = true
			var diagnostic := {"name": mat.resource_name, "filter_before": mat.texture_filter, "textures": []}
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS]:
				var texture := mat.get_texture(slot)
				if texture == null: continue
				var id := texture.get_instance_id()
				if not prepared_textures.has(id):
					var pixels := texture.get_image()
					diagnostic.textures.append({"slot": slot, "mipmaps_before": pixels.has_mipmaps(), "size": [pixels.get_width(), pixels.get_height()]})
					if not pixels.has_mipmaps(): pixels.generate_mipmaps()
					prepared_textures[id] = ImageTexture.create_from_image(pixels)
				mat.set_texture(slot, prepared_textures[id])
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			texture_diagnostics.append(diagnostic)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.23, .25, .27)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.74, .79, .85)
	environment.ambient_light_energy = .35
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-48, -25, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 35
	camera.position = Vector3(48, 30, 43)
	camera.look_at(Vector3(16, 6, -6))
	camera.current = true
	root.size = Vector2i(1400, 900)
	root.msaa_3d = Viewport.MSAA_4X
	for i in range(24): await process_frame
	await RenderingServer.frame_post_draw
	var screenshot_error := root.get_texture().get_image().save_png(OUT + "/godot_exterior.png")
	check(screenshot_error == OK, "Godot screenshot saved")
	var report := {"passed": errors.is_empty(), "errors": errors, "imported_meshes": count,
		"architectural_material_nodes": material_nodes, "hidden_character_nodes": hidden_characters,
		"main_door_hinges": hinges, "base_color_materials": pbr_count,
		"normal_materials": normal_count, "roughness_materials": roughness_count,
		"preview_texture_preparation": texture_diagnostics,
		"glb_sha256": FileAccess.get_sha256(OUT + "/axel_guild_materials_v1.glb"),
		"scope": "PBR import and render only; no new movement, interaction or camera-smoothing claim"}
	var file := FileAccess.open(OUT + "/godot_material_review.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("GUILD_MATERIAL_REVIEW ", JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
