extends RefCounted
## Prepare the generated shader variants behind the map loading cover. Preloading
## the shader file alone misses the variants produced by Materials.make(). Use the
## immutable stream library so distant/unloaded receivers are included too.
const Response = preload("res://scripts/world3d/wind_response.gd")
const Materials = preload("res://scripts/world3d/wind_material.gd")

static func prepare(library: Array, tree: SceneTree) -> Dictionary:
	var started := Time.get_ticks_usec()
	var slice_started := started
	var seen := {}
	var report := {"receivers":0,"materials":0,"skipped":0,"make_ms":0.0,"max_make_ms":0.0}
	for spec: Dictionary in library:
		# Budget the directory scan as well as material preparation. A first shader
		# compilation is indivisible; it must happen before player input is enabled.
		if Time.get_ticks_usec()-slice_started >= 2000:
			await tree.process_frame
			slice_started = Time.get_ticks_usec()
		var authored: Variant = spec.get("extras",{}).get("rmmo_wind")
		if not authored is Dictionary or authored.get("profile","off") == "off": continue
		if not Response.Schema.validate(authored,Response.schema()).is_empty(): continue
		var mesh: Mesh = spec.get("mesh")
		if mesh == null: continue
		report.receivers += 1
		var config: Dictionary = Response.defaults().merged(authored,true)
		var overrides: Array = spec.get("surface_overrides",[])
		for slot in mesh.get_surface_count():
			var source: Material = spec.get("material_override")
			if source == null and slot < overrides.size(): source = overrides[slot]
			if source == null: source = mesh.surface_get_material(slot)
			var id := source.get_instance_id() if source != null else 0
			if seen.has(id): continue
			seen[id] = true
			if not Response.material_error(source).is_empty():
				report.skipped += 1
				continue
			var began := Time.get_ticks_usec()
			# Materials keeps the shader cache; this temporary material is discarded.
			# Runtime still creates independent uniforms for each receiver and never
			# changes the authored source, residency, or the 90 m activation radius.
			Materials.make(source,config,mesh.get_aabb())
			var ms := (Time.get_ticks_usec()-began)/1000.0
			report.materials += 1
			report.make_ms += ms
			report.max_make_ms = maxf(report.max_make_ms,ms)
			if Time.get_ticks_usec()-slice_started >= 2000:
				await tree.process_frame
				slice_started = Time.get_ticks_usec()
	return report.merged({"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0})
