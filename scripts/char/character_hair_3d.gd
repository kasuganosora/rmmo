extends RefCounted
const OPTIONS:Dictionary={10:"短发（女士）",11:"短发（男士）",12:"公主切",13:"长发",14:"长发（束发）",15:"轻空气刘海波波头"}
static var packed:Dictionary={}
static var shared_shader:Shader
var meshes:Array=[]
var skeleton:Skeleton3D
var indices:Array[int]=[]
var angles:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
var velocities:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
var collision_probes:Array=[]
var body_capsules:Array=[]
var max_collision_offset:=.012
var collision_contacts:=0
var collision_frame:Node3D
var last_yaw:=0.0
var initialized_yaw:=false
const HAIR_SHADER:="""shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 hair_color : source_color = vec4(0.7,0.4,0.2,1.0);
uniform sampler2D source_texture : source_color, filter_linear_mipmap;
uniform bool textured = false;
uniform bool strand = true;
uniform bool soft_bob = false;
uniform bool soft_hime = false;
uniform bool soft_short = false;
uniform bool feather_short = false;
uniform bool loose_wave = false;
uniform bool palette_colored = false;
void fragment() {
    float tone = 0.83+0.17*max(0.0,dot(normalize(NORMAL),normalize(vec3(-0.3,0.6,1.0))));
    if (textured) tone *= mix(0.55,1.15,dot(texture(source_texture,UV).rgb,vec3(0.299,0.587,0.114)));
    else if (strand) tone *= 0.88+0.12*pow(max(0.0,sin(UV.x*3.14159)),0.6);
    if (soft_bob || soft_hime || soft_short || feather_short || loose_wave) {
        float phase=UV.x*37.0+sin(UV.y*5.0);
        float fibers=1.0+0.014*sin(phase)*clamp(1.0-fwidth(phase),0.0,1.0);
        float light=max(0.0,dot(normalize(NORMAL),normalize(vec3(-0.4,0.5,1.0))));
        tone=(0.72+0.28*light)*fibers;
        if (strand) tone*=0.96+0.04*sin(UV.x*3.14159);
        if (loose_wave) tone=0.82+0.18*light;

    }
    vec3 pigment=hair_color.rgb;
    if (soft_bob || soft_hime || soft_short || feather_short || loose_wave) {
        float depth=clamp(UV2.x,0.0,1.0);
        vec3 root=hair_color.rgb*0.68;
        vec3 middle=mix(hair_color.rgb,vec3(1.0),0.08);
        vec3 tip=hair_color.rgb*(soft_short ? vec3(0.72,0.69,0.68) : vec3(0.43,0.62,0.88));
        pigment=mix(root,middle,smoothstep(0.0,0.40,depth));
        pigment=mix(pigment,tip,smoothstep(0.46,0.98,depth));
        if (loose_wave) pigment=mix(hair_color.rgb*0.72,mix(hair_color.rgb,vec3(1.0,0.90,0.83),0.18),smoothstep(0.0,0.90,depth));
        if (feather_short) pigment=mix(hair_color.rgb*0.45,mix(hair_color.rgb,vec3(0.82,0.76,0.68),0.45),smoothstep(0.04,0.62,depth));
    }
    if (palette_colored) {
        // Preserve the selected hue; style-specific blue/peach dyes must not leak in.
        pigment=hair_color.rgb*mix(0.80,1.0,smoothstep(0.0,0.6,UV2.x));
    }
    // A directional satin reflection follows each curved lock. Keep the
    // base saturated: only the reflection mixes towards the light colour.
    vec3 n=normalize(NORMAL);
    if (!FRONT_FACING) n=-n;
    vec3 half_vector=normalize(normalize(vec3(-0.4,0.65,1.0))+normalize(VIEW));
    float alignment=max(0.0,dot(n,half_vector));
    float phase=UV.x*37.0+sin(UV.y*5.0);
    float fiber_glint=1.0+0.12*sin(phase)*clamp(1.0-fwidth(phase),0.0,1.0);
    float reflection=(0.14*pow(alignment,12.0)+0.20*pow(alignment,48.0))*fiber_glint;
    // Broad hair highlight, broken up by locks rather than a uniform grey veil.
    float band_center=0.28+0.035*sin(UV.x*3.14159);
    float band=exp(-pow((UV2.x-band_center)/0.085,2.0));
    reflection+=0.19*band*fiber_glint*(0.55+0.45*alignment);
    float lock_edge=strand ? mix(0.55,1.0,sin(clamp(UV.x,0.0,1.0)*3.14159)) : 1.0;
    vec3 sheen_color=mix(hair_color.rgb,vec3(1.0,0.97,0.94),0.72);
    bool styled=soft_bob || soft_hime || soft_short || feather_short || loose_wave;
    ALBEDO=pigment*tone+(styled ? sheen_color*reflection*lock_edge : vec3(0.0));
}
"""
func install(model:Node3D)->void:
	var choice:int=int(model.appearance.get("part_ids",{}).get("FrontHair1",1))
	if not OPTIONS.has(choice):return
	max_collision_offset=.035 if choice in [12,13,14] else .012
	var path:String=preload("res://scripts/util/json_util.gd").content_root()+"/assets/characters/hair/"+model.body_type+"/hair_%d.scn"%choice
	if not FileAccess.file_exists(path):
		push_error("Missing external hairstyle: "+path+"; run tools/bake_hair_runtime.gd")
		return
	if not packed.has(path):
		var resource=ResourceLoader.load(path,"PackedScene")
		if resource==null:return
		packed[path]=resource
	var source:Node3D=packed[path].instantiate();model.rig.add_child(source)
	var source_skeleton:Skeleton3D=source.find_children("*","Skeleton3D",true,false)[0]
	skeleton=model.skeleton
	for side in ["Left","Right","Back"]:
		var name:String="HairSecondary"+side
		var index:=skeleton.find_bone(name)
		if index<0:
			index=skeleton.get_bone_count();skeleton.add_bone(name)
			skeleton.set_bone_parent(index,skeleton.find_bone("mixamorig_Head"))
			skeleton.set_bone_rest(index,source_skeleton.get_bone_rest(source_skeleton.find_bone(name)))
		skeleton.reset_bone_pose(index);indices.append(index)
	for old in model.gear.Hair:old.visible=false
	var color:Color=model._color(model.appearance,"hair",Color("efc2ad") if choice==13 else Color("968575") if choice==11 else (Color("302b30") if choice in [10,12,14] else (Color("eaca96") if model.body_type=="female" else Color("665044"))))
	for mesh:MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		if not str(mesh.name).begins_with("Hair_"+str(choice)+"_"):continue
		var transform:Transform3D=model.rig.global_transform.affine_inverse()*mesh.global_transform
		var skin:=Skin.new()
		for binding in range(mesh.skin.get_bind_count()):
			var name:String=mesh.skin.get_bind_name(binding)
			if name.is_empty():name=source_skeleton.get_bone_name(mesh.skin.get_bind_bone(binding))
			skin.add_named_bind(name,mesh.skin.get_bind_pose(binding))
		mesh.reparent(model.rig,false);mesh.transform=transform;mesh.skin=skin;mesh.skeleton=mesh.get_path_to(skeleton)
		var original:StandardMaterial3D=mesh.get_active_material(0)
		if shared_shader==null:
			shared_shader=Shader.new();shared_shader.code=HAIR_SHADER
		var material:=ShaderMaterial.new();material.shader=shared_shader
		material.set_shader_parameter("hair_color",Color("211c21") if str(mesh.name).ends_with("Tie") else color)
		var texture:Texture2D=original.albedo_texture if original.albedo_texture!=null else original.emission_texture
		material.set_shader_parameter("textured",texture!=null)
		if texture!=null:material.set_shader_parameter("source_texture",texture)
		material.set_shader_parameter("strand",not str(mesh.name).ends_with("Scalp"))
		material.set_shader_parameter("soft_bob",choice==15)
		material.set_shader_parameter("soft_hime",choice in [12,14] and not str(mesh.name).ends_with("Tie"))
		material.set_shader_parameter("soft_short",choice==10)
		material.set_shader_parameter("feather_short",choice==11)
		material.set_shader_parameter("loose_wave",choice==13)
		material.set_shader_parameter("palette_colored",bool(model.appearance.get("hair_on",false)) and not str(mesh.name).ends_with("Tie"))
		mesh.material_override=material;model.gear.Hair.append(mesh);meshes.append(mesh)
		_cache_collision_probes(mesh)
	source.free()
	if collision_probes.size()>72:
		var sampled:Array=[]
		for i in range(72):sampled.append(collision_probes[int(i*float(collision_probes.size())/72)])
		collision_probes=sampled
	_install_capsules(model)
func update(model:Node3D,delta:float)->void:
	if indices.is_empty() or delta<=0:return
	var yaw:float=model.rig.rotation.y
	if not initialized_yaw:last_yaw=yaw;initialized_yaw=true
	var turn:float=clampf(wrapf(yaw-last_yaw,-PI,PI)/maxf(delta,.001),-8,8);last_yaw=yaw
	var moving:bool=model.action in ["walk","dash"]
	var phase:float=model.elapsed/maxf(.01,model.action_duration())*TAU
	for side in range(3):
		var target:=Vector3.ZERO
		if moving:target=Vector3(sin(phase*2-side*.2)*(.09 if model.action=="dash" else .045),sin(phase-side*.4)*.045,cos(phase+side*.5)*.025)
		target.y-=turn*.025
		var index:int=indices[side]
		# Map south is +Z. Transform wind into the animated hair bone's frame,
		# so turning the character never changes the world's wind direction.
		var global_basis:Basis=skeleton.global_basis*skeleton.get_bone_global_pose(index).basis
		var world_wind:=Vector3(model.environment_wind.x,0,model.environment_wind.y)
		var local_bend:Vector3=global_basis.orthonormalized().inverse()*(Vector3.DOWN.cross(world_wind))
		target+=local_bend*.30

		var left:=minf(delta,.1)
		while left>0:
			var step:=minf(left,1.0/120);left-=step
			velocities[side]+=((target-angles[side])*100-velocities[side]*7)*step
			angles[side]+=velocities[side]*step
		skeleton.set_bone_pose_rotation(index,skeleton.get_bone_rest(index).basis.get_rotation_quaternion()*Quaternion.from_euler(angles[side]))

	_solve_body_collisions()

# Analytic capsule contacts are evaluated after skinning/animation. A physics
# body's existence alone would not constrain skinned hair vertices.
func _cache_collision_probes(mesh:MeshInstance3D)->void:
	var arrays:=mesh.mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var bone_ids:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	var stride:=weights.size()/vertices.size()
	for vertex in range(0,vertices.size(),maxi(1,vertices.size()/16)):
		var binds:Array=[];var side:=-1;var dominant:=0.0
		for slot in range(stride):
			var weight:=weights[vertex*stride+slot]
			if weight<.001:continue
			var binding:=bone_ids[vertex*stride+slot]
			var bone:=skeleton.find_bone(mesh.skin.get_bind_name(binding))
			binds.append([bone,mesh.skin.get_bind_pose(binding)*vertices[vertex],weight])
			if bone in indices and weight>dominant:side=indices.find(bone);dominant=weight
		if side>=0 and dominant>.15:collision_probes.append({"binds":binds,"side":side,"weight":dominant})

func _install_capsules(model:Node3D)->void:
	collision_frame=model.rig
	var lift:=.065 if model.body_type=="male" else 0.0
	# Model units before the common 0.8 render scale, including garment clearance.
	for spec in [["mixamorig_Spine2",Vector3(0,1.56,-.015),Vector3(0,1.85,-.015),.16],
		["mixamorig_LeftArm",Vector3(.12,1.88,0),Vector3(.25,1.85,0),.085],
		["mixamorig_RightArm",Vector3(-.12,1.88,0),Vector3(-.25,1.85,0),.085],
		["mixamorig_Head",Vector3(0,2.14,0),Vector3(0,2.24,0),.125]]:
		var bone:=skeleton.find_bone(spec[0])
		if bone<0:continue
		var to_bone:Transform3D=(skeleton.global_transform*skeleton.get_bone_global_rest(bone)).affine_inverse()*model.rig.global_transform
		body_capsules.append({"bone":bone,"a":to_bone*(spec[1]+Vector3(0,lift,0)),"b":to_bone*(spec[2]+Vector3(0,lift,0)),"radius":float(spec[3])*.8})

func _probe_position(probe:Dictionary)->Vector3:
	var point:=Vector3.ZERO
	for bind in probe.binds:point+=(skeleton.get_bone_global_pose(bind[0])*bind[1])*float(bind[2])
	return skeleton.global_transform*point

static func capsule_push(point:Vector3,a:Vector3,b:Vector3,radius:float)->Vector3:
	var axis:=b-a
	var closest:=a+axis*clampf((point-a).dot(axis)/maxf(axis.length_squared(),.000001),0,1)
	var offset:=point-closest
	var distance:=offset.length()
	if distance>=radius:return Vector3.ZERO
	return (offset/distance if distance>.00001 else Vector3.BACK)*(radius-distance+.001)

func _solve_body_collisions()->void:
	collision_contacts=0
	var corrections:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
	# Blended action snapshots may contain the previous contact correction.
	# Never feed that displacement back into this frame's collision solver.
	for bone in indices:skeleton.set_bone_pose_position(bone,skeleton.get_bone_rest(bone).origin)
	for iteration in range(12):
		var pushes:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
		for probe:Dictionary in collision_probes:
			var point:=_probe_position(probe)
			for capsule:Dictionary in body_capsules:
				var transform:=skeleton.global_transform*skeleton.get_bone_global_pose(capsule.bone)
				var push:=capsule_push(point,transform*capsule.a,transform*capsule.b,capsule.radius)
				if push.length_squared()>.0000001:
					collision_contacts+=1
					# A coherent outward direction prevents neighbouring probes
					# from alternating between opposite exits of one capsule.
					var direction:Vector3=(collision_frame.global_basis*[Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD][probe.side]).normalized()
					var a:Vector3=transform*capsule.a;var b:Vector3=transform*capsule.b
					var axis:=b-a
					var closest:=a+axis*clampf((point-a).dot(axis)/maxf(axis.length_squared(),.000001),0,1)
					var offset:=point-closest;var along:=offset.dot(direction)
					var distance:float=-along+sqrt(maxf(0,along*along+capsule.radius*capsule.radius-offset.length_squared()))+.001
					push=direction*distance/float(probe.weight)
					if push.length_squared()>pushes[probe.side].length_squared():pushes[probe.side]=push
		if pushes.all(func(v):return v.length_squared()<.0000001):break
		var moved:=false
		for side in range(3):
			if pushes[side].length_squared()<.0000001:continue
			var bone:int=indices[side]
			var parent:=skeleton.get_bone_parent(bone)
			var basis:Basis=(skeleton.global_transform*skeleton.get_bone_global_pose(parent)).basis
			var correction:Vector3=(corrections[side]+pushes[side]).limit_length(max_collision_offset)
			if correction.distance_squared_to(corrections[side])<.00000001:continue
			moved=true;corrections[side]=correction
			skeleton.set_bone_pose_position(bone,skeleton.get_bone_rest(bone).origin+basis.inverse()*correction)
			# Contact dissipates motion instead of adding spring energy.
			velocities[side]*=.75
		if not moved:break
