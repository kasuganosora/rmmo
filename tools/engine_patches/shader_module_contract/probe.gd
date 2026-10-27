extends SceneTree
var checks:=0
var failures:Array[String]=[]
var output:=""
var gate:=Semaphore.new()
var rd:RenderingDevice
func check(v:bool,s:String)->void:
 checks+=1
 if not v:failures.append(s);push_error(s)
func _initialize()->void:
 for x in OS.get_cmdline_user_args():
  if x.begins_with("--output="):output=x.trim_prefix("--output=")
 call_deferred("run")
func thread_work(binary:PackedByteArray)->RID:
 gate.wait()
 return rd.shader_create_from_bytecode(binary)
func compute_value(shader:RID,expected:int)->void:
 var initial:=PackedByteArray();initial.resize(4)
 var buffer:=rd.storage_buffer_create(4,initial)
 var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;uniform.binding=0;uniform.add_id(buffer)
 var uniform_set:=rd.uniform_set_create([uniform],shader,0)
 var pipeline:=rd.compute_pipeline_create(shader)
 check(buffer.is_valid() and uniform_set.is_valid() and pipeline.is_valid(),"compute resources created")
 if buffer.is_valid() and uniform_set.is_valid() and pipeline.is_valid():
  var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,uniform_set,0);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_end()
  await process_frame
  var bytes:=rd.buffer_get_data(buffer)
  check(bytes.size()==4 and bytes.decode_u32(0)==expected,"compute GPU output matches expected program")
 if pipeline.is_valid():rd.free_rid(pipeline)
 if uniform_set.is_valid():rd.free_rid(uniform_set)
 if buffer.is_valid():rd.free_rid(buffer)
func render_red(shader:RID)->PackedByteArray:
 var format:=RDTextureFormat.new();format.width=8;format.height=8;format.format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM;format.usage_bits=RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
 var texture:=rd.texture_create(format,RDTextureView.new())
 var fb:=rd.framebuffer_create([texture]);var vertex:=rd.vertex_format_create([]);var vertex_array:=rd.vertex_array_create(3,vertex,[])
 var blend:=RDPipelineColorBlendState.new();blend.attachments=[RDPipelineColorBlendStateAttachment.new()]
 var pipeline:=rd.render_pipeline_create(shader,rd.framebuffer_get_format(fb),vertex,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,RDPipelineRasterizationState.new(),RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),blend)
 check(texture.is_valid() and fb.is_valid() and vertex_array.is_valid() and pipeline.is_valid(),"original graphics owner pipeline valid")
 var pixels:=PackedByteArray()
 if texture.is_valid() and fb.is_valid() and vertex_array.is_valid() and pipeline.is_valid():
  var list:=rd.draw_list_begin(fb,RenderingDevice.DRAW_CLEAR_COLOR_0,PackedColorArray([Color(0,0,0,1)]))
  rd.draw_list_bind_render_pipeline(list,pipeline);rd.draw_list_bind_vertex_array(list,vertex_array);rd.draw_list_draw(list,false,1,3);rd.draw_list_end()
  await process_frame
  pixels=rd.texture_get_data(texture,0)
  check(pixels.size()==256 and pixels[0]==255 and pixels[1]==0 and pixels[2]==0,"graphics GPU output red")
 if pipeline.is_valid():rd.free_rid(pipeline)
 if vertex_array.is_valid():rd.free_rid(vertex_array)
 if fb.is_valid():rd.free_rid(fb)
 if texture.is_valid():rd.free_rid(texture)
 return pixels
func run()->void:
 rd=RenderingServer.get_rendering_device()
 check(rd!=null and not output.is_empty(),"private GPU and output available")
 if not failures.is_empty():quit(1);return
 check(rd.has_method("rmmo_test_shader_destroy_modules"),"test-only explicit destroy hook enabled")
 var src:=RDShaderSource.new()
 src.source_compute="#version 450\nlayout(local_size_x=1,local_size_y=1,local_size_z=1) in; layout(set=0,binding=0,std430) buffer Result { uint value; } result; layout(constant_id=0) const uint rmmo_spec=0u; void main(){result.value=0x11223344u+rmmo_spec;}\n"
 var spirv:=rd.shader_compile_spirv_from_source(src)
 check(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty(),"compute shader compiles")
 var binary:=rd.shader_compile_binary_from_spirv(spirv,"RmmoModuleCompute")
 var one:=rd.shader_create_from_bytecode(binary)
 var two:=rd.shader_create_from_bytecode(binary)
 check(one.is_valid() and two.is_valid() and one!=two,"two distinct RIDs created")
 if not failures.is_empty():quit(1);return
 rd.call("rmmo_test_shader_destroy_modules",one)
 rd.call("rmmo_test_shader_destroy_modules",one)
 var pipeline:=rd.compute_pipeline_create(two)
 check(pipeline.is_valid(),"second owner pipeline works after first explicit repeated destroy")
 if pipeline.is_valid():rd.free_rid(pipeline)
 await compute_value(two,0x11223344)
 for device_index in 2:
  var local:=RenderingServer.create_local_rendering_device()
  check(local!=null,"independent local device available")
  if local==null:continue
  var local_a:=local.shader_create_from_bytecode(binary)
  var local_b:=local.shader_create_from_bytecode(binary)
  check(local_a.is_valid() and local_b.is_valid() and local_a!=local_b,"independent device creates own two owners")
  if local_a.is_valid():local.free_rid(local_a)
  if local_b.is_valid():local.free_rid(local_b)
  local.free()
 rd.free_rid(one)
 var workers:Array[Thread]=[]
 for i in 8:
  var t:=Thread.new();workers.append(t);check(t.start(thread_work.bind(binary))==OK,"worker started")
 for i in 8:gate.post()
 while true:
  var busy:=false
  for t in workers:busy=busy or t.is_alive()
  if not busy:break
  await process_frame
 for t in workers:
  var rid:RID=t.wait_to_finish();check(rid.is_valid(),"concurrent owner valid")
  if rid.is_valid():rd.free_rid(rid)
 var src2:=RDShaderSource.new()
 src2.source_compute="#version 450\nlayout(local_size_x=1,local_size_y=1,local_size_z=1) in; layout(set=0,binding=0,std430) buffer Result { uint value; } result; layout(constant_id=0) const uint rmmo_spec=0u; void main(){result.value=0x55667788u+rmmo_spec;}\n"
 var different:=rd.shader_compile_spirv_from_source(src2)
 check(different.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty(),"second distinct shader compiles")
 check(spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE)!=different.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE),"collision inputs are actually different bytes")
 var b2:=rd.shader_compile_binary_from_spirv(different,"RmmoModuleDifferent")
 var distinct:=rd.shader_create_from_bytecode(b2)
 check(distinct.is_valid(),"distinct bytes accepted under forced hash collision")
 if distinct.is_valid():
  await compute_value(two,0x11223344)
  await compute_value(distinct,0x55667788)
  rd.free_rid(distinct)
 rd.free_rid(two)
 var pair:=RDShaderSource.new()
 pair.source_vertex="#version 450\nlayout(constant_id=0) const float rmmo_scale=1.0;void main(){vec2 p[3]=vec2[3](vec2(-1,-1),vec2(3,-1),vec2(-1,3));gl_Position=vec4(p[gl_VertexIndex]*rmmo_scale,0,1);}\n"
 pair.source_fragment="#version 450\nlayout(location=0) out vec4 c;void main(){c=vec4(1,0,0,1);}\n"
 var pairspirv:=rd.shader_compile_spirv_from_source(pair)
 check(pairspirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_VERTEX).is_empty() and pairspirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_FRAGMENT).is_empty(),"two stage shader compiles")
 var good:=rd.shader_compile_binary_from_spirv(pairspirv,"RmmoModulePair")
 var fail:=rd.shader_compile_binary_from_spirv(pairspirv,"RmmoModuleFail")
 var owner:=rd.shader_create_from_bytecode(good)
 check(owner.is_valid(),"two stage owner valid")
 var before_pixels:PackedByteArray=await render_red(owner)
 var bad:=rd.shader_create_from_bytecode(fail)
 check(not bad.is_valid(),"second-stage injected failure returns invalid RID")
 var after_pixels:PackedByteArray=await render_red(owner)
 check(not before_pixels.is_empty() and before_pixels==after_pixels,"original owner GPU output unchanged after partial rollback")
 var still:=rd.shader_create_from_bytecode(good)
 check(still.is_valid(),"owner stays valid after injected partial rollback")
 if still.is_valid():rd.free_rid(still)
 if owner.is_valid():rd.free_rid(owner)
 RenderingServer.force_sync()
 for i in 2:await process_frame
 var report={"checks":checks,"failures":failures}
 var f:=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify(report));f.close()
 print("RMMO_MODULE_CONTRACT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
