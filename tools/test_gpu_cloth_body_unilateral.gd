extends SceneTree
## A historical sweep must not pull a separated point back onto a moving
## surface, or hide a later unresolved contact. Final-position test only.
func _initialize()->void:call_deferred("run")
func uniform(binding:int,rid:RID)->RDUniform:
	var result:=RDUniform.new();result.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;result.binding=binding;result.add_id(rid);return result
func packed(points:Array[Vector3])->PackedByteArray:
	var values:=PackedFloat32Array()
	for p:Vector3 in points:values.append_array(PackedFloat32Array([p.x,p.y,p.z,0]))
	return values.to_byte_array()
func body(t:float,second:bool,basis:Basis)->Array[Vector3]:
	# The signed plane distance at the origin is proportional to
	# (t-.25)*(t-.75): two historical crossings, separated at the end.
	var center:=Vector3(0,t-.5,-.1875+.5*t);var v:=Vector3(0,1,t)*3
	var points:Array[Vector3]=[center-Vector3.RIGHT*3-v,center+Vector3.RIGHT*3-v,center+v]
	if second:
		var x:=t-.5
		points.append_array([Vector3(x,-2,-2),Vector3(x,2,-2),Vector3(x,0,2)])
	for i in points.size():points[i]=basis*points[i]
	return points
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device();assert(rd!=null)
	var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string("res://addons/godot_gpu_cloth/shaders/compute/cloth_collide_triangles.glsl").replace("\r\n", "\n").replace("#[compute]\n", "")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	var compile_error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not compile_error.is_empty():push_error(compile_error);rd.free();quit(2);return
	var shader:=rd.shader_create_from_spirv(spirv);var pipeline:=rd.compute_pipeline_create(shader);var ok:=true
	for case_index in 4:
		var second:bool=case_index%2==1
		var basis:=Basis.IDENTITY if case_index<2 else Basis(Vector3(1,2,3).normalized(),.7)
		var point:=PackedFloat32Array([0,0,0,1]).to_byte_array()
		var directions:=PackedByteArray();directions.resize(32)
		var data:Dictionary={0:point,1:point,4:packed(body(1,second,basis)),5:PackedFloat32Array([1,0,0,0]).to_byte_array(),6:packed(body(0,second,basis)),7:directions}
		var uniforms:Array[RDUniform]=[];var buffers:Dictionary={}
		for key:int in data:
			buffers[key]=rd.storage_buffer_create(data[key].size(),data[key]);uniforms.append(uniform(key,buffers[key]))
		var bindings:=rd.uniform_set_create(uniforms,shader,0)
		var push:=PackedByteArray();push.resize(32);push.encode_u32(0,1);push.encode_u32(4,2 if second else 1);push.encode_float(8,.006);push.encode_float(20,1)
		var commands:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(commands,pipeline);rd.compute_list_bind_uniform_set(commands,bindings,0)
		rd.compute_list_set_push_constant(commands,push,32);rd.compute_list_dispatch(commands,1,1,1);rd.compute_list_end();rd.submit();rd.sync()
		var result:=rd.buffer_get_data(buffers[1]).to_float32_array();var actual:=Vector3(result[0],result[1],result[2]);var expected:=Vector3(.506,0,0) if second else Vector3.ZERO
		expected=basis*expected
		print("BODY UNILATERAL case=",case_index," second=",second," position=",actual," error=",actual.distance_to(expected))
		ok=ok and actual.is_finite() and actual.distance_to(expected)<.00001
		rd.free_rid(bindings)
		for rid:RID in buffers.values():rd.free_rid(rid)
	for rid:RID in [pipeline,shader]:rd.free_rid(rid)
	rd.free()
	if ok:print("PASS body projection has no historical attraction and keeps unresolved contact");quit()
	else:push_error("Resolved body sweep attracted point or hid unresolved contact");quit(2)
