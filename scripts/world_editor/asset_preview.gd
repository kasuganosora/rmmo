extends SubViewportContainer
var viewport_: SubViewport
var scene: Node3D
var camera: Camera3D
var current_path := ""

func _ready() -> void:
	stretch = true
	custom_minimum_size.y = 140
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_ = SubViewport.new()
	viewport_.own_world_3d = true
	viewport_.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport_)
	camera = Camera3D.new()
	viewport_.add_child(camera)
	camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("252c35")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	camera.environment = environment
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	viewport_.add_child(light)
	visible = false

func show_asset(path: String) -> void:
	if path == current_path: return
	current_path = path
	if is_instance_valid(scene): scene.free()
	scene = null
	visible = not path.is_empty()
	if not visible: return
	scene = preload("res://scripts/world_editor/asset_library.gd").instantiate_preview(path)
	if scene == null:
		visible = false
		return
	viewport_.add_child(scene)
	for imported in scene.find_children("*", "Camera3D", true, false): imported.current = false
	camera.current = true
	var bounds := preload("res://scripts/world_editor/asset_library.gd").bounds_of(scene)
	var distance := maxf(bounds.size.length() * 1.4, 1)
	camera.position = bounds.get_center() + Vector3(1, 0.7, 1).normalized() * distance
	camera.look_at(bounds.get_center())
	camera.near = maxf(0.001, distance / 1000)
	camera.far = maxf(100, distance * 5)
	viewport_.render_target_update_mode = SubViewport.UPDATE_ONCE
