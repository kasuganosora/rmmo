extends RefCounted
## Same-frame indexed expansion and validation, private per adapter.
## Fix before initialize. Status and payload share one readback, same-frame.
## Paired RX7900XTX measurements favor separate readbacks. Packed is QA-only.
static var default_packed_readback:=false
var packed_readback:=default_packed_readback
var owned_buffers:Array[RID]=[]
var rd:RenderingDevice
var buffers:Array[RID]=[]
var shader:RID
var pipeline:RID
var uniform_set:RID
var topology:=PackedInt32Array()
var point_count:=0
var extra_count:=0
var output:=PackedByteArray()
func initialize(indices:PackedInt32Array,points:int,extras:int)->bool:
	if indices.is_empty() or indices.size()%3 or extras%3:return false
	for index in indices:
		if index<0 or index>=points:return false
	close();topology=indices.duplicate();point_count=points;extra_count=extras
	rd=RenderingServer.create_local_rendering_device()
	if rd==null:return false
	var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string("res://addons/godot_gpu_cloth/shaders/compute/cloth_indexed_packet.glsl").replace("#[compute]","")
	if packed_readback:source.source_compute=source.source_compute.replace("#version 450","#version 450\n#define RMMO_PACKED_STATUS")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():push_error(spirv.compile_error_compute);close();return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	var sizes:Array[int]=[points*12,indices.size()*4,maxi(extras*12,12),(indices.size()+extras)*16,4]
	var uniforms:Array[RDUniform]=[]
	for i in sizes.size():
		if packed_readback and i==4:buffers.append(buffers[3])
		else:
			var rid:=rd.storage_buffer_create(sizes[i]+(16 if packed_readback and i==3 else 0))
			buffers.append(rid);owned_buffers.append(rid)
		var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(buffers[i]);uniforms.append(u)
	rd.buffer_update(buffers[1],0,indices.size()*4,indices.to_byte_array())
	uniform_set=rd.uniform_set_create(uniforms,shader,0);return true
func build(points:PackedVector3Array,offset:Vector3,extras:PackedVector3Array,read_payload:=true)->bool:
	if rd==null or points.size()!=point_count or extras.size()!=extra_count or not offset.is_finite():return false
	var bytes:=points.to_byte_array();rd.buffer_update(buffers[0],0,bytes.size(),bytes)
	if extra_count:
		bytes=extras.to_byte_array();rd.buffer_update(buffers[2],0,bytes.size(),bytes)
	var zero:=PackedByteArray([0,0,0,0]);rd.buffer_update(buffers[4],0,4,zero)
	var push:=PackedByteArray();push.resize(32)
	push.encode_u32(0,topology.size()/3);push.encode_u32(4,extra_count/3)
	push.encode_float(16,offset.x);push.encode_float(20,offset.y);push.encode_float(24,offset.z)
	var cl:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(cl,pipeline);rd.compute_list_bind_uniform_set(cl,uniform_set,0)
	rd.compute_list_set_push_constant(cl,push,32);rd.compute_list_dispatch(cl,ceili(float((topology.size()+extra_count)/3)/64),1,1);rd.compute_list_end();rd.submit();rd.sync()
	if packed_readback:
		if not read_payload:return rd.buffer_get_data(buffers[4],0,4).decode_u32(0)==0
		var result:=rd.buffer_get_data(buffers[3])
		if result.decode_u32(0)!=0:return false
		output=result.slice(16)
	else:
		if rd.buffer_get_data(buffers[4]).decode_u32(0)!=0:return false
		if read_payload:output=rd.buffer_get_data(buffers[3])
	return true
func close()->void:
	if rd==null:return
	if uniform_set.is_valid():rd.free_rid(uniform_set)
	for rid in owned_buffers:rd.free_rid(rid)
	if pipeline.is_valid():rd.free_rid(pipeline)
	if shader.is_valid():rd.free_rid(shader)
	rd.free();rd=null;buffers.clear();owned_buffers.clear();uniform_set=RID();pipeline=RID();shader=RID()
func _notification(what:int)->void:
	if what!=NOTIFICATION_PREDELETE or rd==null:return
	# Do not call a method on self after the reference count reaches zero.
	if uniform_set.is_valid():rd.free_rid(uniform_set)
	for rid in owned_buffers:rd.free_rid(rid)
	if pipeline.is_valid():rd.free_rid(pipeline)
	if shader.is_valid():rd.free_rid(shader)
	rd.free()
