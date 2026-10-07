extends Node3D
## Instance overlays: never mutate/export the authored base PBR material.
const SIZE:=32
const GroundCpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const CELL:=1.5
var camera:Camera3D
var scene_root:Node
var enabled:=true
var wetness:=0.
var puddles:=0.
var rain:=0.
var time:=0.
var receivers:Dictionary={}
var origin:=Vector2.INF
var height_image:Image
var height_texture:ImageTexture
var cursor:=0
var refresh_left:=0.
var scan_left:=0.
var exclude:Array[RID]=[]

func _ready() -> void:
	height_image=Image.create(SIZE,SIZE,false,Image.FORMAT_RF)
	height_image.fill(Color(-100000,0,0)); height_texture=ImageTexture.create_from_image(height_image)

func _physics_process(delta:float) -> void:
	if not is_instance_valid(camera): return
	if not enabled or wetness<.005:
		clear(); return
	var anchor:=Vector2(floor(camera.global_position.x/CELL),floor(camera.global_position.z/CELL))*CELL-Vector2.ONE*SIZE*CELL*.5
	if not origin.is_finite() or anchor.distance_to(origin)>=CELL*4:
		move_grid(anchor)
	refresh_left-=delta
	if cursor<SIZE*SIZE:
		for i in mini(32,SIZE*SIZE-cursor):
			var x:=cursor%SIZE; var z:=cursor/SIZE
			var point:=Vector3(origin.x+(x+.5)*CELL,camera.global_position.y+180,origin.y+(z+.5)*CELL)
			var query:=PhysicsRayQueryParameters3D.create(point,point-Vector3.UP*360,1)
			query.exclude=exclude
			var hit:=get_world_3d().direct_space_state.intersect_ray(query)
			height_image.set_pixel(x,z,Color(float(hit.position.y) if not hit.is_empty() else -100000.,0,0))
			cursor+=1
		height_texture.update(height_image)
	elif refresh_left<=0: cursor=0; refresh_left=2.
	scan_left-=delta
	if scan_left<=0: refresh(); scan_left=.5
	var parameters:Dictionary={"wetness":wetness,"puddles":puddles,"rain":rain,"wet_time":time,"shelter_origin":origin}
	for row:Dictionary in receivers.values():
		var material:ShaderMaterial=row.material
		for key in parameters: material.set_shader_parameter(key,parameters[key])

func move_grid(anchor:Vector2) -> void:
	var next:=Image.create(SIZE,SIZE,false,Image.FORMAT_RF); next.fill(Color(-100000,0,0))
	if origin.is_finite():
		var shift:=Vector2i(((anchor-origin)/CELL).round())
		for y in SIZE:
			for x in SIZE:
				var old:=Vector2i(x,y)+shift
				if old.x>=0 and old.x<SIZE and old.y>=0 and old.y<SIZE: next.set_pixel(x,y,height_image.get_pixel(old.x,old.y))
	height_image=next; height_texture.update(height_image)
	origin=anchor; cursor=0; refresh_left=0.

func refresh() -> void:
	var alive:Dictionary={}
	if not is_instance_valid(scene_root): return
	for node in scene_root.find_children("*","MeshInstance3D",true,false):
		if node.get_meta("editor_shadow_proxy",false):continue
		if node.mesh is GroundCpu: continue
		if receivers.size()>=512 and not receivers.has(node.get_instance_id()): continue
		if node.get_world_3d()!=get_world_3d() or not node.is_visible_in_tree() or node.mesh==null or node.skin!=null: continue
		if node.is_in_group("world3d_wind_receivers") or node.mesh.get_surface_count()!=1: continue
		if node.mesh is ArrayMesh and node.mesh.get_blend_shape_count()>0: continue
		if not (node.global_transform*node.get_aabb()).grow(36).has_point(camera.global_position): continue
		var owner_node:Node=node; var map_object:=false; var dynamic:=false
		while owner_node!=null and owner_node!=scene_root:
			var extra:Dictionary=owner_node.get_meta("extras",{})
			map_object=map_object or extra.has("uuid") or extra.has("kind")
			dynamic=dynamic or owner_node is CharacterBody3D or extra.get("kind","")=="npc" or bool(extra.get("hostile",false)) or bool(extra.get("ally",false))
			owner_node=owner_node.get_parent()
		if not map_object or dynamic: continue
		var source:Material=node.get_active_material(0)
		if source!=null and (not source is StandardMaterial3D or source.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED): continue
		var id:int=node.get_instance_id()
		if receivers.has(id) and receivers[id].source!=source: _restore(receivers[id]); receivers.erase(id)
		if not receivers.has(id):
			if node.material_overlay!=null: continue
			var material:=ShaderMaterial.new(); material.shader=preload("res://scripts/world3d/wet_surface.gdshader")
			material.set_shader_parameter("shelter_height",height_texture)
			if source!=null:
				material.set_shader_parameter("tint",source.albedo_color)
				material.set_shader_parameter("uv_scale",source.uv1_scale); material.set_shader_parameter("uv_offset",source.uv1_offset)
				material.set_shader_parameter("base_roughness",source.roughness)
				if source.albedo_texture!=null: material.set_shader_parameter("albedo_tex",source.albedo_texture)
			node.material_overlay=material
			receivers[id]={"node":weakref(node),"material":material,"source":source}
		alive[id]=true
	for id in receivers.keys():
		if not alive.has(id): _restore(receivers[id]); receivers.erase(id)

func _restore(row:Dictionary) -> void:
	var node:MeshInstance3D=row.node.get_ref()
	if node!=null and node.material_overlay==row.material: node.material_overlay=null

func clear() -> void:
	for row in receivers.values(): _restore(row)
	receivers.clear()

func reset() -> void:
	clear(); origin=Vector2.INF

func _exit_tree() -> void: clear()
