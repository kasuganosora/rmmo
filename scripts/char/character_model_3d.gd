extends Node3D
signal identity_shapes_changed
const Shapes = preload("res://scripts/char/character_mesh_shapes.gd")
const ImportedRig = preload("res://scripts/char/character_imported_rig.gd")
const AxisRig = preload("res://scripts/char/character_axis_rig.gd")
const Motion = preload("res://scripts/char/character_motion_3d.gd")
## Uses imported weighted adult models when present; young types keep the blockout.
## Clothing remains separate geometry sharing the character skeleton.
const ACTIONS := ["idle","walk","attack","dash","cast","death","sit_ground","sit_down_ground","stand_up_ground","sit_chair","sit_chair_hold","stand_up_chair","lie_down","lie","get_up"]
const REST_NEXT:={"sit_down_ground":"sit_ground","stand_up_ground":"idle","sit_chair":"sit_chair_hold","stand_up_chair":"idle","lie_down":"lie","get_up":"idle"}
const YAW := {"front":0.0,"left":-PI/2,"right":PI/2,"back":PI,"front_left":-PI/4,"front_right":PI/4,"back_left":-3*PI/4,"back_right":3*PI/4}
var environment_wind:=Vector2.ZERO
var skeleton: Skeleton3D
var bones := {}
var gear := {}
var body_meshes := {}
var action := "idle"
var animation_clip:=""
var direction := "front"
var elapsed := 0.0
# Map views supply actual displacement; isolated previews retain authored timing.
var locomotion_rate:=1.0
var body_type := "male"
var appearance := {}
var equipment := {}
var auto_configure:=true
var rig: Node3D
var imported_rig:RefCounted
var axis_rig:RefCounted
var _from_axis_angles:Dictionary={}
var _from_rotations:Array[Quaternion]=[]
var _from_positions:Array[Vector3]=[]
var _from_position:=Vector3.ZERO
var _from_rotation:=Quaternion.IDENTITY
var _blend_elapsed:=0.0
var _blend_duration:=.16
var _expression_from:Dictionary={}
var _expression_target:Dictionary={}
var _expression_time:=0.0
var _expression_duration:=0.0

func _ready()->void:
	if auto_configure:configure(body_type,appearance,equipment)

func set_expressions(values:Dictionary)->bool:
	if axis_rig==null or not axis_rig.body.set_expressions(values):return false
	_expression_duration=0.0
	return true

func set_mmd_expressions(weights:Dictionary)->bool:
	var values:=preload("res://scripts/char/character_expressions.gd").from_mmd(weights)
	if values.has("invalid"):return false
	return set_expressions(values)

func expression_target()->Dictionary:
	if axis_rig==null:return {}
	return (_expression_target if _expression_duration>0 else axis_rig.body.expression_values).duplicate()

func transition_expressions(values:Dictionary,duration:float=.18)->bool:
	var normalized:=preload("res://scripts/char/character_expressions.gd").normalize(values)
	if axis_rig==null or normalized.has("invalid") or not is_finite(duration):return false
	if duration<=0:return set_expressions(normalized)
	_expression_from=axis_rig.body.expression_values.duplicate()
	_expression_target=normalized;_expression_time=0;_expression_duration=duration
	return true

func _step_expressions(delta:float)->void:
	if _expression_duration<=0 or axis_rig==null:return
	_expression_time+=maxf(delta,0)
	var amount:=smoothstep(0,_expression_duration,_expression_time)
	var values:Dictionary={}
	for key in preload("res://scripts/char/character_expressions.gd").CHANNELS:
		values[key]=lerpf(float(_expression_from.get(key,0)),float(_expression_target.get(key,0)),amount)
	if _expression_time>=_expression_duration:values=_expression_target;_expression_duration=0
	if not axis_rig.body.set_expressions(values):_expression_duration=0;push_error("Expression transition failed")

func configure(gender:String,custom:Dictionary,parts:Dictionary)->void:
	custom=custom.duplicate(true)
	custom.erase("equipment");custom.erase("mv_sheet")
	var use_axis:bool=custom.get("body_model","")=="female_base_v2"
	if use_axis and gender!="female":push_error("female_base_v2 requires female body type");return
	if axis_rig!=null and use_axis and gender==body_type:
		var previous:Dictionary=appearance
		appearance=custom.duplicate(true)
		if not axis_rig.update_appearance(self):appearance=previous;return
		set_equipment(parts);return
	if rig!=null and gender==body_type and custom==appearance:
		set_equipment(parts)
		return
	if imported_rig!=null and gender==body_type and _structural_appearance(custom)==_structural_appearance(appearance):
		var previous:Dictionary=appearance
		appearance=custom.duplicate(true)
		imported_rig.update_appearance(self,previous)
		set_equipment(parts)
		return
	body_type=gender;appearance=custom.duplicate(true);equipment=parts.duplicate(true)
	# A replacement rig cannot inherit clips or blending state from its predecessor.
	action="idle";elapsed=0.0;animation_clip=""
	_blend_elapsed=0.0;locomotion_rate=1.0
	if rig!=null:identity_shapes_changed.emit()
	_expression_duration=0.0;_expression_time=0.0
	_expression_from.clear();_expression_target.clear()
	if rig != null:
		remove_child(rig)
		rig.queue_free()
	bones.clear();gear.clear();body_meshes.clear()
	_from_rotations.clear()
	_from_positions.clear()
	imported_rig=null
	axis_rig=null;_from_axis_angles.clear()
	animation_clip=""
	rig=Node3D.new();rig.name="Rig";add_child(rig)
	skeleton=Skeleton3D.new();skeleton.name="Skeleton3D";rig.add_child(skeleton)
	if use_axis:
		var adapter:=AxisRig.new()
		if not adapter.install(self):push_error(adapter.last_error);return
		axis_rig=adapter;set_equipment(parts);pose_at(elapsed);return
	if ImportedRig.available(gender):
		var adapter:=ImportedRig.new()
		if adapter.install(self):
			imported_rig=adapter
			set_equipment(parts)
			pose_at(elapsed)
			return
	if gender in ["male", "female"]:
		push_error("Cannot load approved character resource: " + ImportedRig.source_path(gender))
		return
	var young:=gender.begins_with("young")
	var female:=gender.ends_with("female")
	rig.scale=Vector3(0.91 if female else 1.0,0.92 if young else 1.0,0.96 if female else 1.0)
	_bone("hips","",Vector3(0,.79,0))
	_bone("spine","hips",Vector3(0,.20,0))
	_bone("head","spine",Vector3(0,.53,0))
	for side in ["L","R"]:
		var sign_x:float=-1.0 if side=="L" else 1.0
		_bone("thigh"+side,"hips",Vector3(sign_x*.145,-.04,0))
		_bone("shin"+side,"thigh"+side,Vector3(0,-.34,0))
		_bone("foot"+side,"shin"+side,Vector3(0,-.32,0))
		_bone("arm"+side,"spine",Vector3(sign_x*(.245 if female else .27),.22,0))
		_bone("forearm"+side,"arm"+side,Vector3(0,-.26,0))
		_bone("hand"+side,"forearm"+side,Vector3(0,-.24,0))
	var skin:=_material(_color(custom,"skin",Color("f9ddc8")))
	var hair:=_material(_color(custom,"hair",Color("48312b")))
	hair.cull_mode=BaseMaterial3D.CULL_DISABLED
	var cloth:=_material(_color(custom,"cloth",Color("42576a")))
	var dark:=_material(Color("303944"))
	var leather:=_material(Color("493023"))
	var gold:=_material(Color("c9a567"))
	var eye:=_material(Color("292735"))
	var torso:=Shapes.profile([Vector4(-.20,.17,.11,0),Vector4(-.10,.17 if female else .20,.12,0),Vector4(.10,.22 if female else .245,.14,0),Vector4(.24,.235 if female else .265,.13,0),Vector4(.31,.105,.085,0)])
	_mesh("spine",torso,Vector3.ZERO,skin,"Body")
	_mesh("hips",_ellipsoid(Vector3(.22,.15,.145)),Vector3.ZERO,dark,"Body")
	_mesh("spine",_ellipsoid(Vector3(.085,.13,.085)),Vector3(0,.37,0),skin,"Body")
	_mesh("head",Shapes.profile([Vector4(-.28,.015,.025,.045),Vector4(-.245,.10,.11,.035),Vector4(-.17,.18 if female else .20,.18,.01),Vector4(-.06,.25,.23,0),Vector4(.08,.27,.25,0),Vector4(.22,.25,.225,0),Vector4(.32,.18,.16,0),Vector4(.37,.005,.005,0)]),Vector3(0,.06,0),skin,"Body")
	var whites:=_material(Color("fff8eb"));whites.cull_mode=BaseMaterial3D.CULL_DISABLED
	eye.cull_mode=BaseMaterial3D.CULL_DISABLED
	var iris:=_material(Color("567b79"))
	for x in [-1,1]:
		_mesh("head",_ellipsoid(Vector3(.034,.056,.028)),Vector3(x*.265,.045,0),skin,"Body")
		var edge:=_mesh("head",Shapes.almond(.072,.041),Vector3(x*.112,.047,.235),eye,"Eyes");edge.rotation.y=x*.28
		var white:=_mesh("head",Shapes.almond(.065,.031),Vector3(x*.112,.043,.24),whites,"Eyes");white.rotation.y=x*.28
		_mesh("head",_ellipsoid(Vector3(.025,.031,.01)),Vector3(x*.109,.043,.255),iris,"Eyes")
		_mesh("head",_ellipsoid(Vector3(.011,.023,.005)),Vector3(x*.109,.044,.265),eye,"Eyes")
		_mesh("head",_ellipsoid(Vector3(.008,.009,.004)),Vector3(x*.109-.008,.055,.270),whites,"Eyes")
		_mesh("head",Shapes.lock([Vector3(x*.05,.135,.238),Vector3(x*.105,.148,.237),Vector3(x*.17,.132,.218)],.009,.004),Vector3.ZERO,hair,"Eyes")
	_mesh("head",_ellipsoid(Vector3(.017,.028,.018)),Vector3(0,-.025,.238),skin,"Body")
	_mesh("head",Shapes.lock([Vector3(-.036,-.10,.218),Vector3(0,-.106,.226),Vector3(.036,-.10,.218)],.006,.003),Vector3.ZERO,_material(Color("9b6058")),"Eyes")
	# Open-bottom hair cap, with separate locks. Face stays exposed.
	_mesh("head",_hair_cap(),Vector3(0,.06,0),hair,"Hair")
	var ids:Dictionary=custom.get("part_ids",{})
	var variant:int=int(ids.get("FrontHair1",2 if female else 1))
	for i in range(7):
		var x:float=(i-3)*.077
		var tip_y:=.12+absf(x)*.22+(.04 if i%2==0 else 0.0)
		var strand:=Shapes.lock([Vector3(x-.075,.42,.16),Vector3(x-.035,.35,.265),Vector3(x+.02,.24,.28),Vector3(x+.045,tip_y,.25)],.071,.032)
		_mesh("head",strand,Vector3.ZERO,hair,"Hair")
	for side in [-1,1]:
		_mesh("head",Shapes.lock([Vector3(side*.18,.32,.02),Vector3(side*.28,.19,.07),Vector3(side*.265,-.06,.10)],.07,.048),Vector3.ZERO,hair,"Hair")
	if variant==2:
		for x in [-1,1]:_mesh("head",Shapes.lock([Vector3(x*.22,.25,-.04),Vector3(x*.30,.06,-.05),Vector3(x*.32,-.18,-.025),Vector3(x*.25,-.32,.055)],.11,.12),Vector3.ZERO,hair,"Hair")
	var jacket:=_mesh("spine",torso,Vector3.ZERO,cloth,"Clothing1");jacket.scale=Vector3(1.06,1.04,1.10)
	for x in [-1,1]:
		var lapel:=_mesh("spine",_box(Vector3(.066,.20,.025)),Vector3(x*.065,.20,.14),leather,"Clothing1");lapel.rotation.z=x*.32
		var seam:=_mesh("spine",_box(Vector3(.018,.32,.015)),Vector3(x*.155,.04,.149),gold,"Clothing1");seam.rotation.z=-x*.10
	for y in [-.08,.02,.12]:_mesh("spine",_ellipsoid(Vector3(.012,.012,.008)),Vector3(0,y,.158),gold,"Clothing1")
	_mesh("hips",_ellipsoid(Vector3(.228,.158,.153)),Vector3.ZERO,dark,"Clothing2")
	_mesh("hips",Shapes.profile([Vector4(.015,.223,.162,0),Vector4(.075,.223,.162,0)]),Vector3.ZERO,leather,"Belt")
	_mesh("hips",_box(Vector3(.07,.06,.025)),Vector3(0,.045,.165),gold,"Belt")
	for side in ["L","R"]:
		_mesh("arm"+side,Shapes.profile([Vector4(-.28,.060,.059,0),Vector4(-.13,.075,.073,0),Vector4(.02,.070,.070,0)]),Vector3.ZERO,skin,"Body")
		_mesh("forearm"+side,Shapes.profile([Vector4(-.25,.043,.046,0),Vector4(-.10,.061,.060,0),Vector4(.015,.061,.059,0)]),Vector3.ZERO,skin,"Body")
		_mesh("hand"+side,_ellipsoid(Vector3(.07,.082,.06)),Vector3(0,-.025,0),skin,"Body")
		_mesh("thigh"+side,Shapes.profile([Vector4(-.36,.073,.077,0),Vector4(-.20,.090,.093,0),Vector4(.02,.100,.095,0)]),Vector3.ZERO,skin,"Body")
		_mesh("shin"+side,Shapes.profile([Vector4(-.33,.052,.056,0),Vector4(-.13,.072,.077,0),Vector4(.02,.074,.078,0)]),Vector3.ZERO,skin,"Body")
		_mesh("foot"+side,_ellipsoid(Vector3(.085,.07,.14)),Vector3(0,-.025,.065),skin,"Body")
		_mesh("arm"+side,Shapes.profile([Vector4(-.15,.086,.086,0),Vector4(.02,.099,.099,0),Vector4(.075,.008,.008,0)]),Vector3.ZERO,cloth,"Clothing1")
		_mesh("thigh"+side,Shapes.profile([Vector4(-.36,.083,.09,0),Vector4(-.23,.10,.105,0),Vector4(-.07,.116,.115,0),Vector4(.055,.10,.10,0)]),Vector3.ZERO,dark,"Clothing2")
		_mesh("shin"+side,Shapes.profile([Vector4(-.32,.07,.074,0),Vector4(-.12,.085,.09,0),Vector4(.035,.09,.095,0)]),Vector3.ZERO,dark,"Clothing2")
		_mesh("foot"+side,_ellipsoid(Vector3(.10,.092,.16)),Vector3(0,-.02,.065),leather,"Boots")
		_mesh("shin"+side,_limb(.096,.13),Vector3(0,-.265,0),leather,"Boots")
	_mesh("handR",_box(Vector3(.038,.20,.04)),Vector3(0,-.02,.02),leather,"WeaponMain")
	_mesh("handR",_box(Vector3(.23,.035,.07)),Vector3(0,.09,.02),gold,"WeaponMain")
	_mesh("handR",_box(Vector3(.075,.49,.025)),Vector3(0,.35,.02),_material(Color("b9c5d0")),"WeaponMain")
	set_equipment(parts)
	pose_at(elapsed)

func set_equipment(parts:Dictionary)->void:
	if axis_rig!=null:
		if axis_rig.set_equipment(parts):equipment=parts.duplicate(true)
		else:push_error(axis_rig.last_error)
		return
	equipment=parts.duplicate(true)
	for category in ["Clothing1","Clothing2","Boots","Belt","WeaponMain","HeadAccessory"]:
		for mesh:MeshInstance3D in gear.get(category,[]):
			var variant:int=int(parts.get(category,0)) if parts.get(category)!=null else 0
			mesh.visible=variant>0 and (imported_rig==null or variant in mesh.get_meta("equipment_variants",[int(mesh.get_meta("equipment_variant",1))]))
	if imported_rig!=null:imported_rig.set_base_layers(self)

func play(next_action:String,next_direction:String,restart:bool=false,variant:String="")->void:
	if next_action not in ACTIONS:next_action="idle"
	# Repeated state packets and turning must not consume the next attack clip.
	if not restart and next_action==action and next_direction==direction and (variant.is_empty() or variant==animation_clip):return
	if axis_rig!=null and not restart and next_action==action and variant.is_empty():variant=animation_clip
	if axis_rig!=null:variant=axis_rig.select_clip(next_action,variant)
	if axis_rig!=null and not axis_rig.supports(variant if not variant.is_empty() else next_action):
		axis_rig.report_unsupported(variant if not variant.is_empty() else next_action);return
	_from_rotations.clear()
	_from_positions.clear()
	_from_axis_angles.clear()
	if axis_rig!=null:
		for node:Dictionary in axis_rig.body.nodes:_from_axis_angles[node.name]=node.angles
	if skeleton!=null:
		for i in range(skeleton.get_bone_count()):
			_from_rotations.append(skeleton.get_bone_pose_rotation(i))
			_from_positions.append(skeleton.get_bone_pose_position(i))
		_from_position=rig.position;_from_rotation=rig.quaternion
	_blend_elapsed=0.0;_blend_duration=.09 if next_action=="death" else .16
	var gait_phase:float=-1.0
	if next_action!=action or restart:
		if not restart and action in ["walk","dash"] and next_action in ["walk","dash"]:
			gait_phase=fposmod(elapsed/maxf(action_duration(),.001),1.0)
		else:elapsed=0.0
	action=next_action;direction=next_direction
	if imported_rig!=null:animation_clip=imported_rig.animations.select_clip(self,action,variant,true)
	if axis_rig!=null:animation_clip=variant if not variant.is_empty() else action
	if gait_phase>=0.0:elapsed=gait_phase*action_duration()
	pose_at(elapsed)
	_apply_blend(0)

func _process(delta:float)->void:
	_step_expressions(delta)
	elapsed+=delta*(locomotion_rate if action in ["walk","dash"] else 1.0)
	if axis_rig!=null and REST_NEXT.has(action) and elapsed>=action_duration() and axis_rig.supports(REST_NEXT[action]):
		play(REST_NEXT[action],direction,true)
	pose_at(elapsed)
	_apply_blend(delta)
	if axis_rig!=null:axis_rig.finish_frame(self,delta)
	if imported_rig!=null:
		if action in ["idle","walk","dash"]:preload("res://scripts/char/character_equipment_fit.gd").clear_hands(self)
		imported_rig.apply_weapon_grip(self)
		imported_rig.soft_motion.update(action,elapsed,delta,action_duration())
		imported_rig.hair_motion.update(self,delta)
		imported_rig.garment_motion.update(self,delta)

func _apply_blend(delta:float)->void:
	if _from_rotations.is_empty():return
	_blend_elapsed+=delta
	var weight:=smoothstep(0,_blend_duration,_blend_elapsed)
	for i in range(skeleton.get_bone_count()):
		skeleton.set_bone_pose_rotation(i,_from_rotations[i].slerp(skeleton.get_bone_pose_rotation(i),weight))
		skeleton.set_bone_pose_position(i,_from_positions[i].lerp(skeleton.get_bone_pose_position(i),weight))
	rig.position=_from_position.lerp(rig.position,weight)
	rig.quaternion=_from_rotation.slerp(rig.quaternion,weight)
	if axis_rig!=null and not axis_rig.sync_blend(self,_from_axis_angles,weight):push_error(axis_rig.last_error)
	if weight>=1.0:_from_rotations.clear()

func pose_at(time:float)->void:
	_pose_base(time)
	if imported_rig!=null:imported_rig.apply_weapon_grip(self)
	if imported_rig!=null and action in ["idle","walk","dash"]:preload("res://scripts/char/character_equipment_fit.gd").clear_hands(self)
	if imported_rig!=null:imported_rig.garment_motion.update(self,0)

func _pose_base(time:float)->void:
	if skeleton==null:return
	rig.rotation=Vector3(0,float(YAW.get(direction,0.0)),0)
	rig.position=Vector3.ZERO
	if axis_rig!=null:
		if not axis_rig.pose(self,time):push_error(axis_rig.last_error)
		return
	skeleton.reset_bone_poses()
	if imported_rig!=null:imported_rig.reset_pose(self)
	if imported_rig!=null and imported_rig.animations.apply(self,time):return
	if imported_rig!=null and Motion.apply(self,time):return
	var wave:=sin(time*(12.0 if action=="dash" else 7.0))
	match action:
		"idle":_rotate("spine",Vector3(sin(time*2)*.015,0,0))
		"walk","dash":
			var amp:=.85 if action=="dash" else .52
			_rotate("thighL",Vector3(wave*amp,0,0));_rotate("thighR",Vector3(-wave*amp,0,0))
			_rotate("shinL",Vector3(maxf(0,-wave)*.8,0,0));_rotate("shinR",Vector3(maxf(0,wave)*.8,0,0))
			_rotate("armL",Vector3(-wave*amp,0,-.10));_rotate("armR",Vector3(wave*amp,0,.10))
			if action=="dash":_rotate("spine",Vector3(.20,0,0))
			rig.position.y=absf(wave)*.025
		"attack":
			var p:=clampf(time/.65,0,1)
			var strike:=sin(p*PI)
			_rotate("spine",Vector3(0,-strike*.45,0));_rotate("armR",Vector3(-strike*1.8,0,-.15))
			_rotate("forearmR",Vector3(-.35*(1-strike),0,0))
		"cast":
			_rotate("armL",Vector3(-1.25,0,-.45));_rotate("armR",Vector3(-1.25,0,.45))
			_rotate("forearmL",Vector3(-.3,0,0));_rotate("forearmR",Vector3(-.3,0,0))
		"death":
			var p:=smoothstep(0,.65,time)
			rig.rotation.z=-PI/2*p
			rig.position=Vector3(-.65*p,.24*p,0)
		"sit_chair","sit_ground":
			var ground:=action=="sit_ground"
			rig.position.y=-.58 if ground else -.34
			for side in ["L","R"]:
				var sign_z:float=-1.0 if side=="L" else 1.0
				_rotate("thigh"+side,Vector3(-1.25 if ground else -PI/2,0,sign_z*.7 if ground else 0))
				_rotate("shin"+side,Vector3(2.0 if ground else PI/2,0,-sign_z*.5 if ground else 0))
				_rotate("arm"+side,Vector3(-.65,0,sign_z*.15))
				_rotate("forearm"+side,Vector3(-.65,0,0))
				if ground and imported_rig==null:
					# Place both knees outwards and both feet inwards, just above the floor.
					var upper:=Quaternion(Vector3.DOWN,Vector3(sign_z*.25,-.08,.216).normalized())
					var lower:=Quaternion(Vector3.DOWN,Vector3(-sign_z*.31,-.02,.07).normalized())
					skeleton.set_bone_pose_rotation(bones["thigh"+side],upper)
					skeleton.set_bone_pose_rotation(bones["shin"+side],upper.inverse()*lower)
					skeleton.set_bone_pose_rotation(bones["foot"+side],lower.inverse())
	if imported_rig!=null:imported_rig.finish_pose(self)

func _bone(id:String,parent:String,origin:Vector3)->void:
	var index:=skeleton.get_bone_count();skeleton.add_bone(id);bones[id]=index
	if not parent.is_empty():skeleton.set_bone_parent(index,bones[parent])
	skeleton.set_bone_rest(index,Transform3D(Basis.IDENTITY,origin))
func _rotate(id:String,euler:Vector3)->void:
	if imported_rig!=null:imported_rig.rotate(self,id,Quaternion.from_euler(euler))
	else:skeleton.set_bone_pose_rotation(bones[id],Quaternion.from_euler(euler))
func _mesh(bone:String,shape:Mesh,origin:Vector3,mat:Material,category:String)->MeshInstance3D:
	var attachment:=BoneAttachment3D.new();attachment.bone_name=bone;skeleton.add_child(attachment)
	var mesh:=MeshInstance3D.new();mesh.mesh=shape;mesh.material_override=mat;mesh.position=origin;attachment.add_child(mesh)
	if not gear.has(category):gear[category]=[]
	gear[category].append(mesh)
	return mesh
func _material(color:Color)->StandardMaterial3D:
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.92
	return mat
func _ellipsoid(size:Vector3)->ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sphere:=SphereMesh.new();sphere.radius=1;sphere.height=2;sphere.radial_segments=16;sphere.rings=10
	st.create_from(sphere,0)
	var arrays:=st.commit().surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	for i in range(vertices.size()):vertices[i]*=size;normals[i]=(normals[i]/size).normalized()
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return result
func _limb(radius:float,height:float)->CapsuleMesh:
	var mesh:=CapsuleMesh.new();mesh.radius=radius;mesh.height=maxf(height,radius*2);mesh.radial_segments=12;mesh.rings=4;return mesh
func _box(size:Vector3)->BoxMesh:
	var mesh:=BoxMesh.new();mesh.size=size;return mesh
func _hair_cap()->ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(8):
		for x in range(24):
			for uv in [Vector2(x,y),Vector2(x+1,y+1),Vector2(x+1,y),Vector2(x,y),Vector2(x,y+1),Vector2(x+1,y+1)]:
				var az:float=uv.x/24*TAU
				var end:=1.12 if cos(az)>.4 else 1.95
				var polar:float=uv.y/8*end
				var n:=Vector3(sin(polar)*sin(az),cos(polar),sin(polar)*cos(az))
				st.set_normal(n);st.add_vertex(n*Vector3(.33,.43,.31))
	return st.commit()
func _color(custom:Dictionary,group:String,fallback:Color)->Color:
	if not bool(custom.get(group+"_on",false)):return fallback
	var mv=load("res://scripts/char/mv_generator.gd")
	var row:int=int(custom.get(group+"_row",-1))
	return mv.row_color(row) if row>=0 else fallback




static func _structural_appearance(value:Dictionary)->Dictionary:
	var result:=value.duplicate(true)
	for key in ["hair_row","hair_on","bust_size","skin_row","skin_on","eye_color","cloth_row","cloth_on"]:result.erase(key)
	if result.has("part_ids"):result.part_ids.erase("FrontHair1")
	return result

func action_duration()->float:
	if axis_rig!=null:return axis_rig.duration(animation_clip if not animation_clip.is_empty() else action)
	return imported_rig.animations.duration(self) if imported_rig!=null else float(Motion.DURATION.get(action,1.0))

static func source_available(gender:String,custom:Dictionary)->bool:
	if custom.get("body_model","")=="female_base_v2":return gender=="female" and AxisRig.available()
	return ImportedRig.available(gender) if gender in ["male","female"] else true


static func create(gender: String, custom: Dictionary, parts: Dictionary) -> Node3D:
	var model = load("res://scripts/char/character_model_3d.gd").new()
	model.body_type = gender
	model.appearance = custom.duplicate(true)
	model.equipment = parts.duplicate(true)
	return model

static func create_npc(recipe: Dictionary) -> Node3D:
	recipe=recipe.duplicate(true)
	preload("res://scripts/char/character_body_migration.gd").apply(recipe)
	return create(str(recipe.get("gender", "male")), recipe.get("customization", {}), recipe.get("equipment", {"Clothing1": 1, "Clothing2": 1, "Boots": 1}))
