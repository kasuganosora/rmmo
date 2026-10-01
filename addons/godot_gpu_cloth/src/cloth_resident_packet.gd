extends RefCounted
## Main RenderingDevice payload, local-device status-only validation. No main
## queue synchronization per frame: validated uploads precede the solver in FIFO.
var validator=preload("res://addons/godot_gpu_cloth/src/cloth_indexed_packet.gd").new()
var rd:RenderingDevice
var topology:=PackedInt32Array()
var point_count:=0
var extra_count:=0
var output:=PackedByteArray() # Deliberately empty; reference path compatibility.
var output_buffer:RID
var output_bytes:=0
var buffers:Array[RID]=[]
var shader:RID
var pipeline:RID
var uniform_set:RID
var success:=false
var status_readback_bytes:=0
var payload_readback_bytes:=0
var packed_readback:=false
## Provider updates and this expansion use the same render-thread FIFO. Only
## identical submitted CPU snapshots may share the mutable input buffer; output
## packets/history remain independently owned. Never free the provider buffer.
var point_source:RefCounted
var point_upload_bytes:=0
var shared_point_read_bytes:=0
var shared_uniform_set:RID
var shared_buffer:RID
func set_point_source(source:RefCounted)->void:point_source=source
func is_gpu_resident()->bool:return true
func initialize(indices:PackedInt32Array,points:int,extras:int)->bool:
	if indices.is_empty() or indices.size()%3 or extras<0 or extras%3 or points<=0:return false
	for index in indices:
		if index<0 or index>=points:return false
	close();topology=indices.duplicate();point_count=points;extra_count=extras
	output_bytes=(indices.size()+extras)*16
	if not validator.initialize(indices,points,extras):return false
	RenderingServer.call_on_render_thread(_initialize_gpu)
	RenderingServer.force_sync()
	return success
func _initialize_gpu()->void:
	rd=RenderingServer.get_rendering_device();success=false
	if rd==null:return
	var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string("res://addons/godot_gpu_cloth/shaders/compute/cloth_indexed_packet.glsl").replace("#[compute]","")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():push_error(spirv.compile_error_compute);return
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	var sizes:Array[int]=[point_count*12,topology.size()*4,maxi(extra_count*12,12),output_bytes,4]
	var uniforms:Array[RDUniform]=[]
	for i in sizes.size():
		buffers.append(rd.storage_buffer_create(sizes[i]))
		var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(buffers[i]);uniforms.append(u)
	rd.buffer_update(buffers[1],0,topology.size()*4,topology.to_byte_array())
	uniform_set=rd.uniform_set_create(uniforms,shader,0)
	output_buffer=rd.storage_buffer_create(output_bytes);success=true
func build(points:PackedVector3Array,offset:Vector3,extras:PackedVector3Array)->bool:
	if rd==null or points.size()!=point_count or extras.size()!=extra_count or not offset.is_finite():return false
	var valid:bool=validator.build(points,offset,extras,false)
	status_readback_bytes+=4
	if not valid:return false
	var shared:=RID()
	if point_source!=null and point_source.rd==rd:shared=point_source.shared_points_buffer(points)
	var upload:=PackedByteArray()
	if shared.is_valid():shared_point_read_bytes+=points.size()*12
	else:upload=points.to_byte_array();point_upload_bytes+=upload.size()
	RenderingServer.call_on_render_thread(_build_gpu.bind(upload,offset,extras.to_byte_array(),shared))
	return true
func _build_gpu(points:PackedByteArray,offset:Vector3,extras:PackedByteArray,shared:RID)->void:
	var bindings:=uniform_set
	if shared.is_valid():
		if shared_buffer!=shared or not rd.uniform_set_is_valid(shared_uniform_set):
			if shared_uniform_set.is_valid() and rd.uniform_set_is_valid(shared_uniform_set):rd.free_rid(shared_uniform_set)
			var uniforms:Array[RDUniform]=[]
			for i in buffers.size():
				var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(shared if i==0 else buffers[i]);uniforms.append(u)
			shared_uniform_set=rd.uniform_set_create(uniforms,shader,0);shared_buffer=shared
		bindings=shared_uniform_set
	else:rd.buffer_update(buffers[0],0,points.size(),points)
	if not extras.is_empty():rd.buffer_update(buffers[2],0,extras.size(),extras)
	rd.buffer_update(buffers[4],0,4,PackedByteArray([0,0,0,0]))
	var push:=PackedByteArray();push.resize(32)
	push.encode_u32(0,topology.size()/3);push.encode_u32(4,extra_count/3)
	push.encode_float(16,offset.x);push.encode_float(20,offset.y);push.encode_float(24,offset.z)
	var cl:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(cl,pipeline);rd.compute_list_bind_uniform_set(cl,bindings,0)
	rd.compute_list_set_push_constant(cl,push,32);rd.compute_list_dispatch(cl,ceili(float((topology.size()+extra_count)/3)/64),1,1);rd.compute_list_end()
	# The identical immutable inputs were validated on the local device before
	# this callback was queued. No payload/status readback on the main device.
	# This copy must execute in release builds too (assert expressions may not).
	var error:=rd.buffer_copy(buffers[3],output_buffer,0,0,output_bytes)
	if error!=OK:push_error("Resident collider GPU copy failed: "+str(error))
func close()->void:
	point_source=null
	validator.close()
	if rd==null:return
	var device:=rd;var shared_set:=shared_uniform_set;var resources:Array[RID]=[uniform_set]
	resources.append_array(buffers);resources.append_array([output_buffer,pipeline,shader])
	# Capture values, not this RefCounted, so PREDELETE cannot leave a dangling callback.
	RenderingServer.call_on_render_thread(func():
		if shared_set.is_valid() and device.uniform_set_is_valid(shared_set):device.free_rid(shared_set)
		for rid in resources:
			if rid.is_valid():device.free_rid(rid))
	RenderingServer.force_sync()
	buffers.clear();shared_uniform_set=RID();shared_buffer=RID();output_buffer=RID();uniform_set=RID();pipeline=RID();shader=RID();rd=null;success=false
func _notification(what:int)->void:
	if what!=NOTIFICATION_PREDELETE:return
	# A zero-reference object cannot invoke its own methods during PREDELETE.
	validator.close()
	if rd==null:return
	var device:=rd;var shared_set:=shared_uniform_set;var resources:Array[RID]=[uniform_set]
	resources.append_array(buffers);resources.append_array([output_buffer,pipeline,shader])
	RenderingServer.call_on_render_thread(func():
		if shared_set.is_valid() and device.uniform_set_is_valid(shared_set):device.free_rid(shared_set)
		for rid in resources:
			if rid.is_valid():device.free_rid(rid))
	RenderingServer.force_sync()
