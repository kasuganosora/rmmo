extends SceneTree
const OUT = "D:/code/rmmo_runtime/review_artifacts/alarm_tower_materials_v3_20261011"
var errors: Array = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)
func segment_hits_triangles(start: Vector3, end: Vector3, triangles: PackedVector3Array) -> bool:
	for i in range(0, triangles.size(), 3):
		if Geometry3D.segment_intersects_triangle(start, end, triangles[i], triangles[i+1], triangles[i+2]) != null:
			return true
	return false
func run() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	check(doc.append_from_file(OUT + "/guild_alarm_tower.glb", state) == OK, "GLB import")
	if not errors.is_empty(): quit(1); return
	var scene := doc.generate_scene(state)
	root.add_child(scene)
	var json: Dictionary = state.json
	var horns := 0
	var material_nodes := 0
	for node in json.get("nodes", []):
		var extra: Dictionary = node.get("extras", {})
		if extra.get("open_bore", false): horns += 1
		if extra.get("material_pass", "") == "alarm_tower_v3": material_nodes += 1
		if node.get("name", "") == "Alarm tower context shaft":
			check(extra.get("shooting_slit_count", 0) == 16, "16 shooting slits serialized")
		var name: String = node.get("name", "").to_lower()
		for marker in ["shaft", "hollow masonry drum", "stone lip", "window reveal", "arched corbels", "scalloped arcade", "top cornice"]:
			if marker in name:
				check(extra.get("material_role", "") == "warm small masonry", "stone brick assignment: " + name)
				if node.has("mesh"):
					for primitive in json.meshes[node.mesh].primitives:
						check(json.materials[primitive.material].name == "Alarm PBR | warm small masonry", "actual stone brick material: " + name)
	check(horns == 8, "eight independent hollow horns")
	check(material_nodes == 265, "265 material-assigned meshes retained")
	var textures := 0
	for m in json.get("materials", []):
		var pbr: Dictionary = m.get("pbrMetallicRoughness", {})
		if pbr.has("baseColorTexture") and m.has("normalTexture") and pbr.has("metallicRoughnessTexture"): textures += 1
		if m.get("name", "") == "Alarm PBR | red brick roof": check(pbr.get("metallicFactor", 1) == 0, "red brick is nonmetallic")
		if m.get("name", "") == "Alarm PBR | aged golden brass": check(pbr.get("metallicFactor", 0) > .9, "horns have brass metal response")
	check(textures == 6, "six complete PBR material sets, no smooth trim")
	for mesh in json.get("meshes", []):
		for primitive in mesh.primitives: check(primitive.attributes.has("TEXCOORD_0"), "UV retained")
	var bounds := AABB()
	var count := 0
	var prepared: Dictionary = {}
	var seen: Dictionary = {}
	var slit_probes := 0
	for obj in scene.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = obj.global_transform * obj.get_aabb()
		bounds = box if count == 0 else bounds.merge(box)
		count += 1
		if obj.name == "Alarm tower context shaft":
			var triangles: PackedVector3Array = obj.mesh.get_faces()
			for i in triangles.size(): triangles[i] = obj.global_transform * triangles[i]
			var levels := [5.2,10.0,14.8,19.6]
			for tier in 4:
				for slot in 4:
					var angle := deg_to_rad(slot*90.0-45.0+(tier%2)*45.0)
					var radial := Vector3(cos(angle),0,-sin(angle))
					var tangent := Vector3(-sin(angle),0,-cos(angle))
					var centre := Vector3(0,levels[tier],0)
					check(not segment_hits_triangles(centre+radial*3,centre+radial*1.8,triangles), "exported slit is open")
					check(segment_hits_triangles(centre+radial*3+tangent*.45,centre+radial*1.8+tangent*.45,triangles), "exported adjacent masonry retained")
					slit_probes += 1
		for surface in obj.mesh.get_surface_count():
			var mat := obj.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat == null or seen.has(mat.get_instance_id()): continue
			seen[mat.get_instance_id()] = true
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS]:
				var tex := mat.get_texture(slot)
				if tex == null: continue
				if not prepared.has(tex.get_instance_id()):
					var pixels := tex.get_image()
					if not pixels.has_mipmaps(): pixels.generate_mipmaps()
					prepared[tex.get_instance_id()] = ImageTexture.create_from_image(pixels)
				mat.set_texture(slot, prepared[tex.get_instance_id()])
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	check(abs(bounds.position.y) < .01, "standalone base at ground zero")
	check(abs(bounds.get_center().x) < .01 and abs(bounds.get_center().z) < .01, "standalone origin centred")
	check(bounds.size.y > 33 and bounds.size.y < 34, "tower height retained")
	check(slit_probes == 16, "all 16 exported shooting slits probed")
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_color = Color(.26,.30,.36)
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(.22,.34,.52)
	sky_mat.sky_horizon_color = Color(.7,.75,.8)
	sky_mat.ground_bottom_color = Color(.18,.15,.11)
	sky_mat.ground_horizon_color = Color(.7,.75,.8)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = .7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new(); world.environment = env; root.add_child(world)
	var sun := DirectionalLight3D.new(); root.add_child(sun)
	sun.rotation_degrees = Vector3(-45,-25,0); sun.light_energy = 1.5; sun.shadow_enabled = true
	var camera := Camera3D.new(); root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 47
	camera.position = Vector3(31,26,35); camera.look_at(Vector3(0,16.5,0)); camera.current = true
	root.size = Vector2i(1400,1100); root.msaa_3d = Viewport.MSAA_4X
	for i in range(32): await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + "/godot_tower.png") == OK, "screenshot saved")
	camera.size = 7; camera.position = Vector3(7,12,9); camera.look_at(Vector3(0,10,0))
	for i in range(16): await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + "/godot_slit_detail.png") == OK, "slit detail saved")
	var report := {"passed":errors.is_empty(),"errors":errors,"meshes":count,"hollow_horns":horns,
		"material_nodes":material_nodes,"complete_pbr_sets":textures,"bounds_position":str(bounds.position),"bounds_size":str(bounds.size),
		"shooting_slit_geometry_probes":slit_probes,
		"glb_sha256":FileAccess.get_sha256(OUT + "/guild_alarm_tower.glb"),
		"scope":"Offline PBR import/UV/origin/render; preview mipmaps and sky; production editor unchanged"}
	var file := FileAccess.open(OUT + "/godot_material_review.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("ALARM_TOWER_REVIEW ",JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
