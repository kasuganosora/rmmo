extends SceneTree
## A nearly opposing body contact must not turn a millimetre cloth correction
## into a metre-scale step outside the local contact approximation.
func _initialize()->void:call_deferred("run")
func uniform(binding:int,rid:RID)->RDUniform:
	var value:=RDUniform.new();value.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;value.binding=binding;value.add_id(rid);return value
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device();assert(rd!=null)
	var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string("res://addons/godot_gpu_cloth/shaders/compute/cloth_collide_self_swept.glsl").replace("\r\n", "\n").replace("#[compute]\n", "")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	var compile_error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not compile_error.is_empty():push_error(compile_error);rd.free();quit(2);return
	var shader:=rd.shader_create_from_spirv(spirv);var pipeline:=rd.compute_pipeline_create(shader)
	var old:=PackedFloat32Array([0,.02,0,1, -1,0,-1,0, 0,0,1,0, 1,0,-1,0])
	var current:=old.duplicate();current[1]=.0005
	var weights:=PackedFloat32Array([1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0])
	var directions:=PackedFloat32Array();directions.resize(32)
	var normal:=Vector3(.001,-1,0).normalized();directions[0]=normal.x;directions[1]=normal.y
	var data:Dictionary={0:old.to_byte_array(),1:current.to_byte_array(),2:current.to_byte_array(),3:PackedInt32Array([1,2,3]).to_byte_array(),5:weights.to_byte_array(),6:old.to_byte_array(),7:PackedInt32Array([0,0,0,0]).to_byte_array(),8:PackedInt32Array([0,0,0,0]).to_byte_array(),9:PackedInt32Array([0]).to_byte_array(),10:PackedInt32Array([1,2]).to_byte_array(),11:PackedByteArray(),12:directions.to_byte_array()}
	data[11].resize(4*5*16)
	var rids:Dictionary={};var uniforms:Array[RDUniform]=[]
	for key:int in data:
		rids[key]=rd.storage_buffer_create(data[key].size(),data[key]);uniforms.append(uniform(key,rids[key]))
	var bindings:=rd.uniform_set_create(uniforms,shader,0)
	var push:=PackedByteArray();push.resize(32);push.encode_u32(0,4);push.encode_u32(4,1);push.encode_float(8,.006);push.encode_u32(16,1);push.encode_u32(20,1)
	var commands:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(commands,pipeline);rd.compute_list_bind_uniform_set(commands,bindings,0)
	rd.compute_list_set_push_constant(commands,push,32);rd.compute_list_dispatch(commands,1,1,1);rd.compute_list_add_barrier(commands)
	push.encode_u32(24,2);rd.compute_list_set_push_constant(commands,push,32);rd.compute_list_dispatch(commands,1,1,1)
	rd.compute_list_end();rd.submit();rd.sync()
	var output:=rd.buffer_get_data(rids[1]).to_float32_array()
	var delta:=Vector3(output[0],output[1]-.0005,output[2]);var ok:=delta.is_finite() and delta.length()<=.006 and delta.dot(normal)>=-.000001 and delta.y>=0
	print("OBLIQUE CONTACT step_m=",delta.length()," clearance_gain_m=",delta.y," body_plane_dot=",delta.dot(normal))
	for rid:RID in [bindings,pipeline,shader]:rd.free_rid(rid)
	for rid:RID in rids.values():rd.free_rid(rid)
	rd.free()
	if ok:print("PASS bounded local contact reaction (not complete separation)");quit()
	else:push_error("Oblique contact amplified a local correction beyond its validity");quit(2)
