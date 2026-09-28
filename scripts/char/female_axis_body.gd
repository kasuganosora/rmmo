extends Node3D
## Reference body solver: original axis weights, ordered rotations and joint bulges.
## Base topology remains the future garment anchor; subdivision is display-only.
const Art=preload("res://scripts/asset/art_paths.gd")
const RegionalSkin=preload("res://scripts/char/character_regional_skin.gd")
const Shapes=preload("res://scripts/char/character_body_shapes.gd")
const ORDERS=["XYZ","XZY","YXZ","YZX","ZXY","ZYX"]
const EULER_ORDERS=[EULER_ORDER_XYZ,EULER_ORDER_XZY,EULER_ORDER_YXZ,EULER_ORDER_YZX,EULER_ORDER_ZXY,EULER_ORDER_ZYX]
## Emitted only after the body textures and joint snapshot agree. Consumers must
## use the snapshot: Godot restores pre-modifier bone poses after skeleton_updated.
signal surface_updated
var solved_bones:Array[Transform3D]=[]
var pose_sync_error:=""
var _solving:=false
const POSES={
	"rest":{},
	"stand":{"rShldr":Vector3(0,0,-75),"lShldr":Vector3(0,0,75)},
	"elbow":{"rShldr":Vector3(0,0,-65),"lShldr":Vector3(0,0,65),"rForeArm":Vector3(0,-85,0),"lForeArm":Vector3(0,85,0)},
	"reach":{"rShldr":Vector3(0,0,55),"lShldr":Vector3(0,0,-55)},
	"step":{"rShldr":Vector3(0,0,-75),"lShldr":Vector3(0,0,75),"lThigh":Vector3(-65,0,0),"lShin":Vector3(90,0,0)},
	"sit":{"rShldr":Vector3(0,0,-75),"lShldr":Vector3(0,0,75),"lThigh":Vector3(-90,0,0),"rThigh":Vector3(-90,0,0),"lShin":Vector3(90,0,0),"rShin":Vector3(90,0,0)},
	# Preserve the original lie pose as a collision regression input.
	"lie":{"hip":Vector3(-90,0,0),"rShldr":Vector3(0,0,-75),"lShldr":Vector3(0,0,75)},
	"lie_relaxed":{"hip":Vector3(-90,0,0),"neck":Vector3(-9,0,0),"head":Vector3(9,5,0),
		"rShldr":Vector3(0,10,-70),"lShldr":Vector3(0,-10,70),
		# Supinated forearms let the backs of the hands rest on the support
		# surface. Keep the shoulders/elbows in place; don't splay the arms.
		"rForeArm":Vector3(-75,12,0),"lForeArm":Vector3(-75,-12,0),
		"rHand":Vector3(0,0,3),"lHand":Vector3(0,0,-3),
		"rIndex1":Vector3(0,0,-12),"rMid1":Vector3(0,0,-16),"rRing1":Vector3(0,0,-20),"rPinky1":Vector3(0,0,-24),
		"lIndex1":Vector3(0,0,12),"lMid1":Vector3(0,0,16),"lRing1":Vector3(0,0,20),"lPinky1":Vector3(0,0,24),
		"rIndex2":Vector3(0,0,-16),"rMid2":Vector3(0,0,-22),"rRing2":Vector3(0,0,-25),"rPinky2":Vector3(0,0,-28),
		"lIndex2":Vector3(0,0,16),"lMid2":Vector3(0,0,22),"lRing2":Vector3(0,0,25),"lPinky2":Vector3(0,0,28),
		"rIndex3":Vector3(0,0,-8),"rMid3":Vector3(0,0,-10),"rRing3":Vector3(0,0,-12),"rPinky3":Vector3(0,0,-14),
		"lIndex3":Vector3(0,0,8),"lMid3":Vector3(0,0,10),"lRing3":Vector3(0,0,12),"lPinky3":Vector3(0,0,14),
		"rThumb2":Vector3(0,8,8),"lThumb2":Vector3(0,-8,-8),
		"rThumb3":Vector3(0,0,8),"lThumb3":Vector3(0,0,-8)}}
const VERTEX_CODE="""
uniform sampler2D body_positions : filter_nearest;
uniform sampler2D body_normals : filter_nearest;
uniform sampler2D subdivision_weights : filter_nearest;
vec4 linear_fetch(sampler2D map, int index) {
    int width=textureSize(map,0).x;
    return texelFetch(map,ivec2(index%width,index/width),0);
}
void vertex() {
    vec3 point=vec3(0.0);vec3 normal=vec3(0.0);
    int start=int(UV2.x);int count=int(UV2.y);
    for(int j=0;j<count;j++) {
        vec2 entry=linear_fetch(subdivision_weights,start+j).xy;
        point+=linear_fetch(body_positions,int(entry.x)).xyz*entry.y;
        normal+=linear_fetch(body_normals,int(entry.x)).xyz*entry.y;
    }
    VERTEX=point;NORMAL=normalize(normal);
}
"""
var skeleton:Skeleton3D
var rest_points:=PackedVector3Array()
var base_rest_points:=PackedVector3Array()
var expression_values:Dictionary={}
const Expressions=preload("res://scripts/char/character_expressions.gd")
var shape_values:Dictionary={}
var posed_points:=PackedVector3Array()
var nodes:Array=[]
var topology:Dictionary
var rests:Dictionary={}
var base_rests:Dictionary={}
var positions_texture:ImageTexture
var normals_texture:ImageTexture
var pose_name:="rest"
var last_solve_ms:=0.0
var bulge_scale:=0.0
var root_offset:=Vector3.ZERO
var angles_by_name:Dictionary={}
var world_offset:=Vector3.ZERO
var mesh_instance:MeshInstance3D
var gpu:RefCounted
var use_compute:=false
func enable_compute()->bool:
	if gpu==null:
		gpu=preload("res://scripts/char/female_axis_gpu.gd").new()
		if not gpu.initialize(Art.path("characters/base/female_base_v2")):gpu=null;return false
		if not gpu.set_rest_points(rest_points):gpu.close();gpu=null;return false
	use_compute=true;return true
func _exit_tree()->void:
	if gpu:gpu.close();gpu=null
func read_gpu_points()->PackedVector3Array:
	var values:PackedFloat32Array=gpu.last_positions.to_float32_array();var result:=PackedVector3Array();result.resize(rest_points.size())
	for i in result.size():result[i]=Vector3(values[i*4],values[i*4+1],values[i*4+2])-root_offset
	return result
func set_test_pose(value:String,amount:float=1.0)->void:
	assert(POSES.has(value))
	pose_name=value
	var pose:Dictionary={}
	for bone:String in POSES[value]:pose[bone]=POSES[value][bone]*clampf(amount,0.0,1.0)
	set_angles(pose)
	var points:PackedVector3Array=read_gpu_points() if use_compute else posed_points
	posed_points=points
	var bottom:=INF
	for point:Vector3 in points:bottom=minf(bottom,point.y)
	world_offset=Vector3(0,-bottom,0)
	position=world_offset

static func vector(value:Dictionary)->Vector3:return Vector3(value.x,value.y,value.z)
static func frame(rows:Array)->Transform3D:
	return Transform3D(Basis(Vector3(rows[0][0],rows[1][0],rows[2][0]),Vector3(rows[0][1],rows[1][1],rows[2][1]),Vector3(rows[0][2],rows[1][2],rows[2][2])),Vector3(rows[0][3],rows[1][3],rows[2][3]))
static func ordered_basis(angles:Vector3,order:String)->Basis:
	var result:=Basis.IDENTITY
	for axis:String in order:
		var index:int="XYZ".find(axis)
		var direction:=Vector3.ZERO;direction[index]=1.0
		result=result*Basis(direction,angles[index])
	return result
func initialize()->void:
	assert(is_inside_tree(),"Body must belong to the scene before creating per-instance GPU resources")
	var folder:String=Art.path("characters/base/female_base_v2")
	var rig:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/female_axis_rig.json"))
	topology=JSON.parse_string(FileAccess.get_file_as_string(folder+"/female_display_topology.json"))
	assert(rig.version==1 and rig.vertex_count==21556 and rig.nodes.size()==80 and topology.points.size()==21556)
	bulge_scale=rig.bulge_scale
	for p:Array in topology.points:rest_points.append(Vector3(p[0],p[1],p[2]))
	base_rest_points=rest_points.duplicate()
	skeleton=Skeleton3D.new();skeleton.name="SharedBodySkeleton";add_child(skeleton)
	for data:Dictionary in rig.nodes:
		rests[data.name]=frame(data.rest)
		nodes.append(data)
	base_rests=rests.duplicate()
	var pending:Array=nodes.duplicate()
	while not pending.is_empty():
		var added:=false
		for i in range(pending.size()-1,-1,-1):
			var node:Dictionary=pending[i];var parent:int=skeleton.find_bone(node.parent) if not node.parent.is_empty() else -1
			if not node.parent.is_empty() and parent<0:continue
			skeleton.add_bone(node.name);var index:=skeleton.find_bone(node.name)
			if parent>=0:skeleton.set_bone_parent(index,parent)
			var local:Transform3D=rests[node.parent].affine_inverse()*rests[node.name] if parent>=0 else rests[node.name]
			skeleton.set_bone_rest(index,local);skeleton.set_bone_pose_position(index,local.origin);skeleton.set_bone_pose_rotation(index,local.basis.get_rotation_quaternion())
			pending.remove_at(i);added=true
		assert(added,"Cyclic or missing source parent")
	for node:Dictionary in nodes:
		node["rest_frame"]=rests[node.name];node["inverse_frame"]=rests[node.name].affine_inverse()
		node["skeleton_index"]=skeleton.find_bone(node.name)
		for w:Dictionary in node.weights:
			w["axis_weights"]=Vector3(w.xweight,w.yweight,w.zweight)
			w["left"]=Vector3(w.xleftbulge,w.yleftbulge,w.zleftbulge)
			w["right"]=Vector3(w.xrightbulge,w.yrightbulge,w.zrightbulge)
	positions_texture=ImageTexture.create_from_image(Image.create(512,43,false,Image.FORMAT_RGBAF))
	normals_texture=ImageTexture.create_from_image(Image.create(512,43,false,Image.FORMAT_RGBAF))
	var size:Array=topology.stencil_size
	var stencil:=ImageTexture.create_from_image(Image.create_from_data(size[0],size[1],false,Image.FORMAT_RGBAF,FileAccess.get_file_as_bytes(folder+"/subdivision_stencils.rgba32f")))
	var screen_space_sss:bool=not (is_inside_tree() and get_viewport().transparent_bg)
	var source:=RegionalSkin.create_preview(screen_space_sss);assert(source!=null)
	set_meta("screen_space_sss",screen_space_sss)
	var materials:Dictionary={}
	for mesh:MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():materials[mesh.mesh.surface_get_material(surface).resource_name]=mesh.get_surface_override_material(surface)
	var array_mesh:=ArrayMesh.new()
	for surface in topology.surfaces.size():
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for quad:Array in topology.surfaces[surface]:
			for corner in [0,1,2,0,2,3]:
				var vertex:int=quad[0][corner];var p:Array=topology.display_points[vertex];var uv:Array=quad[1][corner];var span:Array=topology.ranges[vertex]
				st.set_uv(Vector2(uv[0],1.0-uv[1]));st.set_uv2(Vector2(span[0],span[1]));st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(p[0],p[1],p[2]))
		st.index();st.generate_tangents();st.commit(array_mesh)
		var original:Material=materials[topology.materials[surface]]
		var material:=ShaderMaterial.new();var shader:=Shader.new()
		material.resource_name=original.resource_name
		material.render_priority=original.render_priority
		for key:StringName in original.get_meta_list():material.set_meta(key,original.get_meta(key))
		if original is ShaderMaterial:
			# Reconstruct tangent frame from deformed surface derivatives; rest-pose
			# tangents must not rotate the skin detail incorrectly at bent joints.
			shader.code=original.shader.code.replace("NORMAL_MAP = texture(normal_map, UV).rgb;\n\tNORMAL_MAP_DEPTH = 0.35;", """
	vec3 mapped=texture(normal_map,UV).rgb*2.0-1.0;mapped.xy*=0.35;
	vec3 dp1=dFdx(VERTEX),dp2=dFdy(VERTEX);vec2 uv1=dFdx(UV),uv2=dFdy(UV);
	vec3 perpendicular2=cross(dp2,NORMAL),perpendicular1=cross(NORMAL,dp1);
	vec3 tangent=perpendicular2*uv1.x+perpendicular1*uv2.x;
	vec3 bitangent=perpendicular2*uv1.y+perpendicular1*uv2.y;
	float inverse_scale=inversesqrt(max(max(dot(tangent,tangent),dot(bitangent,bitangent)),0.000000000001));
	NORMAL=normalize(tangent*inverse_scale*mapped.x+bitangent*inverse_scale*mapped.y+NORMAL*mapped.z);
""")+VERTEX_CODE
			material.shader=shader
			# Preserve each surface's shader and parameters. Replacing every shader
			# with the skin program silently broke eye and other regional materials.
			for uniform:Dictionary in original.shader.get_shader_uniform_list():
				material.set_shader_parameter(uniform.name,original.get_shader_parameter(uniform.name))
		else:
			var color:Color=original.albedo_color
			shader.code="shader_type spatial;\n"+VERTEX_CODE+"void fragment(){ALBEDO=vec3(%s,%s,%s);ROUGHNESS=0.45;%s}"%[color.r,color.g,color.b,"ALPHA=0.0;" if color.a==0 else ""]
			material.shader=shader
		material.set_shader_parameter("body_positions",positions_texture);material.set_shader_parameter("body_normals",normals_texture);material.set_shader_parameter("subdivision_weights",stencil)
		array_mesh.surface_set_material(surface,material)
	set_meta("skin_id",source.get_meta("skin_id",""));set_meta("eye_id",source.get_meta("eye_id",""))
	source.free()
	mesh_instance=MeshInstance3D.new();mesh_instance.mesh=array_mesh;mesh_instance.custom_aabb=AABB(Vector3(-2,-1,-2),Vector3(4,4,4));add_child(mesh_instance)
	set_angles({})
	skeleton.skeleton_updated.connect(_on_skeleton_updated)

func get_solved_bone_pose(index:int)->Transform3D:
	return solved_bones[index]

func set_colors(recipe:Dictionary)->void:
	RegionalSkin.apply_colors(self,recipe)

func _on_skeleton_updated()->void:
	if not _solving:sync_final_pose()

static func continuous_angles(rotation:Basis,order:int,previous:Vector3)->Vector3:
	# Equivalent Euler triples do not produce equivalent partial-axis skinning.
	# Keep the branch nearest the last solved joint, including crossing +/- PI.
	if ordered_basis(previous,ORDERS[order]).is_equal_approx(rotation):return previous
	var primary:=rotation.get_euler(EULER_ORDERS[order])
	var alternate:=primary
	for i in 3:
		var axis:int="XYZ".find(ORDERS[order][i])
		alternate[axis]=PI-primary[axis] if i==1 else primary[axis]+PI
	var candidates:Array[Vector3]=[primary,alternate]
	var first:int="XYZ".find(ORDERS[order][0])
	var middle:int="XYZ".find(ORDERS[order][1])
	var last:int="XYZ".find(ORDERS[order][2])
	if absf(cos(primary[middle]))<.00001:
		# At gimbal lock there is a continuum of equivalent first/last angles.
		# Project toward the previous pair instead of snapping one axis to zero.
		for sign_value:float in [-1.0,1.0]:
			var candidate:=primary
			var shift:float=(wrapf(previous[first]-primary[first],-PI,PI)+sign_value*wrapf(previous[last]-primary[last],-PI,PI))*.5
			candidate[first]+=shift;candidate[last]+=sign_value*shift
			candidates.append(candidate)
	var best:=primary;var distance:=INF
	for candidate:Vector3 in candidates:
		for axis in 3:candidate[axis]=previous[axis]+wrapf(candidate[axis]-previous[axis],-PI,PI)
		if not ordered_basis(candidate,ORDERS[order]).is_equal_approx(rotation):continue
		var score:=candidate.distance_squared_to(previous)
		if score<distance:distance=score;best=candidate
	return best

func sync_final_pose(angle_references:Dictionary={})->bool:
	# Read while Skeleton3D exposes the final modifier result, without writing it
	# back into the animation input. Axis weights need final local Euler angles
	# as well as global joint matrices; updating only one produces split limbs.
	var next_bones:Array[Transform3D]=[]
	var next_angles:Array[Vector3]=[]
	var changed:=solved_bones.size()!=skeleton.get_bone_count()
	for index in skeleton.get_bone_count():
		var local:=skeleton.get_bone_pose(index)
		var rest:=skeleton.get_bone_rest(index)
		# Shape-driven joint translations/scales require adapted bind data. Reject
		# them atomically until that path exists instead of applying them only to
		# fully weighted vertices while leaving partial weights behind.
		if not local.origin.is_equal_approx(rest.origin) or not local.basis.get_scale().is_equal_approx(Vector3.ONE):
			pose_sync_error="Unsupported joint translation/scale: "+skeleton.get_bone_name(index)
			return false
		var final_pose:=skeleton.get_bone_global_pose(index)
		next_bones.append(final_pose)
		if not changed and not final_pose.is_equal_approx(solved_bones[index]):changed=true
	for node:Dictionary in nodes:
		var index:int=node.skeleton_index
		var relative:Basis=skeleton.get_bone_rest(index).basis.inverse()*skeleton.get_bone_pose(index).basis
		var reference:Vector3=angle_references.get(node.name,node.angles)
		var angles:Vector3=continuous_angles(relative.orthonormalized(),node.order,reference)
		next_angles.append(angles)
		if not angles.is_equal_approx(node.angles):changed=true
	pose_sync_error=""
	if not changed:return true
	solved_bones=next_bones
	for i in nodes.size():nodes[i]["angles"]=next_angles[i]
	_solve_surface(root_offset)
	return true

func set_shape_values(values:Dictionary)->bool:
	for key in values:
		if not Shapes.RANGES.has(key):return false
	var normalized:=Shapes.normalize(values)
	if normalized==shape_values:return true
	var points:=Shapes.evaluate(base_rest_points,normalized)
	points=Expressions.evaluate(points,expression_values)
	if points.is_empty():return false
	var next_rests:=Shapes.evaluate_rests(base_rests,normalized)
	if next_rests.size()!=rests.size():return false
	if gpu!=null and not gpu.set_rest_points(points):return false
	rest_points=points;shape_values=normalized
	var degrees:Dictionary={}
	for node:Dictionary in nodes:degrees[node.name]=node.angles*180.0/PI
	rests=next_rests
	for node:Dictionary in nodes:
		node.rest_frame=rests[node.name];node.inverse_frame=rests[node.name].affine_inverse()
		var local:Transform3D=rests[node.parent].affine_inverse()*rests[node.name] if not node.parent.is_empty() else rests[node.name]
		skeleton.set_bone_rest(node.skeleton_index,local)
	# Original identity formulas move bind centers, not animated local poses.
	# Reapply the current angles on the new rests without changing clip/time.
	set_angles(degrees,root_offset)
	return true

func set_expressions(values:Dictionary)->bool:
	var normalized:=Expressions.normalize(values)
	if normalized.has("invalid"):return false
	if normalized==expression_values:return true
	var points:=Expressions.evaluate(Shapes.evaluate(base_rest_points,shape_values),normalized)
	if points.is_empty():return false
	if gpu!=null and not gpu.set_rest_points(points):return false
	var previous:Dictionary=Expressions.bone_offsets(expression_values)
	rest_points=points;expression_values=normalized
	for surface in topology.materials.size():
		var material:ShaderMaterial=mesh_instance.mesh.surface_get_material(surface)
		if topology.materials[surface] in ["Irises","Pupils"]:
			material.set_shader_parameter("expression_heart",float(normalized.get("heart_eyes",0)))
			material.set_shader_parameter("expression_star",float(normalized.get("star_eyes",0)))
			material.set_shader_parameter("expression_circle",float(normalized.get("circle_eyes",0)))
		elif topology.materials[surface]=="Face":material.set_shader_parameter("expression_blush",float(normalized.get("blush",0)))
	var references:=apply_expression_bones(previous)
	if not sync_final_pose(references):return false
	_solve_surface(root_offset)
	return true

func apply_expression_bones(previous:Dictionary={})->Dictionary:
	var offsets:=Expressions.bone_offsets(expression_values)
	var references:Dictionary={}
	for node:Dictionary in nodes:
		if not offsets.has(node.name) and not previous.has(node.name):continue
		var index:int=node.skeleton_index
		var rest:Transform3D=skeleton.get_bone_rest(index)
		var relative:Basis=rest.basis.inverse()*Basis(skeleton.get_bone_pose_rotation(index))
		var angles:=continuous_angles(relative,node.order,node.angles)
		angles+=offsets.get(node.name,Vector3.ZERO)-previous.get(node.name,Vector3.ZERO)
		skeleton.set_bone_pose_rotation(index,(rest.basis*ordered_basis(angles,ORDERS[node.order])).get_rotation_quaternion())
		references[node.name]=angles
	return references

func set_angles(degrees:Dictionary,offset:Vector3=Vector3.ZERO)->void:
	assert(offset.is_finite())
	for name:String in degrees:assert(rests.has(name) and degrees[name] is Vector3 and degrees[name].is_finite(),"Invalid source joint pose")
	root_offset=offset;angles_by_name=degrees.duplicate(true)
	for node:Dictionary in nodes:
		var angles:Vector3=degrees.get(node.name,Vector3.ZERO)*PI/180.0
		node["angles"]=angles
		var index:int=node.skeleton_index;var local:=skeleton.get_bone_rest(index)
		skeleton.set_bone_pose_rotation(index,(local.basis*ordered_basis(angles,ORDERS[node.order])).get_rotation_quaternion())
		skeleton.set_bone_pose_position(index,local.origin)
		skeleton.set_bone_pose_scale(index,Vector3.ONE)
	solved_bones.clear()
	for index in skeleton.get_bone_count():solved_bones.append(skeleton.get_bone_global_pose(index))
	pose_sync_error=""
	_solve_surface(offset)

func _solve_surface(offset:Vector3)->void:
	_solving=true
	var start:=Time.get_ticks_usec()
	if use_compute and gpu!=null:
		gpu.evaluate(nodes,solved_bones,bulge_scale,offset)
		positions_texture.update(Image.create_from_data(512,43,false,Image.FORMAT_RGBAF,gpu.last_positions))
		normals_texture.update(Image.create_from_data(512,43,false,Image.FORMAT_RGBAF,gpu.last_normals))
		last_solve_ms=(Time.get_ticks_usec()-start)/1000.0
		posed_points=read_gpu_points()
		_solving=false
		surface_updated.emit()
		return
	posed_points=rest_points.duplicate()
	for node:Dictionary in nodes:
		var angles:Vector3=node.angles
		var delta:Transform3D=solved_bones[node.skeleton_index]*node.inverse_frame
		var full_identity:=delta.is_equal_approx(Transform3D.IDENTITY)
		for w:Dictionary in node.weights:
			var id:int=w.vertex;var weight:Vector3=w.axis_weights
			if weight.x>.99999 and weight.y>.99999 and weight.z>.99999:
				if not full_identity:posed_points[id]=delta*posed_points[id]
			elif not angles.is_zero_approx():
				var p:Vector3=node.inverse_frame*posed_points[id]
				var order:String=ORDERS[node.order]
				for order_index in range(2,-1,-1):
					var axis:int="XYZ".find(order[order_index]);var direction:=Vector3.ZERO;direction[axis]=1.0
					p=Basis(direction,angles[axis]*weight[axis])*p
					if absf(angles[axis])>.01:
						var prefix:String="xyz"[axis]+("pos" if angles[axis]>0 else "neg")
						var scale:float=(1.0+node.bulge[prefix+"left"]*angles[axis]*bulge_scale*w.left[axis])*(1.0+node.bulge[prefix+"right"]*angles[axis]*bulge_scale*w.right[axis])
						for component in 3:
							if component!=axis:p[component]*=scale
				posed_points[id]=node.rest_frame*p
		if not full_identity:
			for id:int in node.full:posed_points[id]=delta*posed_points[id]
	var normals:=PackedVector3Array();normals.resize(rest_points.size())
	for face:Array in topology.base_faces:
		for i in range(1,face.size()-1):
			var a:int=face[0];var b:int=face[i];var c:int=face[i+1]
			var normal:Vector3=-(posed_points[b]-posed_points[a]).cross(posed_points[c]-posed_points[a])
			normals[a]+=normal;normals[b]+=normal;normals[c]+=normal
	var position_data:=PackedFloat32Array();var normal_data:=PackedFloat32Array();position_data.resize(512*43*4);normal_data.resize(512*43*4)
	for i in posed_points.size():
		var p:Vector3=posed_points[i]+offset;var normal:Vector3=normals[i].normalized()
		for axis in 3:position_data[i*4+axis]=p[axis];normal_data[i*4+axis]=normal[axis]
	positions_texture.update(Image.create_from_data(512,43,false,Image.FORMAT_RGBAF,position_data.to_byte_array()))
	normals_texture.update(Image.create_from_data(512,43,false,Image.FORMAT_RGBAF,normal_data.to_byte_array()))
	last_solve_ms=(Time.get_ticks_usec()-start)/1000.0
	_solving=false
	surface_updated.emit()
