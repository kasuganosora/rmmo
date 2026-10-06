extends Node3D
## Bounded world-space simulation; physics surfaces also survive camera cutaway.
## A swept ray prevents fast drops from tunnelling through roofs and walls.
const LIMIT_RAIN := 760
const LIMIT_SNOW := 300
const LIMIT_SPLASH := 96
const RADIUS := 19.0
class Drop:
	var kind: int
	var p: Vector3
	var previous: Vector3
	var velocity := Vector3.DOWN
	var age := 0.0
	var life: float
	var phase: float
	var size: float
	func _init(type: int, at: Vector3, duration: float, angle: float, scale_: float) -> void:
		kind = type; p = at; previous = at; life = duration; phase = angle; size = scale_
class Splash:
	var p: Vector3
	var normal: Vector3
	var age := 0.0
	func _init(at: Vector3, direction: Vector3) -> void: p = at; normal = direction
var camera: Camera3D
var exclude: Array[RID] = []
var rain := 0.0
var snow := 0.0
var storm := 0.0
var wind := Vector3.ZERO
var brightness := 1.0
var enabled := true
var drops: Array[Drop] = []
var splashes: Array[Splash] = []
var batches: Array[MultiMeshInstance3D] = []
var rng := RandomNumberGenerator.new()
var clock := 0.0
var tick := 0.0
var last_anchor := Vector3.INF
var last_step_usec := 0
var ray_count := 0
var hit_count := 0
var ray_query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	rng.seed = 812381
	for kind in 3:
		var node := MultiMeshInstance3D.new(); node.name = ["Rain", "Snow", "Splashes"][kind]
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_custom_data = true
		var quad := QuadMesh.new(); quad.size = Vector2.ONE
		var material := ShaderMaterial.new(); material.shader = preload("res://scripts/world3d/weather_particle.gdshader")
		material.set_shader_parameter("kind", kind)
		material.set_shader_parameter("tint", Color(.9,.94,1) if kind == 1 else Color(.63,.76,.86))
		quad.material = material; mm.mesh = quad
		mm.instance_count = [LIMIT_RAIN, LIMIT_SNOW, LIMIT_SPLASH][kind]; mm.visible_instance_count = 0
		node.multimesh = mm; node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node); batches.append(node)

func clear() -> void:
	drops.clear(); splashes.clear(); last_anchor = Vector3.INF
	for batch in batches: batch.multimesh.visible_instance_count = 0

func _process(_delta: float) -> void:
	if drops.is_empty(): return
	# Render between the two simulated endpoints, never beyond a tested collision segment.
	var weight := clampf((tick + get_physics_process_delta_time()*Engine.get_physics_interpolation_fraction())*30.0,0,1)
	for kind in 2: batches[kind].multimesh.mesh.material.set_shader_parameter("interpolation",weight)

func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(camera) or rain + snow < .002:
		if not drops.is_empty() or not splashes.is_empty(): clear()
		return
	tick += delta
	if tick < 1.0/30.0: return
	var step := minf(tick, .067); tick = 0
	simulate(step)

func cast(from: Vector3, to: Vector3) -> Dictionary:
	ray_count += 1
	ray_query.from = from; ray_query.to = to; ray_query.collision_mask = 1
	ray_query.exclude = exclude; ray_query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(ray_query)

func simulate(delta: float) -> void:
	var started := Time.get_ticks_usec()
	clock += delta; ray_count = 0
	var anchor := camera.global_position
	if not last_anchor.is_finite() or anchor.distance_to(last_anchor) > RADIUS: clear()
	last_anchor = anchor
	var counts := [0, 0]
	var wanted := [int(LIMIT_RAIN * rain), int(LIMIT_SNOW * snow)]
	for index in range(drops.size()-1,-1,-1):
		var drop: Drop = drops[index]
		var kind: int = drop.kind
		drop.age += delta
		if drop.age > drop.life or drop.p.distance_to(anchor) > RADIUS*1.8 or counts[kind] >= wanted[kind]:
			drops.remove_at(index); continue
		var velocity := wind * (.5 if kind == 0 else .23) + Vector3(0, -lerpf(15,23,storm) if kind == 0 else -1.5, 0)
		if kind == 1: velocity += Vector3(sin(clock*1.3+drop.phase),0,cos(clock*.9+drop.phase))*.55
		var next: Vector3 = drop.p + velocity * delta
		var hit := cast(drop.p, next)
		if not hit.is_empty():
			hit_count += 1
			if kind == 0 and hit.normal.y > .35 and splashes.size() < LIMIT_SPLASH:
				splashes.append(Splash.new(hit.position + hit.normal*.012,hit.normal))
			drops.remove_at(index); continue
		drop.previous = drop.p; drop.p = next; drop.velocity = velocity; counts[kind] += 1
	# Bounded refill avoids a synchronous burst after teleport or switching weather.
	var budget := 64
	for kind in 2:
		while counts[kind] < wanted[kind] and budget > 0:
			budget -= 1
			var point := anchor + Vector3(rng.randf_range(-RADIUS,RADIUS), rng.randf_range(-5,14), rng.randf_range(-RADIUS,RADIUS))
			# No particles are born below a roof, even when the camera is indoors.
			if not cast(point + Vector3.UP*180, point - Vector3.UP*.1).is_empty(): continue
			drops.append(Drop.new(kind,point,rng.randf_range(1.0,2.5) if kind == 0 else rng.randf_range(6,11),rng.randf()*TAU,rng.randf_range(.75,1.3)))
			counts[kind] += 1
	for index in range(splashes.size()-1,-1,-1):
		splashes[index].age += delta
		if splashes[index].age > .32: splashes.remove_at(index)
	_draw(anchor)
	last_step_usec = Time.get_ticks_usec() - started

func _draw(anchor: Vector3) -> void:
	var counts := [0,0]
	for drop: Drop in drops:
		var kind: int = drop.kind
		var basis := Basis.IDENTITY
		if kind == 0:
			var up: Vector3 = -drop.velocity.normalized()
			var right := up.cross(camera.global_basis.z).normalized()
			if right.length_squared() < .1: right = Vector3.RIGHT
			basis = Basis(right*.027*drop.size, up*lerpf(.45,.72,storm)*drop.size, right.cross(up))
		else: basis = basis.scaled(Vector3.ONE*.075*drop.size)
		var opacity := minf(drop.age*5,1) * clampf((RADIUS*1.5-drop.p.distance_to(anchor))/6,0,1)
		var mm := batches[kind].multimesh
		mm.set_instance_transform(counts[kind], Transform3D(basis, drop.p))
		var offset := drop.previous - drop.p
		mm.set_instance_custom_data(counts[kind], Color(opacity,offset.x,offset.y,offset.z)); counts[kind] += 1
	for kind in 2: batches[kind].multimesh.visible_instance_count = counts[kind]
	for index in splashes.size():
		var splash: Splash = splashes[index]
		var normal: Vector3 = splash.normal
		var tangent := Vector3.RIGHT.slide(normal).normalized()
		if tangent.length_squared() < .1: tangent = Vector3.FORWARD.slide(normal).normalized()
		var size_ := lerpf(.05,.5,splash.age/.32)
		var basis := Basis(tangent*size_,normal.cross(tangent)*size_,normal)
		batches[2].multimesh.set_instance_transform(index,Transform3D(basis,splash.p))
		batches[2].multimesh.set_instance_custom_data(index,Color((1-splash.age/.32)*rain,0,0,0))
	batches[2].multimesh.visible_instance_count = splashes.size()
	for batch in batches:
		batch.multimesh.mesh.material.set_shader_parameter("brightness", brightness)
