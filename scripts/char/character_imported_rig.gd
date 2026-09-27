extends RefCounted
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
## Adapts the user-supplied weighted model to the existing character controller.
## Original mesh weights and facial blend shapes are retained in the GLB.
static func source_path(gender:String)->String:
	return ArtPaths.path("characters/imported/" + gender + "/character.glb") if gender in ["male", "female"] else ""

const MAP := {"hips":"Hips","spine":"Spine","head":"Head", "armL":"RightArm","forearmL":"RightForeArm","handL":"RightHand", "armR":"LeftArm","forearmR":"LeftForeArm","handR":"LeftHand", "thighL":"RightUpLeg","shinL":"RightLeg","footL":"RightFoot", "thighR":"LeftUpLeg","shinR":"LeftLeg","footR":"LeftFoot"}
static var packed_by_path:Dictionary={}
static var masked_meshes:Dictionary={}
static var bust_shapes:Dictionary={}
var bust_instances:Array=[]
var basis_by_id:Dictionary={}
var baseline:Dictionary={}
var rest_positions:Dictionary={}
var animations=preload("res://scripts/char/character_animation_library.gd").new()
var soft_motion=preload("res://scripts/char/character_soft_motion.gd").new()
var garment_motion=preload("res://scripts/char/character_garment_motion.gd").new()
var hair_cache:Dictionary={}
var hair_prepared:=false
var original_hair:Array=[]
var hair_motion=preload("res://scripts/char/character_hair_3d.gd").new()
var body_materials:Array[ShaderMaterial]=[]
const SkinMaterial=preload("res://scripts/char/character_skin_material.gd")
const SKIN_LIGHTING := SkinMaterial.LIGHT
const BODY_SHADER := """shader_type spatial;
render_mode diffuse_lambert_wrap;
uniform vec4 skin_color : source_color = vec4(1.0);
uniform bool cover_top = false;
uniform bool cover_bottom = false;
uniform bool cover_feet = false;
uniform bool wearing_dress = false;
uniform bool skin_maps_enabled = false;
uniform sampler2D skin_basecolor : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D skin_orm : filter_linear_mipmap_anisotropic;
"""+SkinMaterial.SURFACE+"""
void fragment() {
    bool top = !wearing_dress && cover_top && COLOR.r > 0.25;
    // A skirt can expose the thighs during motion. It must not use the
    // trouser mask: the cloth itself occludes the underlying legs.
    bool bottom = !wearing_dress && cover_bottom && COLOR.g > 0.25;
    bool feet = cover_feet && COLOR.b > 0.5;
    if (top || bottom || feet) { discard; }
    float grain=skin_grain(UV);
    NORMAL=normalize(NORMAL+TANGENT*grain*0.004+BINORMAL*skin_grain(UV+vec2(0.173,0.319))*0.004);
    ALBEDO = skin_color.rgb*mix(vec3(1.0),vec3(1.015,0.94,0.915),UV2.x);
    AO = COLOR.a;
    AO_LIGHT_AFFECT = 0.32;
    EMISSION = ALBEDO * skin_fill(NORMAL,INV_VIEW_MATRIX) * COLOR.a;
    ROUGHNESS = 0.48 + UV2.x*0.08 + grain*0.015;
    SPECULAR = 0.30;
    if (skin_maps_enabled) {
        // The authored default is ff/ea/db in sRGB, decoded to linear here.
        ALBEDO=skin_color.rgb*texture(skin_basecolor,UV).rgb/vec3(1.0,0.822786,0.708376);
        vec3 orm=texture(skin_orm,UV).rgb;
        AO=orm.r;ROUGHNESS=orm.g;
        NORMAL_MAP=texture(skin_normal,UV).rgb;
        NORMAL_MAP_DEPTH=0.65;
        EMISSION=ALBEDO*skin_fill(NORMAL,INV_VIEW_MATRIX)*AO;
    }
}
""" + SKIN_LIGHTING
const TINT_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D source_texture : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform int tint_mode = 0;
uniform bool eye_enabled = false;
uniform vec4 eye_color : source_color = vec4(1.0);
void fragment() {
    vec4 tex = texture(source_texture, UV);
    vec3 color = tex.rgb;
    if (tint_mode == 1 && color.r > 0.48 && color.r > color.g && color.g > color.b * 1.025) {
        color *= tint.rgb / vec3(0.91, 0.77, 0.66);
    } else if (tint_mode == 2) {
        float value = dot(color, vec3(0.299, 0.587, 0.114));
        color = tint.rgb * value;
    }
    // The supplied face atlas has green irises. Preserve the black pupil,
    // white highlight and skin; only replace the chromatic iris pixels.
    if (eye_enabled && tex.g > tex.r * 1.03 && tex.g > tex.b * 1.12 && tex.g > 0.035) {
        float value = clamp(tex.g / 0.35, 0.15, 1.35);
        color = eye_color.rgb * value;
    }
    ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
}
"""
const FACE_SHADER := """shader_type spatial;
render_mode diffuse_lambert_wrap, cull_disabled;
uniform sampler2D source_texture : source_color, filter_linear_mipmap;
uniform vec4 skin_color : source_color = vec4(1.0);
uniform vec4 source_skin_color : source_color;
uniform bool eye_enabled = false;
uniform vec4 eye_color : source_color = vec4(1.0);
"""+SkinMaterial.SURFACE+"""
void fragment() {
    vec3 color = texture(source_texture, UV).rgb;
    // Normalize the atlas's base skin to the same albedo as the body,
    // retaining painted blush, lips, lashes and the iris details.
    if (color.r > 0.48 && color.r > color.g && color.g > color.b * 1.025) {
        color *= skin_color.rgb / source_skin_color.rgb;
    }
    if (eye_enabled && color.g > color.r * 1.03 && color.g > color.b * 1.12 && color.g > 0.035) {
        float value = clamp(color.g / 0.35, 0.15, 1.35);
        color = eye_color.rgb * value;
    }
    ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
    ROUGHNESS = 0.48 + skin_grain(UV)*0.015;
    SPECULAR = 0.30;
    EMISSION = ALBEDO * skin_fill(NORMAL,INV_VIEW_MATRIX);
}
""" + SKIN_LIGHTING

static func available(gender:String)->bool:
	return FileAccess.file_exists(source_path(gender))

func install(model:Node3D)->bool:
	var path:String=source_path(model.body_type)
	if not packed_by_path.has(path):
		var document:=GLTFDocument.new();var state:=GLTFState.new()
		if document.append_from_file(path,state)!=OK:return false
		var source:=document.generate_scene(state)
		var packed:=PackedScene.new()
		var error:=packed.pack(source);source.free()
		if error!=OK:return false
		packed_by_path[path]=packed
	var source:Node3D=packed_by_path[path].instantiate()
	model.rig.add_child(source)
	model.rig.scale=Vector3.ONE*.8
	var skeletons:=source.find_children("*","Skeleton3D",true,false)
	if skeletons.is_empty():source.queue_free();return false
	model.skeleton.free();model.skeleton=skeletons[0]
	for id in MAP:
		var index:int=model.skeleton.find_bone("mixamorig_"+MAP[id])
		if index<0:return false
		model.bones[id]=index
		var transform:Transform3D=model.rig.global_transform.affine_inverse()*model.skeleton.global_transform*model.skeleton.get_bone_global_rest(index)
		basis_by_id[id]=transform.basis.orthonormalized().get_rotation_quaternion()
		rest_positions[id]=transform.origin
	for entry in [["chest","Spine1"],["upper_chest","Spine2"],["neck","Neck"]]:
		var index:int=model.skeleton.find_bone("mixamorig_"+entry[1])
		if index<0:continue
		model.bones[entry[0]]=index
		var transform:Transform3D=model.rig.global_transform.affine_inverse()*model.skeleton.global_transform*model.skeleton.get_bone_global_rest(index)
		basis_by_id[entry[0]]=transform.basis.orthonormalized().get_rotation_quaternion()
		rest_positions[entry[0]]=transform.origin
	baseline["armL"]=Quaternion(Vector3.BACK,deg_to_rad(76))
	baseline["armR"]=Quaternion(Vector3.BACK,deg_to_rad(-76))
	for category in ["Body","Hair","Eyes","Clothing1","Clothing2","Boots","Belt","WeaponMain","BaseTop","BaseBottom","HeadAccessory"]:model.gear[category]=[]
	for mesh in source.find_children("*","MeshInstance3D",true,false):
		var category:=str(mesh.name)
		if category=="SkirtVariant":mesh.visible=false;continue
		if category=="Face":category="Body"
		if category=="HairAccessory":category="Hair"
		if category=="HairBack":category="Hair"
		if category=="Stockings":category="Boots"
		if not model.gear.has(category):category="Body"
		model.gear[category].append(mesh)
		_tint_mesh(model,mesh,category)
		if category in ["BaseTop","BaseBottom"]:
			mesh.material_override=preload("res://scripts/char/character_underwear_material.gd").for_body(model.body_type)
		if model.body_type=="female" and mesh.name in ["Body","Clothing1","BaseTop"]:
			_apply_bust(mesh,Customization.valid_bust_size(model.appearance.get("bust_size",0.5)))
	for mesh in model.gear.Hair:
		mesh.visible=int(model.appearance.get("part_ids",{}).get("FrontHair1",1))>0
	original_hair=model.gear.Hair.duplicate()
	hair_motion.install(model)
	hair_cache[int(model.appearance.get("part_ids",{}).get("FrontHair1",1))]=hair_motion
	_add_accessories(model)
	preload("res://scripts/char/character_equipment_3d.gd").install(model,self)
	soft_motion.install(model)
	garment_motion.install(model,rest_positions)
	animations.install(model)
	return true

func _tint_mesh(model:Node3D,mesh:MeshInstance3D,category:String)->void:
	var group:String="hair" if category=="Hair" else ("skin" if category=="Body" else "cloth")
	if category not in ["Hair","Body","Clothing1","Clothing2"]:return
	var tint_enabled:bool=bool(model.appearance.get(group+"_on",false))
	if group=="hair" and model.body_type=="male":tint_enabled=true
	var is_body:bool=mesh.name=="Body"
	var eyes:String=Customization.valid_eye_color(model.appearance.get("eye_color","")) if mesh.name=="Face" else ""
	if mesh.name=="Face":
		for i in mesh.mesh.get_surface_count():
			var material = mesh.get_surface_override_material(i)
			if not material is ShaderMaterial:
				var original = mesh.mesh.surface_get_material(i)
				if not original is StandardMaterial3D:continue
				material=ShaderMaterial.new()
				var shader:=Shader.new();shader.code=FACE_SHADER;material.shader=shader
				material.set_shader_parameter("source_texture",original.albedo_texture if original.albedo_texture!=null else original.emission_texture)
				# Most frequent skin texel in the supplied atlas (sRGB).
				material.set_shader_parameter("source_skin_color",Color("faebde"))
				mesh.set_surface_override_material(i,material)
			material.set_shader_parameter("skin_color",model._color(model.appearance,"skin",Color("ffeadb")))
			material.set_shader_parameter("eye_enabled",not eyes.is_empty())
			material.set_shader_parameter("eye_color",Color.from_string(eyes,Color.WHITE))
		return
	if not tint_enabled and not is_body and eyes.is_empty() and not mesh.get_surface_override_material(0) is ShaderMaterial:
		for i in range(mesh.mesh.get_surface_count()):mesh.set_surface_override_material(i,null)
		return
	var color:Color=model._color(model.appearance,group,Color("665044") if group=="hair" else Color.WHITE)
	if mesh.name=="Body":
		if mesh.material_override is ShaderMaterial:
			mesh.material_override.set_shader_parameter("skin_color",model._color(model.appearance,"skin",Color("ffeadb")))
			return
		_mask_body(mesh,model.body_type=="male",model.skeleton)
		var shader:=Shader.new();shader.code=BODY_SHADER
		var material:=ShaderMaterial.new();material.shader=shader
		material.set_shader_parameter("skin_color",model._color(model.appearance,"skin",Color("ffeadb")))
		SkinMaterial.apply_maps(material,model.body_type)
		mesh.material_override=material
		body_materials.append(material)
		return
	for i in range(mesh.mesh.get_surface_count()):
		var current=mesh.get_surface_override_material(i)
		if current is ShaderMaterial:
			current.set_shader_parameter("tint",color)
			current.set_shader_parameter("tint_mode",(1 if group=="skin" else 2) if tint_enabled else 0)
			current.set_shader_parameter("eye_enabled",not eyes.is_empty())
			current.set_shader_parameter("eye_color",Color.from_string(eyes,Color.WHITE))
			continue
		var original=mesh.mesh.surface_get_material(i)
		if not original is StandardMaterial3D:continue
		var texture:Texture2D=original.albedo_texture if original.albedo_texture!=null else original.emission_texture
		if texture==null:
			if tint_enabled:
				var plain:StandardMaterial3D=original.duplicate();plain.albedo_color=color
				if group=="hair":plain.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;plain.cull_mode=BaseMaterial3D.CULL_DISABLED
				mesh.set_surface_override_material(i,plain)
			continue
		var shader:=Shader.new();shader.code=TINT_SHADER
		var material:=ShaderMaterial.new();material.shader=shader
		material.set_shader_parameter("source_texture",texture)
		material.set_shader_parameter("tint",color)
		material.set_shader_parameter("tint_mode",(1 if group=="skin" else 2) if tint_enabled else 0)
		material.set_shader_parameter("eye_enabled",not eyes.is_empty())
		material.set_shader_parameter("eye_color",Color.from_string(eyes,Color.WHITE))
		mesh.set_surface_override_material(i,material)

static func _bust_point(point:Vector3,amount:float)->Vector3:
	var weight:=exp(-pow((absf(point.x)-.085)/.115,4.0)-pow((point.y-1.70)/.15,4.0))*smoothstep(.03,.11,point.z)
	return point+Vector3(signf(point.x)*.008,.012,.055)*amount*weight

func _apply_bust(mesh:MeshInstance3D,size:float)->void:
	var key:int=mesh.mesh.get_instance_id()
	if not bust_shapes.has(key):
		var result:=ArrayMesh.new()
		result.add_blend_shape("BustSmall");result.add_blend_shape("BustLarge")
		result.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_NORMALIZED
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays:Array=mesh.mesh.surface_get_arrays(surface)
			var shapes:Array[Array]=[]
			for amount in [-1.0,1.0]:
				var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
				var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL].duplicate()
				for i in range(vertices.size()):
					var p:Vector3=vertices[i];var moved:=_bust_point(p,amount)
					if moved.is_equal_approx(p):continue
					var jacobian:=Basis((_bust_point(p+Vector3(.0001,0,0),amount)-moved)/.0001,(_bust_point(p+Vector3(0,.0001,0),amount)-moved)/.0001,(_bust_point(p+Vector3(0,0,.0001),amount)-moved)/.0001)
					vertices[i]=moved;normals[i]=(jacobian.inverse().transposed()*normals[i]).normalized()
				var shape:Array=[];shape.resize(Mesh.ARRAY_MAX)
				shape[Mesh.ARRAY_VERTEX]=vertices;shape[Mesh.ARRAY_NORMAL]=normals
				shape[Mesh.ARRAY_TANGENT]=arrays[Mesh.ARRAY_TANGENT]
				shapes.append(shape)
			var flags:int=Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if arrays[Mesh.ARRAY_BONES].size()==arrays[Mesh.ARRAY_VERTEX].size()*8 else 0
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,shapes,{},flags)
			result.surface_set_material(surface,mesh.mesh.surface_get_material(surface))
		if mesh.mesh.has_meta("skin_detail_match_ratio"):result.set_meta("skin_detail_match_ratio",mesh.mesh.get_meta("skin_detail_match_ratio"))
		bust_shapes[key]=result
	mesh.mesh=bust_shapes[key]
	bust_instances.append(mesh)
	_set_bust_weights(mesh,size)

static func _set_bust_weights(mesh:MeshInstance3D,size:float)->void:
	mesh.set_blend_shape_value(0,maxf(0.0,(.5-size)*2.0))
	mesh.set_blend_shape_value(1,maxf(0.0,(size-.5)*2.0))

func update_bust(size:float)->void:
	for mesh in bust_instances:_set_bust_weights(mesh,size)

func _mask_body(mesh:MeshInstance3D,male:bool,skeleton:Skeleton3D)->void:
	var key:int=mesh.mesh.get_instance_id()
	if masked_meshes.has(key):mesh.mesh=masked_meshes[key];return
	var result:=ArrayMesh.new()
	var detail:Dictionary=SkinMaterial.detail_for("male" if male else "female")
	var matched:=0;var total:=0
	for i in range(mesh.mesh.get_surface_count()):
		var arrays:Array=mesh.mesh.surface_get_arrays(i)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var skin_bones=arrays[Mesh.ARRAY_BONES];var skin_weights=arrays[Mesh.ARRAY_WEIGHTS]
		var influences:int=skin_bones.size()/vertices.size()
		var arm_bindings:Dictionary={}
		for binding in mesh.skin.get_bind_count():
			var name:String=mesh.skin.get_bind_name(binding)
			if name.is_empty():name=skeleton.get_bone_name(mesh.skin.get_bind_bone(binding))
			if "Arm" in name or "Hand" in name:arm_bindings[binding]=true
		var colors:=PackedColorArray();colors.resize(vertices.size())
		var skin_details:=PackedVector2Array();skin_details.resize(vertices.size())
		for v in range(vertices.size()):
			var p:Vector3=vertices[v]
			var top:bool=p.y>(1.50 if male else 1.45) and p.y<(1.98 if male else 1.915) and absf(p.x)<(.92 if male else .79)
			var bottom:bool=p.y>.145 and p.y<(1.49 if male else 1.46)
			var arm_weight:float=0
			for influence in influences:
				if arm_bindings.has(skin_bones[v*influences+influence]):arm_weight+=skin_weights[v*influences+influence]
			var sample:Array=detail.get(SkinMaterial.key(p),[1.0,0.0])
			if detail.has(SkinMaterial.key(p)):matched+=1
			total+=1
			colors[v]=Color((.5 if arm_weight>.15 else 1) if top else 0,(1 if p.y>.95 else .5) if bottom else 0,1 if p.y<.88 else 0,float(sample[0]))
			skin_details[v]=Vector2(float(sample[1]),0)
		arrays[Mesh.ARRAY_COLOR]=colors
		arrays[Mesh.ARRAY_TEX_UV2]=skin_details
		var flags:int=Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if arrays[Mesh.ARRAY_BONES].size()==vertices.size()*8 else 0
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)
		result.surface_set_material(i,mesh.mesh.surface_get_material(i))
	masked_meshes[key]=result;mesh.mesh=result
	result.set_meta("skin_detail_match_ratio",float(matched)/maxi(total,1))

func _accessory(model:Node3D,id:String,shape:Mesh,origin:Vector3,mat:Material,category:String)->void:
	var attach:=BoneAttachment3D.new();attach.bone_name=model.skeleton.get_bone_name(model.bones[id]);model.skeleton.add_child(attach)
	var mesh:=MeshInstance3D.new();mesh.mesh=shape;mesh.material_override=mat;attach.add_child(mesh)
	var rest:Transform3D=model.rig.global_transform.affine_inverse()*model.skeleton.global_transform*model.skeleton.get_bone_global_rest(model.bones[id])
	mesh.transform=rest.affine_inverse()*Transform3D(Basis.IDENTITY,origin)
	model.gear[category].append(mesh)

func _add_accessories(model:Node3D)->void:
	var leather:Material=model._material(Color("4b3326"));var brass:Material=model._material(Color("c3a369"))
	var sk:Skeleton3D=model.skeleton
	var hand:Transform3D=sk.get_bone_global_rest(model.bones.handL)
	var index:Vector3=sk.get_bone_global_rest(sk.find_bone("mixamorig_RightHandIndex1")).origin
	var pinky:Vector3=sk.get_bone_global_rest(sk.find_bone("mixamorig_RightHandPinky1")).origin
	var middle:Vector3=sk.get_bone_global_rest(sk.find_bone("mixamorig_RightHandMiddle1")).origin
	var along:Vector3=(middle-hand.origin).normalized()
	var blade:Vector3=(index-pinky).normalized()
	var normal:Vector3=blade.cross(along).normalized()
	# A socket in the closed palm, with the blade exiting on the thumb side.
	blade=along.cross(normal).normalized()
	var socket:=Transform3D(Basis(-along,blade,normal),(index+pinky)*.5+normal*.018)
	var attachment:=BoneAttachment3D.new();attachment.name="WeaponGrip";attachment.bone_name=sk.get_bone_name(model.bones.handL);sk.add_child(attachment)
	for part in [[Vector3(.026,.12,.026),0.0,leather],[Vector3(.14,.022,.035),.074,brass],[Vector3(.048,.46,.016),.315,model._material(Color("bac8d3"))]]:
		var mesh:=MeshInstance3D.new();mesh.mesh=model._box(part[0]);mesh.material_override=part[2];attachment.add_child(mesh)
		mesh.transform=hand.affine_inverse()*socket*Transform3D(Basis.IDENTITY,Vector3(0,part[1],0))
		model.gear.WeaponMain.append(mesh)

func apply_weapon_grip(model:Node3D)->void:
	if model.equipment.get("WeaponMain")==null or int(model.equipment.get("WeaponMain",0))<=0:return
	var sk:Skeleton3D=model.skeleton
	for finger in ["Index","Middle","Ring","Pinky"]:
		for segment in range(1,4):
			var id:int=sk.find_bone("mixamorig_RightHand%s%d"%[finger,segment])
			if id<0:continue
			var angle:float=[1.15,1.4,.7][segment-1]
			sk.set_bone_pose_rotation(id,sk.get_bone_rest(id).basis.get_rotation_quaternion()*Quaternion(Vector3.RIGHT,angle))
	for segment in range(1,4):
		var id:int=sk.find_bone("mixamorig_RightHandThumb%d"%segment)
		if id>=0:
			var opposition:=Quaternion(Vector3.BACK,.65) if segment==1 else Quaternion.IDENTITY
			sk.set_bone_pose_rotation(id,sk.get_bone_rest(id).basis.get_rotation_quaternion()*opposition*Quaternion(Vector3.RIGHT,[.75,.9,1.0][segment-1]))

func rotate(model:Node3D,id:String,rotation:Quaternion)->void:
	var basis:Quaternion=basis_by_id[id]
	if id.begins_with("arm"):
		rotation=rotation*baseline[id]
	elif id.begins_with("forearm") or id.begins_with("hand"):
		var parent_base:Quaternion=baseline["arm"+id.right(1)]
		rotation=parent_base.inverse()*rotation*parent_base
	var rest:Quaternion=model.skeleton.get_bone_rest(model.bones[id]).basis.get_rotation_quaternion()
	model.skeleton.set_bone_pose_rotation(model.bones[id],rest*basis.inverse()*rotation*basis)

func reset_pose(model:Node3D)->void:
	for id in baseline:rotate(model,id,Quaternion.IDENTITY)

func _global_rotation(model:Node3D,id:String,delta:Quaternion)->void:
	var index:int=model.bones[id]
	var relative:Transform3D=model.rig.global_transform.affine_inverse()*model.skeleton.global_transform
	var parent:int=model.skeleton.get_bone_parent(index)
	var parent_basis:Basis=relative.basis
	if parent>=0:parent_basis=relative.basis*model.skeleton.get_bone_global_pose(parent).basis
	var desired:=Basis(delta*basis_by_id[id])
	model.skeleton.set_bone_pose_rotation(index,(parent_basis.orthonormalized().inverse()*desired).get_rotation_quaternion())

func plant_leg(model:Node3D,side:String,offset:Vector3,pitch:float)->void:
	var upper:String="thigh"+side;var lower:String="shin"+side;var foot:String="foot"+side
	var relative:Transform3D=model.rig.global_transform.affine_inverse()*model.skeleton.global_transform
	var hip:Vector3=(relative*model.skeleton.get_bone_global_pose(model.bones[upper])).origin
	var a:float=rest_positions[upper].distance_to(rest_positions[lower])
	var b:float=rest_positions[lower].distance_to(rest_positions[foot])
	var target:Vector3=rest_positions[foot]+offset
	var axis:Vector3=(target-hip).normalized()
	var distance:float=clampf(hip.distance_to(target),absf(a-b)+.001,a+b-.001)
	var along:float=(a*a-b*b+distance*distance)/(2*distance)
	var bend:Vector3=(Vector3.BACK-axis*Vector3.BACK.dot(axis)).normalized()
	var knee:Vector3=hip+axis*along+bend*sqrt(maxf(0,a*a-along*along))
	_global_rotation(model,upper,Quaternion((rest_positions[lower]-rest_positions[upper]).normalized(),(knee-hip).normalized()))
	_global_rotation(model,lower,Quaternion((rest_positions[foot]-rest_positions[lower]).normalized(),(target-knee).normalized()))
	_global_rotation(model,foot,Quaternion(Vector3.RIGHT,pitch))

func set_base_layers(model:Node3D)->void:
	var dress:=false
	for category in ["Clothing1","Clothing2"]:
		for mesh:MeshInstance3D in model.gear[category]:
			if mesh.visible and mesh.get_meta("garment_kind","")=="skirt":dress=true
	# The imported starter boots include separate long stockings. Trousers
	# already cover that layer; rendering both lets the stocking shell poke out.
	var trousers:bool=not dress and int(model.equipment.get("Clothing2",0))>0 if model.equipment.get("Clothing2")!=null else false
	for mesh in model.gear.Boots:
		if mesh.name=="Stockings":mesh.visible=not trousers and model.equipment.get("Boots")==1
	for mesh in model.gear.Clothing1:
		if mesh.name=="MaidDress" and mesh.material_override is ShaderMaterial:
			mesh.material_override.set_shader_parameter("black_variant",model.equipment.get("Clothing1")==3)
	for mesh in model.gear.Clothing2:mesh.visible=not dress and model.equipment.get("Clothing2")!=null and int(model.equipment.Clothing2)>0
	for mesh in model.gear.Belt:mesh.visible=not dress and model.equipment.get("Belt")!=null and int(model.equipment.Belt)>0
	for entry in [["BaseTop","Clothing1"],["BaseBottom","Clothing2"]]:
		for mesh in model.gear.get(entry[0],[]):
			mesh.visible=model.equipment.get(entry[1])==null or int(model.equipment.get(entry[1],0))<=0
			if dress and entry[0]=="BaseBottom":mesh.visible=true
	for material in body_materials:
		material.set_shader_parameter("wearing_dress",dress)
		for entry in [["cover_top","Clothing1"],["cover_bottom","Clothing2"],["cover_feet","Boots"]]:
			material.set_shader_parameter(entry[0],(dress if entry[0]=="cover_bottom" else false) or (model.equipment.get(entry[1])!=null and int(model.equipment.get(entry[1],0))>0))

func finish_pose(model:Node3D)->void:
	if model.action=="sit_chair":
		for side in ["L","R"]:
			_global_rotation(model,"thigh"+side,Quaternion((rest_positions["shin"+side]-rest_positions["thigh"+side]).normalized(),Vector3.BACK))
			_global_rotation(model,"shin"+side,Quaternion((rest_positions["foot"+side]-rest_positions["shin"+side]).normalized(),Vector3.DOWN))
			_global_rotation(model,"foot"+side,Quaternion.IDENTITY)
		var relative:Transform3D=model.rig.global_transform.affine_inverse()*model.skeleton.global_transform
		var offset:float=0
		for side in ["L","R"]:
			var foot:Vector3=(relative*model.skeleton.get_bone_global_pose(model.bones["foot"+side])).origin
			offset+=(rest_positions["foot"+side].y-foot.y)*.5
		model.rig.position.y=offset*model.rig.scale.y
		_rest_seated_hands(model)
	if model.action=="sit_ground":
		model.rig.position.y=-.80
		for side in ["L","R"]:
			var sign_x:float=-1.0 if side=="L" else 1.0
			var upper:=Quaternion(Vector3.DOWN,Vector3(sign_x*.32,-.07,.30).normalized())
			var lower:=Quaternion(Vector3.DOWN,Vector3(-sign_x*.34,-.035,.31).normalized())
			rotate(model,"thigh"+side,upper)
			rotate(model,"shin"+side,upper.inverse()*lower)
			rotate(model,"foot"+side,lower.inverse())

func _rest_seated_hands(model:Node3D)->void:
	var sk:Skeleton3D=model.skeleton
	var relative:Transform3D=model.rig.global_transform.affine_inverse()*sk.global_transform
	for side in ["L","R"]:
		if side=="L" and model.equipment.get("WeaponMain")!=null and int(model.equipment.WeaponMain)>0:continue
		var upper:int=model.bones["arm"+side];var lower:int=model.bones["forearm"+side];var hand:int=model.bones["hand"+side]
		var shoulder:Vector3=(relative*sk.get_bone_global_pose(upper)).origin
		var elbow:Vector3=(relative*sk.get_bone_global_pose(lower)).origin
		var wrist:Vector3=(relative*sk.get_bone_global_pose(hand)).origin
		var thigh:Vector3=(relative*sk.get_bone_global_pose(model.bones["thigh"+side])).origin
		var knee:Vector3=(relative*sk.get_bone_global_pose(model.bones["shin"+side])).origin
		var forward:Vector3=(knee-thigh).normalized()
		var middle:int=sk.find_bone(sk.get_bone_name(hand)+"Middle1")
		var fingers:Vector3=(relative*sk.get_bone_global_rest(middle)).origin-rest_positions["hand"+side]
		var target:Vector3=thigh.lerp(knee,.65)+Vector3.UP*garment_motion.leg_radius-forward*fingers.length()*.5
		var a:float=shoulder.distance_to(elbow);var b:float=elbow.distance_to(wrist)
		var axis:Vector3=(target-shoulder).normalized();var distance:float=minf(target.distance_to(shoulder),(a+b)*.98)
		target=shoulder+axis*distance
		var along:float=(a*a-b*b+distance*distance)/(2*distance)
		var outward:=Vector3(signf(shoulder.x),0,0);var bend:Vector3=(outward-axis*outward.dot(axis)).normalized()
		var joint:Vector3=shoulder+axis*along+bend*sqrt(maxf(0,a*a-along*along))
		var fit=preload("res://scripts/char/character_equipment_fit.gd")
		fit._rotate_towards(sk,relative,upper,lower,joint);fit._rotate_towards(sk,relative,lower,hand,target)
		_global_rotation(model,"hand"+side,Quaternion(forward,PI)*Quaternion(fingers.normalized(),forward))

# Preserve the body, equipment, animation state and skeleton while changing hair.
func switch_hair(model:Node3D)->void:
	var choice:int=int(model.appearance.get("part_ids",{}).get("FrontHair1",1))
	for mesh in model.gear.Hair:mesh.visible=false
	if hair_cache.has(choice):
		hair_motion=hair_cache[choice]
	else:
		hair_motion=preload("res://scripts/char/character_hair_3d.gd").new()
		hair_motion.install(model)
		hair_cache[choice]=hair_motion
	for name in ["HairSecondaryLeft","HairSecondaryRight","HairSecondaryBack"]:
		var index:int=model.skeleton.find_bone(name)
		if index>=0:model.skeleton.reset_bone_pose(index)
	hair_motion.angles.fill(Vector3.ZERO)
	hair_motion.velocities.fill(Vector3.ZERO)
	hair_motion.initialized_yaw=false
	if choice in hair_motion.OPTIONS:
		var color:Color=model._color(model.appearance,"hair",Color("efc2ad") if choice==13 else Color("968575") if choice==11 else (Color("302b30") if choice in [10,12,14] else (Color("eaca96") if model.body_type=="female" else Color("665044"))))
		for mesh in hair_motion.meshes:
			mesh.visible=true
			var tie:=str(mesh.name).ends_with("Tie")
			mesh.material_override.set_shader_parameter("hair_color",Color("211c21") if tie else color)
			mesh.material_override.set_shader_parameter("palette_colored",bool(model.appearance.get("hair_on",false)) and not tie)
	elif choice>0:
		for mesh in original_hair:
			mesh.visible=true
			_tint_mesh(model,mesh,"Hair")

func prepare_hair_choices(model:Node3D)->void:
	if hair_prepared:return
	var saved:Dictionary=model.appearance.duplicate(true)
	for id in preload("res://scripts/char/character_hair_3d.gd").OPTIONS:
		if not model.appearance.has("part_ids"):model.appearance.part_ids={}
		model.appearance.part_ids.FrontHair1=id
		switch_hair(model)
	model.appearance=saved
	switch_hair(model)
	hair_prepared=true

# All non-structural appearance edits share the same incremental update path.
func update_appearance(model:Node3D,previous:Dictionary)->void:
	var current:Dictionary=model.appearance
	if _changed(previous,current,["hair_on","hair_row"]) or previous.get("part_ids",{}).get("FrontHair1")!=current.get("part_ids",{}).get("FrontHair1"):
		switch_hair(model)
	if _changed(previous,current,["bust_size"]):update_bust(Customization.valid_bust_size(current.get("bust_size",.5)))
	var skin_changed:=_changed(previous,current,["skin_on","skin_row"])
	var eyes_changed:=_changed(previous,current,["eye_color"])
	if skin_changed or eyes_changed:
		for mesh in model.gear.Body:
			if skin_changed or mesh.name=="Face":_tint_mesh(model,mesh,"Body")
	if skin_changed:
		for mesh in model.gear.Boots:
			if mesh.name=="MaidStockings" and mesh.material_override is ShaderMaterial:
				mesh.material_override.set_shader_parameter("skin_color",model._color(current,"skin",Color("ffeadb")))
	if _changed(previous,current,["cloth_on","cloth_row"]):
		for category in ["Clothing1","Clothing2"]:
			for mesh in model.gear[category]:
				if mesh.material_override==null:_tint_mesh(model,mesh,category)

static func _changed(before:Dictionary,after:Dictionary,keys:Array)->bool:
	for key in keys:
		if before.get(key)!=after.get(key):return true
	return false
