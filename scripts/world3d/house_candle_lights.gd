extends Node3D
## Night-only presentation. Authored fixture records remain ordinary independent building parts.
const Sconce=preload("res://scripts/world3d/candle_sconce_mesh.gd")
const Cycle=preload("res://scripts/world3d/celestial_cycle.gd")
const SkyClock=preload("res://scripts/world3d/night_sky.gd")
const MAX_LIGHTS:=2
const LIGHT_DISTANCE:=18.0
var map_root:Node
var observer:Node3D
var weather:Node
var fixtures:Array=[]
var hours:=12.0
var tick:=0.0

static func is_night(hour:float)->bool:
	var value:=fposmod(hour,24.0)
	return value>=20.0 or value<6.0

func bind_map(root_:Node,actor:Node3D=null,weather_:Node=null)->void:
	for f in fixtures:
		if is_instance_valid(f.effect):f.effect.queue_free()
	fixtures.clear();map_root=root_;observer=actor;weather=weather_
	if not is_instance_valid(map_root):return
	var extras:Dictionary=preload("res://scripts/world3d/gltf_map_io.gd").extras_of(map_root)
	for r:Dictionary in extras.get("rmmo_records",[]):
		if r.get("building_shape")!="candle_sconce":continue
		var effect:=Node3D.new();effect.name="Candle_"+str(r.uuid);add_child(effect);effect.visible=false
		var mesh:=MeshInstance3D.new();mesh.name="Flame";effect.add_child(mesh)
		mesh.mesh=flame_mesh()
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light:=OmniLight3D.new();effect.add_child(light);light.light_color=Color(1,.80,.50);light.omni_range=5.5;light.omni_attenuation=1.5;light.light_energy=.18;light.shadow_enabled=true;light.shadow_bias=.035;light.visible=false
		var position_:Array=r.position;var rotation_:Array=r.rotation
		var pose:=Transform3D(Basis.from_euler(Vector3(rotation_[0],rotation_[1],rotation_[2])*PI/180.0),Vector3(position_[0],position_[1],position_[2]))
		fixtures.append({"uuid":str(r.uuid),"effect":effect,"light":light,"pose":pose,"floor_y":float(r.get("building",{}).get("floor_y",position_[1]-2.15)),"flame":Sconce.FLAME*Vector3(r.size[0],r.size[1],r.size[2])/Sconce.SIZE})
	read_clock()
	refresh()

func set_hours(hour:float)->void:
	hours=hour;refresh()

func _process(delta:float)->void:
	tick+=delta
	if tick<.25:return
	tick=0
	read_clock()
	refresh()

func read_clock()->void:
	if is_instance_valid(weather):
		if weather.night_sky.ready:hours=Cycle.hours(weather.night_sky.snapshot,SkyClock.local_time()+weather.night_sky.clock_offset)
		else:hours=float(weather.values.get("time_hours",12.0))

func refresh()->void:
	var active:Array=[];var night:=is_night(hours)
	var meshes:Dictionary=map_root.get_meta("stream_meshes",{}) if is_instance_valid(map_root) else {}
	var streamed:bool=is_instance_valid(map_root) and map_root.has_meta("stream_meshes")
	var eye:=observer.global_position if is_instance_valid(observer) else Vector3.ZERO
	for f in fixtures:
		var source=meshes.get(f.uuid)
		var visible_:bool=night and is_instance_valid(map_root)
		if streamed:visible_=visible_ and is_instance_valid(source) and source.is_visible_in_tree()
		var pose:Transform3D=source.global_transform if is_instance_valid(source) else f.pose
		f.effect.global_position=pose*f.flame
		var distance_:float=eye.distance_squared_to(f.effect.global_position)
		f.effect.visible=visible_ and distance_<45.0*45.0;f.light.visible=false
		if visible_ and distance_<LIGHT_DISTANCE*LIGHT_DISTANCE:
			var score:float=distance_
			# Prefer the player's floor and an unobstructed connection to the room.
			# A candle just across a party wall must not steal an occupied room's budget.
			if is_instance_valid(observer):
				if eye.y<float(f.floor_y)-.25 or eye.y>float(f.floor_y)+3.9:score+=10000.0
				var query:=PhysicsRayQueryParameters3D.create(eye+Vector3.UP*1.4,f.effect.global_position)
				if observer is CollisionObject3D:query.exclude=[observer.get_rid()]
				query.collide_with_areas=false
				if not observer.get_world_3d().direct_space_state.intersect_ray(query).is_empty():score+=1000.0
			active.append({"fixture":f,"distance":score})
	active.sort_custom(func(a,b):return a.distance<b.distance)
	for i in mini(active.size(),MAX_LIGHTS):active[i].fixture.light.visible=true

func lit_count()->int:
	return fixtures.filter(func(f):return f.light.visible and f.effect.visible).size()

static var _flame_mesh:ArrayMesh
static func flame_mesh()->ArrayMesh:
	if _flame_mesh!=null:return _flame_mesh
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m:=StandardMaterial3D.new();m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.vertex_color_use_as_albedo=true;m.emission_enabled=true;m.emission=Color(1,.30,.015);m.emission_energy_multiplier=.6;st.set_material(m)
	var radii:Array=[.002,.01,.012,.007,.0001];var heights:Array=[-.036,-.020,0,.022,.045]
	for row in 4:
		for i in 8:
			var vertices:Array=[];var colors:Array=[]
			for cell in [[row,i],[row,(i+1)%8],[row+1,(i+1)%8],[row+1,i]]:
				var angle:float=cell[1]*TAU/8
				vertices.append(Vector3(cos(angle)*radii[cell[0]]+pow(float(cell[0])/4,2)*.006,heights[cell[0]],sin(angle)*radii[cell[0]]))
				colors.append(Color(1,.92,.40).lerp(Color(1,.30,.015),float(cell[0])/4))
			for index in [0,2,1,0,3,2]:st.set_color(colors[index]);st.add_vertex(vertices[index])
	st.generate_normals();_flame_mesh=st.commit();return _flame_mesh
