extends Node3D
## Experimental backend. Original render mesh, UVs and materials stay untouched;
## a hidden control mesh supplies topology/weights to the pinned PBD dependency.
const Solver=preload("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
const CONTACT_MARGIN:=.006
var garment:Node3D
var body:Node3D
var solver:Node3D
var controls:MeshInstance3D
var lookup:ImageTexture
var body_triangles:=PackedInt32Array()
var scene_triangles:=PackedVector3Array()
var control_to_particle:=PackedInt32Array()
var frame_error:=""
var last_submit_ms:=0.0
var last_simulate_ms:=0.0
static var default_shared_body_points:=false
static var default_resident_packet:=true
var indexed_packet=(preload("res://addons/godot_gpu_cloth/src/cloth_resident_packet.gd").new() if default_resident_packet else preload("res://addons/godot_gpu_cloth/src/cloth_indexed_packet.gd").new())
var edge_contacts:=false
var constraint_iterations:=24
var source_bending:=false
var interpolate_targets:=false
var self_edge_contacts:=false
var continuous_self_contacts:=false
var self_contact_mass_balance:=false
var self_contact_body_tangents:=false
var review_stage_trace:=false
var self_contact_iterations:=1
var self_contact_structural_projection:=false

func initialize(target:Node3D,objects:Array[MeshInstance3D]=[])->bool:
	assert(is_inside_tree())
	garment=target;body=target.body
	for face:Array in body.topology.base_faces:
		for i in range(1,face.size()-1):
			var a:Vector3=body.rest_points[face[0]];var b:Vector3=body.rest_points[face[i]];var c:Vector3=body.rest_points[face[i+1]]
			if (b-a).cross(c-a).length_squared()>1e-16:body_triangles.append_array(PackedInt32Array([face[0],face[i],face[i+1]]))
	# Scene geometry is sampled in the same frame as the body. Store references
	# below so a moved chair never silently keeps its old world-space collider.
	collision_objects=objects.duplicate()
	scene_triangles=_scene_points()
	var weights:=FileAccess.get_file_as_bytes(Art.path("characters/equipment/surface_bound/"+garment.garment_id+"/cloth_rest.bin")).to_float32_array()
	if weights.size()!=garment.rest_points.size()*4:return false
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=garment.rest_points.duplicate()
	var normals:=PackedVector3Array();normals.resize(garment.rest_points.size());normals.fill(Vector3.UP);arrays[Mesh.ARRAY_NORMAL]=normals
	var colors:=PackedColorArray()
	for i in garment.rest_points.size():colors.append(Color(1.0-weights[i*4+3],0,0,1))
	arrays[Mesh.ARRAY_COLOR]=colors
	var indices:=PackedInt32Array()
	for face:Dictionary in garment.data.faces:
		for i in range(1,face.vertices.size()-1):indices.append_array(PackedInt32Array([face.vertices[0],face.vertices[i],face.vertices[i+1]]))
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	controls=MeshInstance3D.new();controls.name="ControlMesh";controls.mesh=mesh;controls.visible=false;add_child(controls)
	solver=Solver.new();solver.name="Solver";solver.target_mesh=NodePath("../ControlMesh")
	if source_bending:
		var source_path:String=Art.path("characters/equipment/surface_bound/"+garment.garment_id+"/source_cloth_data.json")
		var source:Variant=JSON.parse_string(FileAccess.get_file_as_string(source_path))
		if not source is Dictionary or not source.get("physics") is Dictionary:
			frame_error="Missing authored cloth neighbor graph";solver.free();return false
		var physics:Dictionary=source.physics
		var to_control:Dictionary={}
		for face_index in garment.data.faces.size():
			var face:Dictionary=garment.data.faces[face_index]
			var uvs:Array=garment.data.uv_faces[face_index].vertices
			for corner in face.vertices.size():
				var uv:int=uvs[corner]
				if uv<0 or uv>=physics.mesh_to_physics.size():
					frame_error="Invalid authored UV/particle mapping";solver.free();return false
				var particle:int=physics.mesh_to_physics[uv];var control:int=face.vertices[corner]
				if to_control.has(particle) and garment.rest_points[to_control[particle]].distance_to(garment.rest_points[control])>.00001:
					frame_error="Authored particle maps to conflicting control positions";solver.free();return false
				to_control[particle]=control
		for group:Array in physics.bend_groups:
			for pair:Array in group:
				if not to_control.has(int(pair[0])) or not to_control.has(int(pair[1])):
					frame_error="Authored bend references an unmapped particle";solver.free();return false
				solver.external_bend_pairs.append_array(PackedInt32Array([to_control[int(pair[0])],to_control[int(pair[1])]]))
	solver.external_surface_input=true;solver.external_triangle_count=(body_triangles.size()+scene_triangles.size())/3
	solver.interpolate_external_targets=interpolate_targets
	solver.external_reverse_contacts=true
	solver.self_edge_contacts=self_edge_contacts
	solver.self_contact_mass_balance=self_contact_mass_balance
	solver.self_contact_body_tangents=self_contact_body_tangents
	solver.review_stage_trace=review_stage_trace
	solver.self_contact_structural_projection=self_contact_structural_projection
	solver.self_contact_iterations=self_contact_iterations
	solver.self_collide=continuous_self_contacts
	solver.continuous_self_contacts=continuous_self_contacts
	if continuous_self_contacts:solver.peer_collider_voxel_resolution=0
	var seen:Dictionary={}
	for i in body_triangles.size():
		if not seen.has(body_triangles[i]):
			seen[body_triangles[i]]=true;solver.external_collision_vertices.append(i)
	for i in scene_triangles.size():solver.external_collision_vertices.append(body_triangles.size()+i)
	var collider_points:=PackedVector3Array()
	for index in body_triangles:collider_points.append(body.rest_points[index])
	collider_points.append_array(scene_triangles)
	var centers:=PackedVector3Array()
	for i in range(0,collider_points.size(),3):centers.append((collider_points[i]+collider_points[i+1]+collider_points[i+2])/3)
	solver.external_collision_order=preload("res://addons/godot_gpu_cloth/src/cloth_spatial_order.gd").order(centers)
	var vertex_centers:=PackedVector3Array()
	for index in solver.external_collision_vertices:vertex_centers.append(collider_points[index])
	solver.external_collision_order.append_array(preload("res://addons/godot_gpu_cloth/src/cloth_spatial_order.gd").order(vertex_centers))
	var edge_set:Dictionary={}
	for i in range(0,body_triangles.size() if edge_contacts else 0,3):
		for side in 3:
			var a:int=body_triangles[i+side];var b:int=body_triangles[i+(side+1)%3]
			var key:=Vector2i(mini(a,b),maxi(a,b))
			if not edge_set.has(key):
				edge_set[key]=true;solver.external_collision_edges.append_array(PackedInt32Array([i+side,i+(side+1)%3]))
	for i in range(body_triangles.size(),body_triangles.size()+(scene_triangles.size() if edge_contacts else 0),3):
		for side in 3:solver.external_collision_edges.append_array(PackedInt32Array([i+side,i+(side+1)%3]))
	solver.weld_epsilon=.0000001;solver.substeps=4;solver.solver_iterations=constraint_iterations;solver.max_travel_distance=.8
	solver.body_collider_thickness=CONTACT_MARGIN
	add_child(solver);solver.set_process(false)
	control_to_particle=solver._original_to_welded.duplicate()
	if control_to_particle.size()!=garment.rest_points.size():return false
	var pixels:=PackedFloat32Array();var height:int=ceili(float(control_to_particle.size())/512);pixels.resize(512*height*4)
	for i in control_to_particle.size():pixels[i*4]=control_to_particle[i]
	lookup=ImageTexture.create_from_image(Image.create_from_data(512,height,false,Image.FORMAT_RGBAF,pixels.to_byte_array()))
	return submit_frame()

var collision_objects:Array[MeshInstance3D]=[]
func _scene_points()->PackedVector3Array:
	var result:=PackedVector3Array()
	for object:MeshInstance3D in collision_objects:
		if not is_instance_valid(object):return PackedVector3Array()
		var local:Transform3D=global_transform.affine_inverse()*object.global_transform
		for surface in object.mesh.get_surface_count():
			var arrays:Array=object.mesh.surface_get_arrays(surface)
			var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			if indices.is_empty():
				for point:Vector3 in points:result.append(local*point)
			else:
				for index in indices:result.append(local*points[index])
	return result

func submit_frame()->bool:
	var positions:PackedVector3Array=garment.evaluate(body.posed_points)
	var targets:=PackedVector3Array();targets.resize(solver._particle_count)
	var assigned:=PackedByteArray();assigned.resize(targets.size())
	for i in positions.size():
		var particle:int=control_to_particle[i];var point:Vector3=positions[i]+body.root_offset
		if assigned[particle] and targets[particle].distance_to(point)>.00001:
			frame_error="Welded seam has conflicting surface targets";return false
		targets[particle]=point;assigned[particle]=1
	var extras:=_scene_points()
	if indexed_packet.rd==null:
		if not indexed_packet.initialize(body_triangles,body.posed_points.size(),extras.size()):frame_error="Collider packet initialization failed";return false
	if indexed_packet.has_method("set_point_source"):indexed_packet.set_point_source(body.gpu_display if default_shared_body_points else null)
	if not solver.set_indexed_external_frame(targets,indexed_packet,body.posed_points,body.root_offset,extras):frame_error="Candidate rejected indexed collider packet";return false
	frame_error="";return true

func advance(delta:float)->bool:
	var start:=Time.get_ticks_usec()
	if not solver._gpu_init_done or not submit_frame():return false
	last_submit_ms=(Time.get_ticks_usec()-start)/1000.0;start=Time.get_ticks_usec()
	if solver._needs_warm_start:
		if not solver.warm_start():frame_error="Candidate warm start unavailable";return false
	else:solver._simulate(delta)
	last_simulate_ms=(Time.get_ticks_usec()-start)/1000.0
	for i in garment.mesh_instance.mesh.get_surface_count():
		var material:ShaderMaterial=garment.mesh_instance.mesh.surface_get_material(i)
		material.set_shader_parameter("candidate_lookup",lookup)
		material.set_shader_parameter("candidate_positions",solver._positions_tex)
		material.set_shader_parameter("candidate_normals",solver._normals_tex)
		material.set_shader_parameter("candidate_simulate",true)
	return true

func _exit_tree()->void:
	indexed_packet.close()
	if not is_instance_valid(garment):return
	for i in garment.mesh_instance.mesh.get_surface_count():garment.mesh_instance.mesh.surface_get_material(i).set_shader_parameter("candidate_simulate",false)
