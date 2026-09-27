extends RefCounted
## Shared garment support volumes, derived from this body's bind mesh/bones.
## The vertex pass runs on the skinned mesh and never removes body geometry.
const VERTEX_FIT="""
uniform mat4 cloth_to_body;
uniform mat4 body_to_cloth;
uniform vec3 pelvis_center;
uniform vec3 pelvis_size;
uniform mat4 pelvis_frame;
uniform mat4 inverse_pelvis_frame;
uniform vec3 leg_top[2];
uniform vec3 leg_end[2];
uniform float leg_radius = 0.0;
uniform vec3 cloth_sway = vec3(0.0);
vec3 outside_leg(vec3 p, vec3 a, vec3 b, float radius, float front_panel) {
    vec3 axis = b-a;
    float t = clamp(dot(p-a,axis)/max(dot(axis,axis),0.000001),0.0,1.0);
    vec3 nearest = a+axis*t;
    vec3 offset = p-nearest;
    float distance = length(offset);
    float r = radius*mix(1.0,0.72,t);
    if (distance<r && distance>0.00001) p=nearest+offset*(r/distance);
    // The front panel stays on the front/up side of a raised thigh.
    // A radial closest-point push can otherwise choose the underside and
    // allow an entire triangle to cross a seated leg between its vertices.
    vec3 right = normalize((pelvis_frame*vec4(1.0,0.0,0.0,0.0)).xyz);
    vec3 front = cross(normalize(axis),right);
    if (front_panel>0.0 && length(front)>0.0001) {
        front=normalize(front);
        float lateral=abs(dot(p-nearest,right));
        float along=dot(p-a,axis)/max(dot(axis,axis),0.000001);
        if (along>=0.0 && along<=1.0 && lateral<r) {
            float surface=sqrt(max(0.0,r*r-lateral*lateral));
            p+=front*max(0.0,surface-dot(p-nearest,front))*front_panel;
        }
    }
    return p;
}
void vertex() {
    if (leg_radius > 0.0) {
        vec3 p=(cloth_to_body*vec4(VERTEX,1.0)).xyz;
        float mobility = COLOR.a;
        p += cloth_sway*mobility;
        // Nested layers need distinct support volumes. A normal offset alone
        // can push folded apron vertices back through the supporting skirt.
        float layer_scale = 1.0 + COLOR.g * 0.12;
        vec3 support_size = pelvis_size * layer_scale;
        for (int pass=0; pass<2; pass++) {
            vec3 unit=((inverse_pelvis_frame*vec4(p,1.0)).xyz-pelvis_center)/support_size;
            float distance=pow(dot(unit*unit,unit*unit),0.25);
            if (distance<1.0 && distance>0.00001) p=(pelvis_frame*vec4(pelvis_center+unit/distance*support_size,1.0)).xyz;
            for (int i=0;i<2;i++) p=outside_leg(p,leg_top[i],leg_end[i],leg_radius*layer_scale, smoothstep(0.0,0.3,COLOR.b)*smoothstep(0.0,0.1,mobility));
        }
        VERTEX=(body_to_cloth*vec4(p,1.0)).xyz+NORMAL*COLOR.g*leg_radius*0.08;
    }
}
"""
var pelvis_offset:=Vector3.ZERO
var pelvis_size:=Vector3.ONE
var leg_radius:=0.0
var sway:=Vector3.ZERO
var velocity:=Vector3.ZERO
var previous_position:=Vector3.ZERO
var previous_speed:=Vector3.ZERO
var initialized:=false

func install(model:Node3D,rest:Dictionary)->void:
	var length:float=rest.thighL.distance_to(rest.shinL)
	var lo:=Vector3(INF,INF,INF);var hi:=-lo
	for mesh:MeshInstance3D in model.gear.Body:
		if mesh.name!="Body":continue
		for surface in mesh.mesh.get_surface_count():
			for p:Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if absf(p.y-rest.hips.y)<length*.22:lo=lo.min(p);hi=hi.max(p)
	if not lo.is_finite():return
	pelvis_offset=(lo+hi)*.5-rest.hips
	pelvis_size=(hi-lo)*.5+Vector3.ONE*length*.045
	pelvis_size.y=length*.45
	leg_radius=0.0
	# Fit the support capsule to this body's actual thigh cross sections.
	# A fraction of pelvis width underestimates fuller thighs and lets the
	# leg emerge through the apron during a forward step.
	for mesh:MeshInstance3D in model.gear.Body:
		if mesh.name!="Body":continue
		for surface in mesh.mesh.get_surface_count():
			for p:Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				for side in ["L","R"]:
					var top:Vector3=rest["thigh"+side];var end:Vector3=rest["shin"+side]
					if p.x*top.x<0:continue
					var axis:Vector3=end-top
					var t:float=(p-top).dot(axis)/axis.length_squared()
					if t<0.05 or t>0.95:continue
					var radius:float=p.distance_to(top+axis*t)/lerpf(1.0,.72,t)
					leg_radius=maxf(leg_radius,radius+length*.018)
	if leg_radius<=0:leg_radius=pelvis_size.x*.64

func update(model:Node3D,delta:float)->void:
	if leg_radius<=0:return
	var sk:Skeleton3D=model.skeleton
	var relative:Transform3D=model.rig.global_transform.affine_inverse()*sk.global_transform
	var hips:Transform3D=relative*sk.get_bone_global_pose(model.bones.hips)
	var hips_rest:Transform3D=relative*sk.get_bone_global_rest(model.bones.hips)
	var frame:Transform3D=hips*hips_rest.affine_inverse()
	var tops:=PackedVector3Array();var ends:=PackedVector3Array()
	for side in ["L","R"]:
		tops.append((relative*sk.get_bone_global_pose(model.bones["thigh"+side])).origin)
		ends.append((relative*sk.get_bone_global_pose(model.bones["shin"+side])).origin)
	var world:Vector3=model.global_position
	if delta>0:
		var dt:float=minf(delta,1.0/30)
		var speed:Vector3=(world-previous_position)/dt if initialized else Vector3.ZERO
		var acceleration:Vector3=(speed-previous_speed)/dt if initialized else Vector3.ZERO
		acceleration=model.global_basis.inverse()*acceleration
		var target:Vector3=(-acceleration*.002).limit_length(leg_radius*.25)
		# Alternating legs drive a small delayed hem response even when an
		# animation is previewed in place; the pinned bodice has zero mobility.
		target.x+=(ends[0].z-ends[1].z)*.045
		target=target.limit_length(leg_radius*.25)
		velocity+=(target-sway)*90*dt-velocity*14*dt
		sway=(sway+velocity*dt).limit_length(leg_radius*.3)
		previous_position=world;previous_speed=speed;initialized=true
	for category in ["Clothing1","Clothing2"]:
		for mesh:MeshInstance3D in model.gear[category]:
			if not mesh.visible or not mesh.get_meta("flexible_garment",false):continue
			var material:ShaderMaterial=mesh.material_override
			material.set_shader_parameter("cloth_to_body",mesh.transform)
			material.set_shader_parameter("body_to_cloth",mesh.transform.affine_inverse())
			material.set_shader_parameter("pelvis_center",hips_rest.origin+pelvis_offset)
			material.set_shader_parameter("pelvis_frame",frame)
			material.set_shader_parameter("inverse_pelvis_frame",frame.affine_inverse())
			material.set_shader_parameter("pelvis_size",pelvis_size)
			material.set_shader_parameter("leg_top",tops);material.set_shader_parameter("leg_end",ends)
			material.set_shader_parameter("leg_radius",leg_radius)
			material.set_shader_parameter("cloth_sway",sway)
