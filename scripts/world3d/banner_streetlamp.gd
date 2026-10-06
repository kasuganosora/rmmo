extends Node3D
## Optional scene-level night presentation. No per-lamp process/timer or world registration.
## A central caller supplies actual clock, observer and remaining shared light budget.
const Candles=preload("res://scripts/world3d/house_candle_lights.gd")
const Cycle=preload("res://scripts/world3d/celestial_cycle.gd")
const SkyClock=preload("res://scripts/world3d/night_sky.gd")
const CRYSTAL_POSITION:=Vector3(0,3.46,0)
const LIGHT_DISTANCE:=28.0
const GLOW_DISTANCE:=60.0
var _crystal:MeshInstance3D
var _crystal_glowing:=false
var _crystal_materials_ready:=false
static var _night_materials:Dictionary={}

func _ready()->void:
	preload("res://scripts/world3d/streetlamp_banner.gd").apply(self,{})

func crystal_lit(value:bool)->void:
	var current:=get_node_or_null("Model/ArcaneCrystal") as MeshInstance3D
	if current!=_crystal:_crystal=current;_crystal_materials_ready=false
	if _crystal==null:return
	if _crystal_materials_ready and _crystal_glowing==value:return
	for slot in _crystal.mesh.get_surface_count():
		if not value:_crystal.set_surface_override_material(slot,null);continue
		var original:StandardMaterial3D=_crystal.mesh.surface_get_material(slot)
		if not _night_materials.has(original):
			var material:StandardMaterial3D=original.duplicate()
			material.emission_enabled=true
			var heart:=original.resource_name.contains("heart")
			material.emission=Color(.55,.95,1) if heart else Color(.015,.26,1)
			material.emission_energy_multiplier=4.8 if heart else 2.5
			_night_materials[original]=material
		_crystal.set_surface_override_material(slot,_night_materials[original])
	_crystal_glowing=value;_crystal_materials_ready=true

func is_crystal_lit()->bool:
	return is_instance_valid(_crystal) and _crystal.get_surface_override_material(0)!=null

static func update_from_weather(lamps:Array,eye:Vector3,weather:Node,remaining_budget:int=0)->int:
	var hour:=12.0
	if is_instance_valid(weather):
		if weather.night_sky.ready:hour=Cycle.hours(weather.night_sky.snapshot,SkyClock.local_time()+weather.night_sky.clock_offset)
		else:hour=float(weather.values.get("time_hours",12.0))
	return update_group(lamps,eye,hour,remaining_budget)

static func update_group(lamps:Array,eye:Vector3,hour:float,remaining_budget:int=0)->int:
	var candidates:Array=[]
	var night:=Candles.is_night(hour)
	for lamp in lamps:
		if not is_instance_valid(lamp) or not lamp is Node3D:continue
		var light:OmniLight3D=lamp.get_node_or_null("NightLight")
		if light==null or not lamp.has_method("crystal_lit"):continue
		var distance:=eye.distance_squared_to(lamp.to_global(CRYSTAL_POSITION))
		var visible_:bool=night and lamp.is_visible_in_tree()
		lamp.crystal_lit(visible_ and distance<GLOW_DISTANCE*GLOW_DISTANCE)
		light.visible=false
		if visible_ and distance<LIGHT_DISTANCE*LIGHT_DISTANCE:candidates.append({"light":light,"distance":distance})
	candidates.sort_custom(func(a,b):return a.distance<b.distance)
	var count:=mini(candidates.size(),clampi(remaining_budget,0,2))
	for i in count:candidates[i].light.visible=true
	return count
