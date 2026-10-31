extends "res://tools/test_draw_descriptor_scratch.gd"
## Render bind counts are checked in the exported native trace, independently
## of pixel success: changing only set 3 must not record empty batches.
var trace_path:=""
var compute_rows:Array=[]
var compute_shader:RID
var compute_pipeline:RID
var compute_output:RID
var compute_output_set:RID
var compute_values:Array[RID]=[]
var indirect_arguments:RID
const DISPATCHES:=64

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--trace="):trace_path=arg.trim_prefix("--trace=")
	run.call_deferred()

func prepare_compute()->void:
	var source:=RDShaderSource.new()
	source.source_compute="#version 450\nlayout(local_size_x=1,local_size_y=1,local_size_z=1) in;\nlayout(set=0,binding=0,std430) restrict writeonly buffer Result {uint values[];};\nlayout(set=3,binding=0,std140) uniform Value {uvec4 value;};\nlayout(push_constant,std430) uniform Push {uvec4 index;};\nvoid main(){values[index.x]=value.x+index.x;}\n"
	var spirv:=rd.shader_compile_spirv_from_source(source)
	check(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty(),"compute shader compilation")
	compute_shader=keep(rd.shader_create_from_spirv(spirv));compute_pipeline=keep(rd.compute_pipeline_create(compute_shader))
	compute_output=keep(rd.storage_buffer_create(DISPATCHES*4))
	var output_uniform:=RDUniform.new();output_uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;output_uniform.binding=0;output_uniform.add_id(compute_output)
	compute_output_set=keep(rd.uniform_set_create([output_uniform],compute_shader,0))
	for value:int in [11,29]:
		var buffer:=keep(rd.uniform_buffer_create(16,PackedInt32Array([value,0,0,0]).to_byte_array()))
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER;uniform.binding=0;uniform.add_id(buffer)
		compute_values.append(keep(rd.uniform_set_create([uniform],compute_shader,3)))
	indirect_arguments=keep(rd.storage_buffer_create(12,PackedInt32Array([1,1,1]).to_byte_array(),RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT))

func compute_trial(indirect:bool,reuse:bool)->void:
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,compute_pipeline)
	rd.compute_list_bind_uniform_set(list,compute_output_set,0)
	rd.compute_list_bind_uniform_set(list,compute_values[0],3)
	for i:int in DISPATCHES:
		if not reuse:rd.compute_list_bind_uniform_set(list,compute_values[i%2],3)
		var constants:=PackedInt32Array([i,0,0,0]).to_byte_array()
		rd.compute_list_set_push_constant(list,constants,constants.size())
		if indirect:rd.compute_list_dispatch_indirect(list,indirect_arguments,0)
		else:rd.compute_list_dispatch(list,1,1,1)
		# Every dispatch writes a distinct uint. No inter-dispatch dependency
		# exists; a barrier would end/restart the list and rebind every set,
		# preventing this test from exercising a change to set 3 alone.
	rd.compute_list_end();rd.submit();rd.sync()
	var actual:=rd.buffer_get_data(compute_output).to_int32_array();var good:=actual.size()==DISPATCHES
	for i:int in actual.size():good=good and actual[i]==(11 if reuse or i%2==0 else 29)+i
	check(good,"compute values and push constants indirect=%s reuse=%s"%[indirect,reuse])
	compute_rows.append({"indirect":indirect,"reuse":reuse,"dispatches":DISPATCHES,"values_correct":good})

func run()->void:
	check(not output.is_empty() and not trace_path.is_empty() and DisplayServer.get_name()!="headless","output, native trace and real GPU")
	rd=RenderingServer.create_local_rendering_device();check(rd!=null,"local rendering device")
	var trace:Dictionary={}
	if rd!=null:
		prepare();prepare_compute()
		if failures.is_empty():
			check(Performance.call("debug_trace_start",1048576,true)==OK,"native capture start")
			validate_queued_bindings()
			for mode:String in ["reuse","material","sparse","pipeline"]:trial(mode,4096,1)
			for indirect:bool in [false,true]:
				compute_trial(indirect,false);compute_trial(indirect,true)
			trace=Performance.call("debug_trace_stop");check(trace.dropped==0,"trace has no drops")
			check(Performance.call("debug_trace_export",trace_path)==OK,"trace export")
		for i:int in range(owned.size()-1,-1,-1):rd.free_rid(owned[i])
		owned.clear();rd.free()
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"compute":compute_rows,"trace":trace},"\t"))
	print("DESCRIPTOR_BIND_BATCHES checks=",checks," failures=",failures.size());quit(1 if not failures.is_empty() else 0)
