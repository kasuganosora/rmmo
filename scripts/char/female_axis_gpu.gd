extends RefCounted
## Per-instance compute buffers; CPU reference remains available for numerical QA.
var rd:RenderingDevice
var buffers:Array[RID]=[]
var shader:RID
var pipeline:RID
var uniform_set:RID
var last_positions:PackedByteArray
var last_normals:PackedByteArray
var rest_data:=PackedFloat32Array()
func initialize(folder:String)->bool:
	if RenderingServer.get_rendering_device()==null:return false
	rd=RenderingServer.create_local_rendering_device()
	if rd==null:return false
	var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string("res://scripts/char/female_axis_compute.glsl").replace("#[compute]","")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():push_error(spirv.compile_error_compute);close();return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	var data:Array[PackedByteArray]=[]
	data.append(FileAccess.get_file_as_bytes(folder+"/axis_gpu_rest.bin"));data.append(FileAccess.get_file_as_bytes(folder+"/axis_gpu_weights.bin"))
	rest_data=data[0].to_float32_array()
	var bone_data:=PackedByteArray();bone_data.resize(80*16*16);data.append(bone_data)
	var positions:=PackedByteArray();positions.resize(512*43*16);data.append(positions)
	data.append(FileAccess.get_file_as_bytes(folder+"/axis_gpu_adjacency.bin"));data.append(FileAccess.get_file_as_bytes(folder+"/axis_gpu_triangles.bin"));data.append(positions)
	var uniforms:Array[RDUniform]=[]
	for i in data.size():
		var rid:=rd.storage_buffer_create(data[i].size(),data[i]);buffers.append(rid)
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;uniform.binding=i;uniform.add_id(rid);uniforms.append(uniform)
	uniform_set=rd.uniform_set_create(uniforms,shader,0);return true
func set_rest_points(points:PackedVector3Array)->bool:
	# The original buffer includes padding to the 512x43 display texture size.
	if rd==null or points.size()!=21556 or points.size()*4>rest_data.size():return false
	for point:Vector3 in points:
		if not point.is_finite():return false
	for i in points.size():
		# Preserve W: it is the number of original axis-weight records.
		for axis in 3:rest_data[i*4+axis]=points[i][axis]
	var bytes:=rest_data.to_byte_array()
	return rd.buffer_update(buffers[0],0,bytes.size(),bytes)==OK
func evaluate(nodes:Array,solved_bones:Array[Transform3D],bulge_scale:float,offset:Vector3)->void:
	var bone_data:=PackedFloat32Array();bone_data.resize(80*64)
	for i in nodes.size():
		var node:Dictionary=nodes[i];var angles:Vector3=node.angles
		var transforms:Array[Transform3D]=[node.rest_frame,node.inverse_frame,solved_bones[node.skeleton_index]*node.inverse_frame]
		for t in 3:
			var transform:Transform3D=transforms[t]
			var columns:Array[Vector3]=[transform.basis.x,transform.basis.y,transform.basis.z,transform.origin]
			for column in 4:
				for row in 3:bone_data[i*64+t*16+column*4+row]=columns[column][row]
				bone_data[i*64+t*16+column*4+3]=1.0 if column==3 else 0.0
		for axis in 3:
			bone_data[i*64+48+axis]=angles[axis]
			var prefix:String="xyz"[axis]+("pos" if angles[axis]>0 else "neg")
			if absf(angles[axis])>.01:
				bone_data[i*64+52+axis]=node.bulge[prefix+"left"]*angles[axis]*bulge_scale
				bone_data[i*64+56+axis]=node.bulge[prefix+"right"]*angles[axis]*bulge_scale
		bone_data[i*64+51]=node.order
	var bytes:=bone_data.to_byte_array();rd.buffer_update(buffers[2],0,bytes.size(),bytes)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,uniform_set,0)
	for pass_index in 2:
		var push:=PackedFloat32Array([offset.x,offset.y,offset.z,float(pass_index)]).to_byte_array()
		rd.compute_list_set_push_constant(list,push,16);rd.compute_list_dispatch(list,337,1,1)
		if pass_index==0:rd.compute_list_add_barrier(list)
	rd.compute_list_end();rd.submit();rd.sync()
	last_positions=rd.buffer_get_data(buffers[3]);last_normals=rd.buffer_get_data(buffers[6])
func close()->void:
	if rd==null:return
	if uniform_set.is_valid():rd.free_rid(uniform_set)
	if pipeline.is_valid():rd.free_rid(pipeline)
	if shader.is_valid():rd.free_rid(shader)
	for rid in buffers:rd.free_rid(rid)
	buffers.clear();rd.free();rd=null
