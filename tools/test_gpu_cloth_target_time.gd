extends SceneTree
## Execute the production prediction shader against a known moving attachment.
## Both fixed and blended particles must see the collider's substep time.
func _initialize()->void:call_deferred("run")
func uniform(binding:int,rid:RID)->RDUniform:
	var result:=RDUniform.new();result.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;result.binding=binding;result.add_id(rid);return result
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device();assert(rd!=null)
	var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string("res://addons/godot_gpu_cloth/shaders/compute/cloth_predict.glsl").replace("\r\n","\n").replace("#[compute]\n","")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():push_error(error);rd.free();quit(2);return
	var shader:=rd.shader_create_from_spirv(spirv);var pipeline:=rd.compute_pipeline_create(shader);var ok:=true
	for interpolate:bool in [false,true]:
		for fraction:float in [.25,.5,1.0]:
			# Rest x=0; the authored target moves 80 mm during this frame.
			var data:Dictionary={0:PackedFloat32Array([0,0,0,0, 0,0,0,1]),1:PackedFloat32Array([0,0,0,0, 0,0,0,1]),2:PackedFloat32Array([0,0,0,0, 0,0,0,0]),5:PackedFloat32Array([.08,0,0,0, .08,0,0,0]),6:PackedFloat32Array([0,0,0,0, .5,0,0,0]),7:PackedFloat32Array([0,0,0,0, 0,0,0,0])}
			var uniforms:Array[RDUniform]=[];var buffers:Dictionary={}
			for binding:int in data:
				var bytes:PackedByteArray=data[binding].to_byte_array()
				buffers[binding]=rd.storage_buffer_create(bytes.size(),bytes);uniforms.append(uniform(binding,buffers[binding]))
			var bindings:=rd.uniform_set_create(uniforms,shader,0)
			var push:=PackedByteArray();push.resize(96);push.encode_float(0,1.0/240);push.encode_u32(8,2);push.encode_float(20,5);push.encode_float(60,.25);push.encode_float(76,1);push.encode_float(88,fraction);push.encode_float(92,1 if interpolate else 0)
			var commands:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(commands,pipeline);rd.compute_list_bind_uniform_set(commands,bindings,0);rd.compute_list_set_push_constant(commands,push,96);rd.compute_list_dispatch(commands,1,1,1);rd.compute_list_end();rd.submit();rd.sync()
			var values:=rd.buffer_get_data(buffers[1]).to_float32_array()
			var target:float=.08*(fraction if interpolate else 1)
			ok=ok and absf(values[0]-target)<.000001 and absf(values[4]-target*(1-pow(.5,.25)))<.000001
			print("TARGET TIME interpolate=",interpolate," fraction=",fraction," pinned=",values[0]," blend=",values[4])
			rd.free_rid(bindings)
			for rid:RID in buffers.values():rd.free_rid(rid)
	for rid:RID in [pipeline,shader]:rd.free_rid(rid)
	rd.free()
	if ok:print("PASS attachment and collider substep time, including legacy replay");quit()
	else:push_error("Attachment jumped ahead of collision time");quit(2)
