extends RefCounted
## Per-instance compute buffers; CPU reference remains available for numerical QA.
const TEXTURE_BYTES:=512*43*16
const CONTACT_OFFSET:=TEXTURE_BYTES*2
const BOUNDS_OFFSET:=CONTACT_OFFSET+21556*12
const OUTPUT_BYTES:=BOUNDS_OFFSET+337*4
## Select before initialize; outputs remain same-frame and byte-identical.
var packed_readback:=true
var owned_buffers:Array[RID]=[]
var rd:RenderingDevice
var buffers:Array[RID]=[]
var shader:RID
var pipeline:RID
var uniform_set:RID
var last_positions:PackedByteArray
var last_normals:PackedByteArray
var last_points:PackedVector3Array
var last_min_y:=0.0
var last_readback_bytes:=0
var rest_data:=PackedFloat32Array()
func initialize(folder:String)->bool:
	if RenderingServer.get_rendering_device()==null:return false
	rd=RenderingServer.create_local_rendering_device()
	if rd==null:return false
	var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string("res://scripts/char/female_axis_compute.glsl").replace("#[compute]","")
	if packed_readback:source.source_compute=source.source_compute.replace("#version 450","#version 450\n#define RMMO_PACKED_OUTPUT")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():push_error(spirv.compile_error_compute);close();return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	var data:Array[PackedByteArray]=[]
	data.append(FileAccess.get_file_as_bytes(folder+"/axis_gpu_rest.bin"));data.append(FileAccess.get_file_as_bytes(folder+"/axis_gpu_weights.bin"))
	rest_data=data[0].to_float32_array()
	var bone_data:=PackedByteArray();bone_data.resize(80*16*16);data.append(bone_data)
	var positions:=PackedByteArray();positions.resize(512*43*16);data.append(positions)
	data.append(FileAccess.get_file_as_bytes(folder+"/axis_gpu_adjacency.bin"));data.append(FileAccess.get_file_as_bytes(folder+"/axis_gpu_triangles.bin"));data.append(positions)
	var contact_points:=PackedByteArray();contact_points.resize(21556*12);data.append(contact_points)
	var bounds:=PackedByteArray();bounds.resize(337*4);data.append(bounds)
	var uniforms:Array[RDUniform]=[]
	for i in data.size():
		var rid:RID
		if packed_readback and i in [6,7,8]:rid=buffers[3]
		else:
			if packed_readback and i==3:data[i].resize(OUTPUT_BYTES)
			rid=rd.storage_buffer_create(data[i].size(),data[i]);owned_buffers.append(rid)
		buffers.append(rid)
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
func evaluate(nodes:Array,solved_bones:Array[Transform3D],bulge_scale:float,offset:Vector3,read_display:=true)->void:
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
	for pass_index in (2 if read_display else 1):
		var push:=PackedFloat32Array([offset.x,offset.y,offset.z,float(pass_index)]).to_byte_array()
		rd.compute_list_set_push_constant(list,push,16);rd.compute_list_dispatch(list,337,1,1)
		if pass_index==0:rd.compute_list_add_barrier(list)
	rd.compute_list_end();rd.submit();rd.sync()
	var bounds:PackedByteArray
	if not read_display:
		last_positions=PackedByteArray();last_normals=PackedByteArray()
		last_readback_bytes=OUTPUT_BYTES-CONTACT_OFFSET
		if packed_readback:
			var output:=rd.buffer_get_data(buffers[3],CONTACT_OFFSET,OUTPUT_BYTES-CONTACT_OFFSET)
			last_points=output.slice(0,BOUNDS_OFFSET-CONTACT_OFFSET).to_vector3_array()
			bounds=output.slice(BOUNDS_OFFSET-CONTACT_OFFSET)
		else:
			last_points=rd.buffer_get_data(buffers[7]).to_vector3_array()
			bounds=rd.buffer_get_data(buffers[8])
	elif packed_readback:
		last_readback_bytes=OUTPUT_BYTES
		var output:=rd.buffer_get_data(buffers[3])
		last_positions=output.slice(0,TEXTURE_BYTES)
		last_normals=output.slice(TEXTURE_BYTES,CONTACT_OFFSET)
		last_points=output.slice(CONTACT_OFFSET,BOUNDS_OFFSET).to_vector3_array()
		bounds=output.slice(BOUNDS_OFFSET)
	else:
		last_readback_bytes=OUTPUT_BYTES
		last_positions=rd.buffer_get_data(buffers[3]);last_normals=rd.buffer_get_data(buffers[6])
		last_points=rd.buffer_get_data(buffers[7]).to_vector3_array()
		bounds=rd.buffer_get_data(buffers[8])
	last_min_y=INF
	for value:float in bounds.to_float32_array():last_min_y=minf(last_min_y,value)
func close()->void:
	if rd==null:return
	if uniform_set.is_valid():rd.free_rid(uniform_set)
	if pipeline.is_valid():rd.free_rid(pipeline)
	if shader.is_valid():rd.free_rid(shader)
	for rid in owned_buffers:rd.free_rid(rid)
	buffers.clear();owned_buffers.clear();rd.free();rd=null
