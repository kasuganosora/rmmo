extends Node3D
## One controller per weather world, including the editor. Streamed meshes own no timers.
const GROUP:="rmmo_streetlamp_crystals"
var weather:Node
var camera:Camera3D
var fixtures:Dictionary={}
var lights:Array[OmniLight3D]=[]
var elapsed:=0.0
var material_builds:=0
static var night_materials:Dictionary={}
static var halo_mesh:QuadMesh

func _night_material(original:Material,warm:bool=false)->Material:
	if not original is StandardMaterial3D:return original
	var key:String=str(original.get_instance_id())+("_warm" if warm else "_blue")
	if not night_materials.has(key):
		if night_materials.size()>=64:night_materials.erase(night_materials.keys()[0])
		var mat:StandardMaterial3D=original.duplicate()
		var heart:=original.resource_name.to_lower().contains("heart")
		material_builds+=1
		mat.emission_enabled=true;mat.emission=Color(.55,.95,1) if heart else Color(.015,.26,1)
		mat.emission_energy_multiplier=4.8 if heart else 2.5
		if warm:
			mat.emission=Color(1,.42,.08);mat.emission_energy_multiplier=3.0
			mat.albedo_color.a=1.0
		# StandardMaterial defers shader/RID creation until its first assignment.
		# Resolve it along with the day resource, not on the first night toggle.
		mat.get_rid()
		night_materials[key]=mat
	return night_materials[key]

static func register(node:MeshInstance3D)->void:
	var extras:Dictionary=node.get_meta("extras",{})
	if extras.get("rmmo_streetlamp_crystal",false) or extras.get("rmmo_small_wall_lantern",false):node.add_to_group(GROUP)

static func annotate(root_:Node,instance_id:String)->void:
	# Only the explicitly tagged banner prefab owns this named crystal component.
	var crystal:=root_.find_child("ArcaneCrystal",true,false) as MeshInstance3D
	if crystal==null:return
	_mark_parts(root_,instance_id)
	var extras:Dictionary=crystal.get_meta("extras",{}).duplicate(true)
	extras.rmmo_streetlamp_crystal=true;crystal.set_meta("extras",extras);register(crystal)

static func _mark_parts(node:Node,instance_id:String)->void:
	if node is MeshInstance3D:
		var extras:Dictionary=node.get_meta("extras",{}).duplicate(true)
		extras.rmmo_streetlamp_instance=instance_id;node.set_meta("extras",extras)
	for child in node.get_children():_mark_parts(child,instance_id)

func _new_light()->OmniLight3D:
	var light:=OmniLight3D.new();light.name="StreetlampLight"
	light.light_color=Color(.18,.60,1);light.light_energy=4.5;light.omni_range=10.0
	light.omni_attenuation=1.0;light.shadow_enabled=false;light.visible=false;add_child(light);lights.append(light)
	return light

static func halo()->QuadMesh:
	if halo_mesh!=null:return halo_mesh
	halo_mesh=QuadMesh.new();halo_mesh.size=Vector2(.85,.85)
	var shader:=Shader.new();shader.code="""shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
void vertex(){ MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]); }
void fragment(){ float r=length(UV-vec2(0.5))*2.0; float a=pow(max(0.0,1.0-r),3.0)*0.34; ALBEDO=vec3(0.025,0.42,1.0); EMISSION=vec3(0.02,0.3,0.8); ALPHA=a; }
"""
	var material:=ShaderMaterial.new();material.shader=shader;halo_mesh.material=material
	return halo_mesh

func _process(delta:float)->void:
	elapsed+=delta
	if elapsed<.20:return
	elapsed=0;refresh()

func refresh()->void:
	if not is_instance_valid(weather):return
	var profile_start:=Time.get_ticks_usec() if has_meta("profile_frame") else 0
	var hour:float=weather.values.get("time_hours",12.0)
	if weather.night_sky.ready:hour=preload("res://scripts/world3d/celestial_cycle.gd").hours(weather.night_sky.snapshot,preload("res://scripts/world3d/night_sky.gd").local_time()+weather.night_sky.clock_offset)
	var night:bool=hour<6.0 or hour>=20.0
	var active:Dictionary={}
	for node in get_tree().get_nodes_in_group(GROUP):
		if not node is MeshInstance3D or node.get_world_3d()!=get_world_3d() or node.is_queued_for_deletion():continue
		var id:int=node.get_instance_id();active[id]=true
		if not fixtures.has(id):
			var warm:bool=node.get_meta("extras",{}).get("rmmo_small_wall_lantern",false)
			var originals:Array=[]
			var emission:Array=[]
			for slot in node.mesh.get_surface_count():
				var override:Material=node.get_surface_override_material(slot)
				originals.append(override)
				# Prepare both states on fixture discovery, while initial map loading
				# is covered. Switching the clock only swaps already built resources.
				# Retain them per fixture even if the bounded shared cache evicts one.
				emission.append(_night_material(override if override!=null else node.mesh.surface_get_material(slot),warm))
			var glow:=MeshInstance3D.new();glow.name="StreetlampHalo";glow.mesh=halo();glow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glow.position=node.get_aabb().get_center();glow.visible=false;node.add_child(glow)
			var light:=_new_light()
			if warm:light.light_color=Color(1,.52,.22);light.light_energy=1.2;light.omni_range=3.5
			fixtures[id]={"node":weakref(node),"originals":originals,"emission":emission,"glow":glow,"light":light,"lit":false,"warm":warm}
		var row:Dictionary=fixtures[id]
		var at:Vector3=node.global_transform*node.get_aabb().get_center()
		# Night lighting belongs to the fixture, never to the observer's distance/rank.
		var enabled:bool=night and node.is_visible_in_tree()
		if enabled!=row.lit:
			for slot in node.mesh.get_surface_count():
				node.set_surface_override_material(slot,row.emission[slot] if enabled else row.originals[slot])
			row.lit=enabled
		row.glow.visible=enabled and not row.warm
		# Reassigning an unchanged Node3D transform still dirties its render
		# instance. Static lamps need updates only when their fixture moves.
		if row.light.global_position!=at:row.light.global_position=at
		row.light.visible=enabled
	for id in fixtures.keys():
		if not active.has(id):_restore(fixtures[id]);fixtures.erase(id)
	if profile_start>0:set_meta("frame_timing",{"frame":Engine.get_process_frames(),"ms":(Time.get_ticks_usec()-profile_start)/1000.0,"material_builds":material_builds,"materials":night_materials.size()})

func _restore(row:Dictionary)->void:
	var node=row.node.get_ref()
	if is_instance_valid(node):
		for slot in row.originals.size():node.set_surface_override_material(slot,row.originals[slot])
	if is_instance_valid(row.glow):row.glow.queue_free()
	if is_instance_valid(row.light):
		row.light.hide();lights.erase(row.light);row.light.queue_free()

func _exit_tree()->void:
	for row:Dictionary in fixtures.values():_restore(row)
	fixtures.clear()
