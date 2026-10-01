extends SceneTree
## Compare real GPU outputs with and without block culling. Uneven block counts,
## moving colliders, rotated coordinates, substeps and reverse vertex IDs.
var rd:RenderingDevice
var owned:Array[RID]=[]
var failed:=false
func _initialize()->void:call_deferred("run")
func buffer(bytes:PackedByteArray)->RID:
	var result:=rd.storage_buffer_create(bytes.size(),bytes);owned.append(result);return result
func uniform(binding:int,rid:RID)->RDUniform:
	var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=binding;u.add_id(rid);return u
func shader(name:String, exhaustive:=false,define:String="")->RID:
	var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string("res://addons/godot_gpu_cloth/shaders/compute/"+name+".glsl").replace("\r\n","\n").replace("#[compute]\n","")
	if exhaustive:source.source_compute=source.source_compute.replace("#version 450","#version 450\n#define RMMO_EXHAUSTIVE_SANITIZE")
	if not define.is_empty():source.source_compute=source.source_compute.replace("#version 450","#version 450\n#define "+define)
	var spirv:=rd.shader_compile_spirv_from_source(source)
	var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():
		failed=true;push_error(name+" "+define+": "+error);return RID()
	var result:=rd.shader_create_from_spirv(spirv);owned.append(result);return result
func dispatch(program:RID,data:Dictionary,push:PackedByteArray,count:int)->void:
	var uniforms:Array[RDUniform]=[]
	for key:int in data:uniforms.append(uniform(key,data[key]))
	var bindings:=rd.uniform_set_create(uniforms,program,0)
	var pipeline:=rd.compute_pipeline_create(program)
	var cl:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(cl,pipeline);rd.compute_list_bind_uniform_set(cl,bindings,0)
	rd.compute_list_set_push_constant(cl,push,push.size());rd.compute_list_dispatch(cl,ceili(float(count)/64),1,1);rd.compute_list_end();rd.submit();rd.sync()
	rd.free_rid(bindings);rd.free_rid(pipeline)
func run()->void:
	rd=RenderingServer.create_local_rendering_device();assert(rd!=null)
	var original:=shader("cloth_solve");var batched:=shader("cloth_solve",false,"RMMO_BATCHED_SOLVE")
	if failed:quit(2);return
	var worst:=0.0
	for compliance in [0.0,.000001,.001,1.0]:
		var points:=PackedVector4Array()
		for i in 702:points.append(Vector4(i*.013,sin(i*.2)*.02,cos(i*.13)*.02,0 if i%11==0 else 1))
		var constraints:=PackedVector4Array();var groups:=PackedInt32Array()
		for parity in 2:
			var start:=constraints.size()
			for i in range(parity,701,2):constraints.append(Vector4(i,i+1,.01,compliance))
			groups.append(start);groups.append(constraints.size()-start)
		var pos:=buffer(points.to_byte_array());var cs:=buffer(constraints.to_byte_array());var gb:=buffer(groups.to_byte_array())
		var zeros:=PackedByteArray();zeros.resize(constraints.size()*4);var lambdas:=buffer(zeros)
		var push:=PackedByteArray();push.resize(96);push.encode_float(0,1.0/240.0)
		var reference:=PackedFloat32Array();var reference_lambdas:=PackedByteArray()
		for mode in [false,true]:
			rd.buffer_update(pos,0,points.size()*16,points.to_byte_array());rd.buffer_update(lambdas,0,zeros.size(),zeros)
			for iteration in 24:
				var reset:=0x80000000 if iteration%6==0 else 0
				if mode:
					push.encode_u32(12,2);push.encode_u32(28,reset)
					dispatch(batched,{1:pos,3:cs,8:lambdas,9:gb},push,1)
				else:
					for group in 2:
						push.encode_u32(12,groups[group*2+1]);push.encode_u32(28,groups[group*2]|reset)
						dispatch(original,{1:pos,3:cs,8:lambdas},push,groups[group*2+1])
			var actual:=rd.buffer_get_data(pos).to_float32_array()
			if not mode:reference=actual;reference_lambdas=rd.buffer_get_data(lambdas)
			else:
				for i in actual.size():assert(is_finite(actual[i]));worst=maxf(worst,absf(reference[i]-actual[i]))
				assert(reference_lambdas==rd.buffer_get_data(lambdas),"XPBD lambda accumulation changed")
	for i in range(owned.size()-1,-1,-1):rd.free_rid(owned[i])
	rd.free()
	if worst>.000002:push_error("Batched solve mismatch "+str(worst));quit(2);return
	print("PASS batched constraints: 4 compliance cases x 24 iterations, >256 constraints/color, pinned points, lambda resets; max error=",worst);quit()
