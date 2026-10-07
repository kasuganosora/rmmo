extends SceneTree
const Lamps=preload("res://scripts/world3d/streetlamp_lights.gd")
var failures:=0
class Weather extends Node:
	var values:Dictionary={"time_hours":12.0}
	var night_sky:Dictionary={"ready":false}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var lamps:=Lamps.new();root.add_child(lamps);lamps.set_process(false)
	var base:=StandardMaterial3D.new();base.albedo_color=Color(.3,.2,.1,.4)
	var override:=StandardMaterial3D.new();override.albedo_color=Color(.7,.5,.2,.6)
	var mesh:=BoxMesh.new();mesh.material=base
	var crystal:={"mesh":mesh,"material_override":override,"surface_overrides":[],"extras":{"rmmo_streetlamp_crystal":true}}
	var warm:=crystal.duplicate(true);warm.extras={"rmmo_small_wall_lantern":true}
	var fallback:={"mesh":mesh,"material_override":null,"surface_overrides":[],"extras":{"rmmo_streetlamp_crystal":true}}
	var slot:=fallback.duplicate(true);slot.surface_overrides=[override]
	var ignored:=fallback.duplicate(true);ignored.extras={}
	var unsupported:=fallback.duplicate(true);unsupported.material_override=ShaderMaterial.new()
	var report:Dictionary=await lamps.prepare_materials([crystal,crystal,warm,fallback,slot,ignored,unsupported],self)
	check(report.materials==3,"preparation deduplicates source/state and honors override precedence")
	var builds:int=lamps.material_builds
	var blue:Material=lamps._night_material(override)
	var yellow:Material=lamps._night_material(override,true)
	lamps._night_material(base)
	check(lamps.material_builds==builds,"first residency uses prepared emissive materials without rebuilding")
	check(blue!=yellow and blue.emission_enabled and yellow.emission_enabled and blue.emission!=yellow.emission,"crystal and warm lamp emission stay independent")
	check(override.albedo_color==Color(.7,.5,.2,.6) and not override.emission_enabled and mesh.material==base,"source material and mesh remain unchanged")
	check(lamps.lights.is_empty() and lamps.fixtures.is_empty(),"preparing distant library does not create lights or activate fixtures")
	var again:Dictionary=await lamps.prepare_materials([crystal,warm],self)
	check(again.materials==2 and lamps.material_builds==builds,"reentry reuses prepared variants")
	var weather:=Weather.new();root.add_child(weather);lamps.weather=weather
	var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.material_override=override
	visual.set_surface_override_material(0,base);visual.set_meta("extras",crystal.extras);root.add_child(visual);Lamps.register(visual)
	lamps.refresh()
	check(lamps.material_builds==builds and visual.get_active_material(0)==override,"discovery honors global override and reuses its prepared material")
	weather.values.time_hours=22.0;lamps.refresh()
	check(visual.material_override==null and visual.get_active_material(0)==blue and blue.albedo_color==override.albedo_color,"night replaces global override with matching emissive appearance")
	check(lamps.fixtures[visual.get_instance_id()].light.visible,"night fixture remains lit")
	weather.values.time_hours=12.0;lamps.refresh()
	check(visual.material_override==override and visual.get_surface_override_material(0)==base and visual.get_active_material(0)==override,"day restores both global and per-surface overrides")
	weather.values.time_hours=22.0;lamps.refresh();visual.hide();lamps.refresh()
	check(visual.material_override==override and visual.get_surface_override_material(0)==base and not lamps.fixtures[visual.get_instance_id()].light.visible,"hidden fixture restores source and disables light")
	visual.show();lamps.refresh();visual.remove_from_group(Lamps.GROUP);lamps.refresh()
	check(visual.material_override==override and visual.get_surface_override_material(0)==base and lamps.fixtures.is_empty(),"leaving receiver group restores complete source state")
	Lamps.register(visual);lamps.refresh()
	check(visual.get_active_material(0)==blue and lamps.material_builds==builds,"reentry at night uses same prepared global override material")
	visual.queue_free();lamps.refresh()
	check(lamps.fixtures.is_empty() and lamps.lights.is_empty(),"queued residency exit removes fixture and light safely")
	# A new map can reuse this controller; warm material and global override
	# state must belong to its own receiver and restore on controller teardown.
	var replacement:=MeshInstance3D.new();replacement.mesh=mesh;replacement.material_override=override
	replacement.set_meta("extras",warm.extras);root.add_child(replacement);Lamps.register(replacement);lamps.refresh()
	check(replacement.get_active_material(0)==yellow and lamps.material_builds==builds,"replacement map warm fixture remains distinct from crystal emission")
	lamps.free()
	check(replacement.material_override==override and replacement.get_surface_override_material(0)==null,"controller teardown restores original global override")
	replacement.free();weather.free();print("LAMP_MATERIAL_PREPARER failures=",failures);quit(failures)
