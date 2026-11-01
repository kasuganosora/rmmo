extends SceneTree
## Component-only fixture; real Weather/Outline entry points, counted leaf effects.
const Weather=preload("res://scripts/world3d/weather_controller.gd")
const Outline=preload("res://scripts/world3d/occlusion_outline.gd")
const EnvironmentSettings=preload("res://scripts/world3d/environment_settings.gd")
const WeatherProfile=preload("res://scripts/world3d/weather_profile.gd")

class WeatherProbe extends Weather:
	var applies:=0
	var sky_calls:=0
	var audio_calls:=0
	func _apply()->void:applies+=1
	func _tick_night_sky(_delta:float)->void:sky_calls+=1
	func _tick_lightning(_delta:float)->void:pass
	func _sync_audio()->void:audio_calls+=1

class WindProbe extends Node3D:
	var calls:=0
	func advance(_wind:Vector3,_time:float)->void:calls+=1

class PrecipitationProbe extends Node3D:
	var enabled:=true
	var wind:=Vector3.ZERO
	var casts:=0
	var clears:=0
	func clear()->void:clears+=1
	func cast(_from:Vector3,_to:Vector3)->Dictionary:casts+=1;return {}

class WetProbe extends Node3D:
	var enabled:=true
	var wetness:=0.0
	var puddles:=0.0
	var rain:=0.0
	var time:=0.0
	var clears:=0
	func clear()->void:clears+=1

class OutlineProbe extends Outline:
	var queries:=0
	func _blocked()->bool:queries+=1;return true

class SettingsPulse extends Node:
	signal changed

var failures:=0
var passes:=0

func _init()->void:call_deferred("_run")
func check(value:bool,label:String)->void:
	if value:passes+=1;print("PASS "+label)
	else:failures+=1;push_error("FAIL "+label)

func _run()->void:
	var world:=Node3D.new();root.add_child(world)
	var player:=CharacterBody3D.new();world.add_child(player)
	var camera:=Camera3D.new();world.add_child(camera)
	var weather:=WeatherProbe.new();world.add_child(weather)
	weather.editor_preview=true
	weather.environment=Environment.new();weather.camera=camera;weather.observer=player
	weather.values=EnvironmentSettings.defaults();weather.values.sky_enabled=false;weather.values.celestial_cycle=false
	weather.current=WeatherProfile.sample(weather.values);weather.target=weather.current.duplicate(true)
	var wind:=WindProbe.new();weather.add_child(wind);weather.wind_objects=wind
	var rain:=PrecipitationProbe.new();weather.add_child(rain);weather.precipitation=rain
	var wet:=WetProbe.new();weather.add_child(wet);weather.wet_surfaces=wet
	weather.process_mode=Node.PROCESS_MODE_ALWAYS
	var settings_pulse:=SettingsPulse.new();world.add_child(settings_pulse)
	settings_pulse.changed.connect(weather._settings_changed)
	weather.suspend_map_observation();weather.suspend_map_observation()
	settings_pulse.changed.emit();settings_pulse.changed.emit()
	weather._process(.1);weather._physics_process(.1)
	await process_frame
	check(weather.applies==0 and wind.calls==0,"paused settings and explicit process have no apply/wind side effect")
	check(weather.sky_calls==0 and rain.casts==0 and weather.audio_calls==0,"paused idle and physics perform no observer work")
	check(weather._map_observation_settings_pending,"settings changes coalesce while paused")
	check(weather.process_mode==Node.PROCESS_MODE_DISABLED,"Weather subtree remains disabled through duplicate suspend")
	weather.resume_map_observation()
	check(weather.applies==1 and wind.calls==1,"resume applies pending current settings once")
	check(not weather._map_observation_settings_pending,"resume consumes pending flag")
	check(weather.process_mode==Node.PROCESS_MODE_ALWAYS,"Weather original process mode restored")
	weather.resume_map_observation()
	check(weather.applies==1 and wind.calls==1,"duplicate resume does not replay settings")
	weather._process(.1);weather._physics_process(.3)
	check(weather.sky_calls==1 and weather.audio_calls==1 and wind.calls==2,"normal explicit idle resumes once")
	check(rain.casts==9,"normal physics resumes all nine shelter queries")
	weather.suspend_map_observation();weather.resume_map_observation()
	check(weather.applies==1 and wind.calls==2,"no settings changes means no extra apply on resume")
	weather.free()
	var outline:=OutlineProbe.new();world.add_child(outline)
	outline.player=player;outline.source=camera
	outline.mask=SubViewport.new();outline.add_child(outline.mask)
	outline.mask.size=Vector2i(16,16)
	outline.camera=Camera3D.new();outline.mask.add_child(outline.camera)
	outline.overlay=ColorRect.new();outline.add_child(outline.overlay)
	outline.mask.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	outline.overlay.show();outline.process_mode=Node.PROCESS_MODE_ALWAYS
	outline.suspend_map_observation();outline.suspend_map_observation()
	outline._process(.1);outline._tick_frame(.1)
	await process_frame
	check(outline.queries==0,"paused automatic, explicit and direct outline ticks cannot query old physics")
	check(outline.mask.render_target_update_mode==SubViewport.UPDATE_DISABLED and not outline.overlay.visible,"outline mask disabled even though it owns a separate viewport")
	check(outline.process_mode==Node.PROCESS_MODE_DISABLED,"Outline process disabled")
	outline.resume_map_observation();outline.resume_map_observation()
	check(outline.process_mode==Node.PROCESS_MODE_ALWAYS,"Outline process mode restored once")
	check(outline.mask.render_target_update_mode==SubViewport.UPDATE_ALWAYS and outline.overlay.visible,"Outline prior presentation restored after target binding")
	outline.suspend_map_observation();outline.enabled=false;outline.resume_map_observation()
	check(outline.mask.render_target_update_mode==SubViewport.UPDATE_DISABLED and not outline.overlay.visible,"target disabled setting overrides pre-suspend visible state")
	outline.enabled=true;outline._tick_frame(.1)
	check(outline.queries==1,"normal outline observer resumes on target")
	outline.free();world.free()
	print("BODY_DETACH_OBSERVERS passes=%d failures=%d"%[passes,failures])
	quit(1 if failures else 0)
