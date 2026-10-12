extends SceneTree
const Prepare = preload("res://scripts/world3d/wind_material_preparer.gd")
const Materials = preload("res://scripts/world3d/wind_material.gd")
const Response = preload("res://scripts/world3d/wind_response.gd")
const Runtime = preload("res://scripts/world3d/wind_runtime.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ",message)
	if not value: failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var mesh := PlaneMesh.new()
	mesh.material = StandardMaterial3D.new()
	var painted := StandardMaterial3D.new()
	painted.cull_mode = BaseMaterial3D.CULL_DISABLED
	painted.albedo_color = Color(.6,.1,.2)
	var config := Response.defaults().merged({"profile":"cloth","anchor":"left","shelter":false},true)
	var spec := {"mesh":mesh,"material_override":painted,"surface_overrides":[],"extras":{"rmmo_wind":config},"position":Vector3(1000,0,0)}
	var invalid := spec.duplicate(); invalid.extras = {"rmmo_wind":{"profile":"wrong"}}
	var off := spec.duplicate(); off.extras = {"rmmo_wind":{"profile":"off"}}
	var shader := ShaderMaterial.new()
	var unsupported := spec.duplicate(); unsupported.material_override = shader
	var fallback := spec.duplicate(); fallback.material_override = null
	var slot_override := fallback.duplicate(); slot_override.surface_overrides = [painted]
	var stats: Dictionary = await Prepare.prepare([spec,spec,invalid,off,unsupported,fallback,slot_override],self)
	check(stats.receivers == 5 and stats.materials == 2 and stats.skipped == 1,"unloaded/distant library, overrides, duplicate sources and unsupported materials")
	check(spec.material_override == painted and mesh.material is StandardMaterial3D and painted.albedo_color == Color(.6,.1,.2),"preparation leaves authored resources and stream records unchanged")
	var shader_count: int = Materials.shaders.size()
	var scene := Node3D.new(); root.add_child(scene)
	var camera := Camera3D.new(); scene.add_child(camera)
	var runtime := Runtime.new(); scene.add_child(runtime); runtime.camera = camera
	runtime.set_shared_state_enabled(false) # Verify legacy uniform compatibility.
	runtime.set_physics_process(false)
	var a := MeshInstance3D.new(); a.mesh = mesh; a.material_override = painted; a.set_meta("extras",{"rmmo_wind":config}); scene.add_child(a); Response.register(a)
	var b := MeshInstance3D.new(); b.mesh = mesh; b.material_override = painted; b.position.x = 1000; b.set_meta("extras",{"rmmo_wind":config}); scene.add_child(b); Response.register(b)
	runtime.refresh()
	check(runtime.receivers.size() == 1 and b.material_override == painted,"preparation does not activate distant receivers")
	var first: ShaderMaterial = a.get_surface_override_material(0)
	check(first.get_shader_parameter("tint") == painted.albedo_color,"prepared variant preserves authored color")
	b.position.x = 2; runtime.refresh()
	var second: ShaderMaterial = b.get_surface_override_material(0)
	check(first != second and first.shader == second.shader and Materials.shaders.size() == shader_count,"first activation reuses prepared shader with independent instance uniforms")
	runtime.advance(Vector3(3,0,1),12)
	check(second.get_shader_parameter("wind_velocity") == Vector3(3,0,1) and second.get_shader_parameter("wind_time") == 12,"wind parameters still update")
	a.position.x = 1000; runtime.refresh()
	check(a.material_override == painted and a.get_surface_override_material(0) == null and not a.has_meta("wind_original"),"leaving range restores source material")
	runtime.free()
	check(b.material_override == painted and not b.has_meta("wind_original"),"runtime teardown restores bound receivers")
	scene.free()
	var again: Dictionary = await Prepare.prepare([spec],self)
	check(again.materials == 1 and Materials.shaders.size() == shader_count,"map re-entry reuses generated variants")
	print("test_wind_material_preparer: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
