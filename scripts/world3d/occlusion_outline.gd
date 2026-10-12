extends CanvasLayer
## Render the same player geometry (including skinning and GPU deformation) to
## an isolated mask. Visual layer 20 is reserved for this local-player mask.
const MASK_LAYER := 1 << 19
var player: CharacterBody3D
var source: Camera3D
var mask: SubViewport
var camera: Camera3D
var overlay: ColorRect
var enabled := true
var occluded := false
var tagged: Array[GeometryInstance3D] = []
var scan_time := 0.0
var visual_exclusions:Array[RID]=[]

func bind(body: CharacterBody3D, view: Camera3D) -> void:
	player = body; source = view; layer = 5
	mask = SubViewport.new()
	mask.transparent_bg = true
	mask.world_3d = player.get_world_3d()
	mask.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(mask)
	camera = Camera3D.new(); camera.cull_mask = MASK_LAYER
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color(0, 0, 0, 0)
	camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	camera.environment.ambient_light_color = Color.WHITE
	camera.environment.ambient_light_energy = 1.0
	mask.add_child(camera); camera.current = true
	overlay = ColorRect.new(); overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/world3d/occlusion_outline.gdshader")
	material.set_shader_parameter("player_mask", mask.get_texture())
	overlay.material = material; overlay.hide(); add_child(overlay)
	_tag(player)

func configure(settings: Dictionary) -> void:
	enabled = bool(settings.outline_enabled)
	if overlay != null:
		overlay.material.set_shader_parameter("outline_color", preload("res://scripts/world3d/environment_settings.gd").color(settings.outline_color))
		overlay.material.set_shader_parameter("width", float(settings.outline_width))
		if not enabled: overlay.hide(); mask.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _tag(node: Node) -> void:
	if node is GeometryInstance3D and (node.layers & MASK_LAYER) == 0:
		node.layers |= MASK_LAYER; tagged.append(node)
	for child in node.get_children(): _tag(child)

func _process(delta: float) -> void:
	if not has_meta("profile_frame"):
		_tick_frame(delta);return
	var began:=Time.get_ticks_usec()
	_tick_frame(delta)
	set_meta("frame_timing",{"frame":Engine.get_process_frames(),"begin_us":began,"end_us":Time.get_ticks_usec(),"ms":(Time.get_ticks_usec()-began)/1000.0})

func _tick_frame(delta:float)->void:
	if not is_instance_valid(source) or not is_instance_valid(player): return
	scan_time -= delta
	if scan_time <= 0:
		_tag(player); scan_time = .5
		for i in range(tagged.size() - 1, -1, -1):
			if not is_instance_valid(tagged[i]): tagged.remove_at(i)
	occluded = enabled and _blocked()
	overlay.visible = occluded
	mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS if occluded else SubViewport.UPDATE_DISABLED
	if not occluded: return
	mask.size = Vector2i(source.get_viewport().get_texture().get_size())
	overlay.size = source.get_viewport().get_visible_rect().size
	camera.global_transform = source.global_transform
	camera.projection = source.projection; camera.fov = source.fov
	camera.size = source.size; camera.near = source.near; camera.far = source.far
	camera.keep_aspect = source.keep_aspect; camera.frustum_offset = source.frustum_offset
	camera.h_offset = source.h_offset; camera.v_offset = source.v_offset

func _blocked() -> bool:
	if source.is_position_behind(player.global_position): return false
	for height in [-.65, 0, .65]:
		var destination := player.global_position + Vector3(0, height, 0)
		var ray := PhysicsRayQueryParameters3D.create(source.global_position, destination)
		ray.exclude = visual_exclusions.duplicate()
		ray.exclude.append(player.get_rid())
		if not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return true
	return false

func _exit_tree() -> void:
	for geometry in tagged:
		if is_instance_valid(geometry): geometry.layers &= ~MASK_LAYER
