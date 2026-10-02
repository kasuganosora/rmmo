extends Node3D
const Sound=preload("res://scripts/world3d/weather_sound.gd")
var bolt:MeshInstance3D
var light:OmniLight3D
var played:Dictionary={}
var active_id:=""
var epoch:=""
var last_thunder_id:=""
var sound_count:=0

func _ready() -> void:
	bolt=MeshInstance3D.new(); bolt.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(bolt)
	var material:=ShaderMaterial.new(); material.shader=preload("res://scripts/world3d/lightning_bolt.gdshader"); bolt.material_override=material
	light=OmniLight3D.new(); light.omni_range=90.; light.light_color=Color(.68,.79,1); light.shadow_enabled=true
	light.light_energy=0.; add_child(light)

static func arrival(event:Dictionary, listener:Vector3) -> float:
	return float(event.start_at)+listener.distance_to(Vector3(event.position[0],event.position[1],event.position[2]))/343.

static func envelope(age:float) -> float:
	return 1. if age>=0. and age<.06 else .25 if age>=.11 and age<.19 else 0.

func reset() -> void:
	played.clear(); active_id=""; epoch=""; last_thunder_id=""
	for node in get_children():
		if node is AudioStreamPlayer3D: node.queue_free()
	if light!=null: light.light_energy=0.; bolt.visible=false

func advance(packet:Dictionary, stamp:float, listener:Vector3, enclosure:float, visual:bool, audible:bool) -> void:
	if epoch!=packet.epoch: reset(); epoch=packet.epoch
	for node in get_children():
		if node is AudioStreamPlayer3D:
			if not audible: node.stop(); node.queue_free()
			else: node.volume_db=-2.-enclosure*12.
	bolt.visible=false; light.light_energy=0.
	for event:Dictionary in packet.lightning_events:
		var position:=Vector3(event.position[0],event.position[1],event.position[2])
		var energy:=envelope(stamp-float(event.start_at))*float(event.energy)
		if visual and energy>0.:
			if active_id!=event.id:
				active_id=event.id; bolt.mesh=geometry(int(event.seed),float(event.height)); bolt.global_position=position
			bolt.visible=true; light.global_position=position+Vector3.UP*10.; light.light_energy=energy*8.
			bolt.material_override.set_shader_parameter("energy",energy)
		var distance:=listener.distance_to(position)
		var due:=arrival(event,listener)
		if stamp>=due and not played.has(event.id):
			played[event.id]=float(event.start_at)+30.
			# Late joins and reconnects don't replay thunder which has already passed.
			if audible and distance<6000. and stamp-due<.25:
				var audio:=AudioStreamPlayer3D.new(); audio.bus="Ambient"; audio.stream=Sound.stream("thunder_near" if distance<350. else "thunder_far")
				audio.unit_size=120.; audio.max_distance=6000.; audio.volume_db=-2.-enclosure*12.
				add_child(audio); audio.global_position=position; audio.finished.connect(audio.queue_free); audio.play()
				last_thunder_id=event.id; sound_count+=1
	for id in played.keys():
		if played[id]<stamp: played.erase(id)

static func geometry(seed:int, height:float) -> ArrayMesh:
	var rng:=RandomNumberGenerator.new(); rng.seed=seed
	var vertices:=PackedVector3Array(); var last:=Vector3.ZERO
	for i in range(1,15):
		var point:=Vector3(rng.randf_range(-1,1)*height*.045,height*i/14.,rng.randf_range(-1,1)*height*.045)
		segment(vertices,last,point,.65)
		if i in [5,9,12]:
			var branch:=point+Vector3(rng.randf_range(-.15,.15)*height,-height*.15,rng.randf_range(-.15,.15)*height)
			segment(vertices,point,branch,.35)
		last=point
	var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices
	var uv:=PackedVector2Array()
	for i in vertices.size()/6: uv.append_array(PackedVector2Array([Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(1,0)]))
	arrays[Mesh.ARRAY_TEX_UV]=uv
	var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); return mesh

static func segment(vertices:PackedVector3Array,a:Vector3,b:Vector3,width:float) -> void:
	for offset:Vector3 in [Vector3.RIGHT*width,Vector3.FORWARD*width]:
		vertices.append_array(PackedVector3Array([a-offset,b-offset,b+offset,a-offset,b+offset,a+offset]))
