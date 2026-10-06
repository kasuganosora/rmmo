extends Node3D
## Source hair is an attachment with its own native rig, not replacement body bones.
const Art = preload("res://scripts/asset/art_paths.gd")
const Spring = preload("res://scripts/char/character_source_hair_spring.gd")
const OPTIONS = preload("res://scripts/char/character_hairstyles.gd").SOURCE_OPTIONS
const SOURCE_NUMBERS = {201:1,202:3,203:6}
static var cache: Dictionary = {}
var body: Node3D
var source: Node3D
var selected := 0
var fit := Transform3D.IDENTITY
var error := ""
var materials: Array[ShaderMaterial] = []
var head_index := -1
var spring:RefCounted
var dynamics_enabled:=false
var fit_bake_error:=0.0
var key_light:DirectionalLight3D

func _process(_delta:float)->void:
	if materials.is_empty():return
	if not is_instance_valid(key_light) or key_light.get_world_3d()!=get_world_3d():
		key_light=null
		for node in get_tree().get_nodes_in_group("character_key_light"):
			if node is DirectionalLight3D and node.get_world_3d()==get_world_3d():
				key_light=node;break
	var enabled:bool=is_instance_valid(key_light) and key_light.is_visible_in_tree() and key_light.light_energy>0.0
	for mat in materials:
		mat.set_shader_parameter("source_key_enabled",enabled)
		if enabled:mat.set_shader_parameter("source_key_direction",key_light.global_transform.basis.z.normalized())

func configure_body(value: Node3D) -> void:
	body = value
	head_index = body.skeleton.find_bone("head")
	body.surface_updated.connect(sync_head)
	refit_body()

func refit_body()->void:
	var previous_fit:Transform3D=fit
	# Fit the source's original head reference, not the hairstyle silhouette:
	# a ponytail/long tip must never influence the head scale.
	var ref_path: String = Art.path("characters/source_hair/koikatu/head_reference.json")
	if not FileAccess.file_exists(ref_path):error="Missing native hair head reference";return
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ref_path))
	var src := AABB()
	var first := true
	for point: Array in reference.vertices:
		var p := Vector3(-point[0],point[1],point[2])
		if first:src=AABB(p,Vector3.ZERO);first=false
		else:src=src.expand(p)
	var cutoff: float = lerpf(body.rests.neck.origin.y,body.rests.head.origin.y,.5)
	var dst := AABB()
	first=true
	for point: Vector3 in body.rest_points:
		if point.y<cutoff:continue
		if first:dst=AABB(point,Vector3.ZERO);first=false
		else:dst=dst.expand(point)
	var scale_: Vector3 = dst.size/src.size
	fit=Transform3D(Basis.from_scale(scale_),dst.position-src.position*scale_)
	fit=fit*Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)
	# Hair prefab coordinates are relative to HairParent, not the head prefab.
	# Restore the original complete parent chain before fitting to our head.
	var source_parent:=Transform3D.IDENTITY
	for t:Dictionary in reference.hair_parent_chain_leaf_first:
		var q:Dictionary=t.m_LocalRotation
		var s:Dictionary=t.m_LocalScale
		var p:Dictionary=t.m_LocalPosition
		var local:=Transform3D(Basis(Quaternion(-q.x,-q.y,q.z,q.w)).scaled(Vector3(s.x,s.y,s.z)),Vector3(p.x,p.y,-p.z))
		source_parent=local*source_parent
	fit=fit*source_parent
	if source!=null and not fit.is_equal_approx(previous_fit):
		fit_bake_error=Spring.bake_fit(source,fit)
		assert(fit_bake_error<.00001)
		if spring!=null:spring.set_enabled(dynamics_enabled)
	sync_head()

func apply(model: Node3D) -> bool:
	var choice: int = int(model.appearance.get("part_ids",{}).get("FrontHair1",0))
	if choice != 0 and not SOURCE_NUMBERS.has(choice):
		error="Native hair resource not mapped for ID %d"%choice
		return false
	if choice!=selected:
		var next: Node3D
		if choice!=0:
			var path: String = Art.path("characters/hair/female_base_v2/source_%02d.scn"%SOURCE_NUMBERS[choice])
			if not FileAccess.file_exists(path):error="Missing native hair: "+path;return false
			if not cache.has(path):cache[path]=load(path)
			next=cache[path].instantiate()
		if source!=null:remove_child(source);source.queue_free()
		source=next;selected=choice;materials.clear();spring=null
		if source!=null:
			add_child(source)
			fit_bake_error=Spring.bake_fit(source,fit)
			assert(fit_bake_error<0.00001,"Native hair fit changed the rest shape")
			spring=Spring.new();spring.install(source);spring.install_contacts(body);spring.set_enabled(dynamics_enabled)
			for mesh: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
				for i in mesh.mesh.get_surface_count():
					var mat: Material=mesh.get_active_material(i)
					if mat is ShaderMaterial:
						var local: ShaderMaterial=mat.duplicate()
						mesh.set_surface_override_material(i,local);materials.append(local)
	for mat in materials:
		for parameter in ["hair_color","hair_color2","hair_color3"]:
			var key:String="source_"+parameter
			if not mat.has_meta(key):mat.set_meta(key,mat.get_shader_parameter(parameter))
			mat.set_shader_parameter(parameter,model._color(model.appearance,"hair",mat.get_meta(key)))
	error="";sync_head();return true

func sync_head() -> void:
	if body==null or head_index<0 or body.solved_bones.size()<=head_index:return
	var delta: Transform3D=body.solved_bones[head_index]*body.rests.head.affine_inverse()
	transform=delta
	position+=body.root_offset
	if spring!=null:spring.sync_contacts(body)

func projected_top(direction: Vector3, include_motion_margin:bool=true) -> float:
	var top: float=-INF
	if source==null:return top
	for mesh: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		var box: AABB=mesh.custom_aabb
		if not include_motion_margin:box=mesh.get_meta("native_fitted_rest_bounds",box)
		for corner in 8:top=maxf(top,(mesh.global_transform*box.get_endpoint(corner)).dot(direction))
	return top
