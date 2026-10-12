extends SceneTree
const Runtime = preload("res://scripts/world3d/wind_runtime.gd")
var failures := 0

func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error(label)

func _initialize() -> void: run.call_deferred()

func legacy(node: MeshInstance3D, camera: Camera3D) -> bool:
	if not is_instance_valid(camera): return true
	var begin := node.visibility_range_begin
	var end := node.visibility_range_end
	if begin == 0.0 and end == 0.0: return true
	var bounds := node.custom_aabb
	if bounds.size == Vector3.ZERO: bounds = node.get_aabb()
	var distance := camera.global_position.distance_to(node.global_transform * bounds.get_center())
	return (begin == 0.0 or distance >= begin-node.visibility_range_begin_margin-1.0) and (end == 0.0 or distance <= end+node.visibility_range_end_margin+1.0)

func compare(wind: Node3D, camera: Camera3D, nodes: Array, label: String) -> void:
	wind._update_active_rows()
	var actual := {}
	for index in wind.active_rows.size():
		var row:Dictionary=wind.active_rows[index]
		var id:int=row.node.get_ref().get_instance_id()
		check(not actual.has(id),label+" has no duplicate active rows")
		check(wind._active_indices.get(id,-1)==index,label+" swap-pop index matches row")
		actual[id]=true
	check(wind._active_indices.size()==actual.size(),label+" has no stale active indices")
	for node: MeshInstance3D in nodes:
		check(actual.has(node.get_instance_id()) == legacy(node,camera),label)

func run() -> void:
	var scene := Node3D.new(); root.add_child(scene)
	var wind := Runtime.new(); scene.add_child(wind); wind.set_physics_process(false)
	var camera := Camera3D.new(); scene.add_child(camera); wind.camera = camera
	var shared := BoxMesh.new()
	var nodes: Array = []
	var rng := RandomNumberGenerator.new(); rng.seed = 74127
	for i in 1500:
		var node := MeshInstance3D.new(); node.mesh = shared; scene.add_child(node)
		node.position = Vector3(rng.randf_range(-60,60),rng.randf_range(-3,3),rng.randf_range(-60,60))
		node.rotation = Vector3(rng.randf(),rng.randf(),rng.randf())
		node.scale = Vector3(.5+rng.randf(),.5+rng.randf(),.5+rng.randf())
		node.custom_aabb = AABB(Vector3(-.5,0,-.5),Vector3(1,2,1))
		node.visibility_range_begin = 12.0 if i%2 else 0.0
		node.visibility_range_end = 25.0 if i%2 else 12.0
		node.visibility_range_begin_margin = 1; node.visibility_range_end_margin = 1
		wind.receivers[node.get_instance_id()] = {"node":weakref(node)}
		nodes.append(node)
	compare(wind,camera,nodes,"initial transformed LOD scan matches legacy")
	for i in 24:
		camera.position = Vector3(rng.randf_range(-30,30),rng.randf_range(-5,5),rng.randf_range(-30,30))
		for n in 17:
			var node: MeshInstance3D = nodes[rng.randi_range(0,nodes.size()-1)]
			node.position += Vector3(rng.randf_range(-10,10),rng.randf_range(-2,2),rng.randf_range(-10,10))
			node.rotation += Vector3(.1,.4,.2); node.scale = Vector3(1.5,.6,2.1)
			node.visibility_range_begin = 0 if n%2 else 7
			node.visibility_range_end = 0 if n%3 else 32
			node.visibility_range_begin_margin = 9; node.visibility_range_end_margin = 4
			node.custom_aabb = AABB() if n%2 else AABB(Vector3(2,-1,3),Vector3(3,2,4))
			if n%4 == 0:
				var replacement := BoxMesh.new(); replacement.size = Vector3(4,3,5); node.mesh = replacement
		compare(wind,camera,nodes,"direct range/bounds/mesh/pose changes remain live")
	# Removing an instance between scans must neither dereference it nor keep a row active.
	var removed: MeshInstance3D = nodes.pop_back()
	removed.visibility_range_begin=0;removed.visibility_range_end=0
	wind._update_active_rows()
	check(wind._active_indices.has(removed.get_instance_id()),"freed-node fixture starts active")
	removed.free()
	compare(wind,camera,nodes,"freed receiver skipped")
	var previous: Array = []; var optimized: Array = []
	for repeat in 25:
		var start := Time.get_ticks_usec()
		var rows: Array = []
		for row: Dictionary in wind.receivers.values():
			var node: MeshInstance3D = row.node.get_ref()
			if node != null and legacy(node,camera): rows.append(row)
		previous.append((Time.get_ticks_usec()-start)/1000.0)
		start = Time.get_ticks_usec(); wind._update_active_rows()
		optimized.append((Time.get_ticks_usec()-start)/1000.0)
	previous.sort(); optimized.sort()
	print("WIND_RANGE_SCAN ",{"failures":failures,"receivers":1500,"legacy_median_ms":previous[12],"optimized_median_ms":optimized[12]})
	# The fixture uses range-only rows; prevent material restoration on teardown.
	wind.receivers.clear(); wind.active_rows.clear(); scene.free()
	quit(0 if failures == 0 else 1)
