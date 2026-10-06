extends SceneTree
## Exercise the actual shader helper against known half-space projections.
## Keeping one contact must not reintroduce penetration into the other contact.
func _initialize()->void:call_deferred("run")
func uniform(binding:int,rid:RID)->RDUniform:
	var result:=RDUniform.new();result.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;result.binding=binding;result.add_id(rid);return result
func run()->void:
	var shader_text:=FileAccess.get_file_as_string("res://addons/godot_gpu_cloth/shaders/compute/cloth_collide_self_swept.glsl")
	var begin:=shader_text.find("vec3 body_safe(");var end:=shader_text.find("vec3 closest_point_on_triangle",begin)
	assert(begin>=0 and end>begin)
	var cases:Array=[
		[Vector3.RIGHT,Vector3(-.99,.1,0).normalized(),Vector3(-1,-1,.5),Vector3(0,0,.5)],
		[Vector3.ZERO,Vector3.ZERO,Vector3(-1,.3,.5),Vector3(-1,.3,.5)],
		[Vector3.RIGHT,Vector3.ZERO,Vector3(-1,.3,.5),Vector3(0,.3,.5)],
		[Vector3.RIGHT,Vector3.LEFT,Vector3(1,-1,.5),Vector3(0,-1,.5)],
		[Vector3.RIGHT,Vector3.UP,Vector3(-1,-1,.5),Vector3(0,0,.5)],
		[Vector3.RIGHT,Vector3(-.5,.8660254,0).normalized(),Vector3(-1,.25,.5),Vector3(0,.25,.5)],
		[Vector3.RIGHT,Vector3(-.99,.1,0).normalized(),Vector3(1,20,.5),Vector3(1,20,.5)]]
	var rotated:Basis=Basis(Vector3(1,2,3).normalized(),.74)
	var original:Array=cases.duplicate(true)
	for entry:Array in original:cases.append([rotated*entry[0],rotated*entry[1],rotated*entry[2],rotated*entry[3]])
	var normals:=PackedFloat32Array();var inputs:=PackedFloat32Array()
	for entry:Array in cases:
		for i in 2:
			var p:Vector3=entry[i];normals.append_array(PackedFloat32Array([p.x,p.y,p.z,1]))
		var p:Vector3=entry[2];inputs.append_array(PackedFloat32Array([p.x,p.y,p.z,0]))
	var rd:=RenderingServer.create_local_rendering_device();assert(rd!=null)
	var source:=RDShaderSource.new()
	source.source_compute="#version 450\nlayout(local_size_x=1) in;\nlayout(set=0,binding=0,std430) readonly buffer Normals {vec4 body_directions[];};\nlayout(set=0,binding=1,std430) readonly buffer Inputs {vec4 input_direction[];};\nlayout(set=0,binding=2,std430) writeonly buffer Outputs {vec4 result[];};\nconst uint body_tangents=1u;\n"+shader_text.substr(begin,end-begin)+"\nvoid main(){uint i=gl_GlobalInvocationID.x;result[i]=vec4(body_safe(i,input_direction[i].xyz),0);}\n"
	var spirv:=rd.shader_compile_spirv_from_source(source)
	assert(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty())
	var shader:=rd.shader_create_from_spirv(spirv);var pipeline:=rd.compute_pipeline_create(shader)
	var normal_buffer:=rd.storage_buffer_create(normals.size()*4,normals.to_byte_array())
	var input_buffer:=rd.storage_buffer_create(inputs.size()*4,inputs.to_byte_array())
	var output_buffer:=rd.storage_buffer_create(inputs.size()*4)
	var bindings:=rd.uniform_set_create([uniform(0,normal_buffer),uniform(1,input_buffer),uniform(2,output_buffer)],shader,0)
	var commands:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(commands,pipeline);rd.compute_list_bind_uniform_set(commands,bindings,0)
	rd.compute_list_dispatch(commands,cases.size(),1,1);rd.compute_list_end();rd.submit();rd.sync()
	var output:=rd.buffer_get_data(output_buffer).to_float32_array();var ok:=true
	for i in cases.size():
		var result:=Vector3(output[i*4],output[i*4+1],output[i*4+2]);var expected:Vector3=cases[i][3]
		var clearance:float=minf(result.dot(cases[i][0]),result.dot(cases[i][1]))
		var error:=result.distance_to(expected)
		print("BODY DIRECTION case=",i," plane_dot=",clearance," expected_error=",error)
		ok=ok and result.is_finite() and clearance>=-.000001 and error<.00001
	for rid:RID in [bindings,pipeline,shader,normal_buffer,input_buffer,output_buffer]:rd.free_rid(rid)
	rd.free()
	if ok:print("PASS feasible body directions in 14 known and rotated cases");quit()
	else:push_error("Self reaction re-enters an active body half-space");quit(2)
