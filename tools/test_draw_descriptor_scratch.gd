extends SceneTree
## Real RD draws exercise descriptor reuse, sparse sets and pipeline switches.
## Timings include GD dispatch; submit/sync are reported separately.
var rd:RenderingDevice
var owned:Array[RID]=[]
var failures:Array[String]=[]
var checks:=0
var rows:Array=[]
var output:=""
var shaders:Array[RID]=[]
var pipelines:Array[RID]=[]
var sets:Array=[]
var framebuffer:RID
var texture:RID
var vertex_array:RID

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func keep(rid:RID)->RID:
	check(rid.is_valid(),"native resource valid")
	if rid.is_valid():owned.append(rid)
	return rid
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	run.call_deferred()
func make_shader(factor:int)->RID:
	var src:=RDShaderSource.new()
	src.source_vertex="#version 450\nvoid main(){vec2 p[3]=vec2[3](vec2(-1,-1),vec2(3,-1),vec2(-1,3));gl_Position=vec4(p[gl_VertexIndex],0,1);}\n"
	src.source_fragment="#version 450\nlayout(set=0,binding=0,std140) uniform A {vec4 a;};\nlayout(set=2,binding=0,std140) uniform B {vec4 b;};\nlayout(set=3,binding=0,std140) uniform C {vec4 c;};\nlayout(location=0) out vec4 color;\nvoid main(){color=vec4(a.rgb+b.rgb+c.rgb*%d.0,1.0);}\n"%factor
	var spirv:=rd.shader_compile_spirv_from_source(src)
	for stage:int in [RenderingDevice.SHADER_STAGE_VERTEX,RenderingDevice.SHADER_STAGE_FRAGMENT]:check(spirv.get_stage_compile_error(stage).is_empty(),"shader compilation")
	return keep(rd.shader_create_from_spirv(spirv))
func prepare()->void:
	for factor:int in [1,2]:shaders.append(make_shader(factor))
	var vertex:=rd.vertex_format_create([]);vertex_array=keep(rd.vertex_array_create(3,vertex,[]))
	var format:=RDTextureFormat.new();format.width=8;format.height=8;format.format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	texture=keep(rd.texture_create(format,RDTextureView.new()));framebuffer=keep(rd.framebuffer_create([texture]))
	var blend:=RDPipelineColorBlendState.new();blend.attachments=[RDPipelineColorBlendStateAttachment.new()]
	for shader:RID in shaders:
		pipelines.append(keep(rd.render_pipeline_create(shader,rd.framebuffer_get_format(framebuffer),vertex,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,RDPipelineRasterizationState.new(),RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),blend)))
	for index:int in [0,2,3]:
		var alternatives:Array[RID]=[]
		for variant:int in 2:
			var value:=PackedFloat32Array([.05*(variant+1),.025*(variant+1),.0125*(variant+1),0.])
			var buffer:=keep(rd.uniform_buffer_create(16,value.to_byte_array()))
			var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER;uniform.binding=0;uniform.add_id(buffer)
			alternatives.append(keep(rd.uniform_set_create([uniform],shaders[0],index)))
		sets.append(alternatives)
func validate_queued_bindings()->void:
	# Keep all four binding histories visible after the recording calls return.
	# A full-screen overdraw-only check would only verify the final descriptor.
	var variants:Array=[Vector3i(0,0,0),Vector3i(0,1,0),Vector3i(1,1,1),Vector3i(0,0,1)]
	var scales:Array[int]=[3,4,7,4]
	var list:=rd.draw_list_begin(framebuffer,RenderingDevice.DRAW_CLEAR_COLOR_0,PackedColorArray([Color.BLACK]))
	rd.draw_list_bind_vertex_array(list,vertex_array)
	for tile:int in 4:
		var state:Vector3i=variants[tile]
		rd.draw_list_bind_render_pipeline(list,pipelines[state.z])
		rd.draw_list_bind_uniform_set(list,sets[0][state.x],0)
		rd.draw_list_bind_uniform_set(list,sets[1][0],2)
		rd.draw_list_bind_uniform_set(list,sets[2][state.y],3)
		rd.draw_list_enable_scissor(list,Rect2(tile*2,0,2,8))
		rd.draw_list_draw(list,false,1,3)
	rd.draw_list_end();rd.submit();rd.sync()
	var pixels:=Image.create_from_data(8,8,false,Image.FORMAT_RGBA8,rd.texture_get_data(texture,0))
	for tile:int in 4:
		var expected:=Color(.05*scales[tile],.025*scales[tile],.0125*scales[tile],1.)
		var correct:=true
		for y:int in 8:
			for x:int in range(tile*2,tile*2+2):
				var actual:=pixels.get_pixel(x,y)
				correct=correct and absf(actual.r-expected.r)<.005 and absf(actual.g-expected.g)<.005 and absf(actual.b-expected.b)<.005 and actual.a==1.
		check(correct,"queued sparse binding and pipeline history survives scratch reuse, tile "+str(tile))
func trial(mode:String,count:int,iteration:int)->void:
	var started:=Time.get_ticks_usec()
	var list:=rd.draw_list_begin(framebuffer,RenderingDevice.DRAW_CLEAR_COLOR_0,PackedColorArray([Color.BLACK]))
	rd.draw_list_bind_render_pipeline(list,pipelines[0]);rd.draw_list_bind_vertex_array(list,vertex_array)
	for i:int in 3:rd.draw_list_bind_uniform_set(list,sets[i][0],[0,2,3][i])
	var bindings:=3;var last_variant:=0;var last_pipeline:=0
	for i:int in count:
		if mode=="material":
			last_variant=i%2;rd.draw_list_bind_uniform_set(list,sets[2][last_variant],3);bindings+=1
		elif mode=="sparse":
			last_variant=i%2
			rd.draw_list_bind_uniform_set(list,sets[0][last_variant],0);rd.draw_list_bind_uniform_set(list,sets[2][last_variant],3);bindings+=2
		elif mode=="pipeline":
			last_pipeline=i%2;rd.draw_list_bind_render_pipeline(list,pipelines[last_pipeline])
		rd.draw_list_draw(list,false,1,3)
	rd.draw_list_end()
	var encoded:=Time.get_ticks_usec()
	rd.submit();var submitted:=Time.get_ticks_usec();rd.sync();var finished:=Time.get_ticks_usec()
	var pixels:=rd.texture_get_data(texture,0)
	var image:=Image.create_from_data(8,8,false,Image.FORMAT_RGBA8,pixels)
	var scale:=3.+last_pipeline
	if mode=="material":scale+=last_variant
	if mode=="sparse":scale+=2*last_variant
	var expected:=Color(.05*scale,.025*scale,.0125*scale,1.)
	var good:=pixels.size()==256
	for y:int in 8:
		for x:int in 8:
			var actual:=image.get_pixel(x,y)
			good=good and absf(actual.r-expected.r)<.005 and absf(actual.g-expected.g)<.005 and absf(actual.b-expected.b)<.005 and actual.a==1.
	check(good,"GPU pixels "+mode+" iteration "+str(iteration))
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(pixels)
	rows.append({"mode":mode,"draws":count,"binds":bindings,"iteration":iteration,"warmup":iteration==0,"encode_us":encoded-started,"submit_us":submitted-encoded,"sync_us":finished-submitted,"pixel_ok":good,"pixel_sha256":digest.finish().hex_encode()})
func run()->void:
	check(not output.is_empty() and DisplayServer.get_name()!="headless","output and real GPU")
	rd=RenderingServer.create_local_rendering_device();check(rd!=null,"local rendering device")
	if rd!=null:
		prepare()
		if failures.is_empty():
			validate_queued_bindings()
			for iteration:int in 6:
				for mode:String in ["reuse","material","sparse","pipeline"]:trial(mode,4096,iteration)
		for i:int in range(owned.size()-1,-1,-1):rd.free_rid(owned[i])
		owned.clear();rd.free()
	var result:={"checks":checks,"failures":failures,"rows":rows,"scope":"Local RD real GPU; equal draw/bind work; CPU encode includes GD calls; pipeline warmup excluded from measured rows; not map/FPS acceptance."}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DRAW_DESCRIPTOR_SCRATCH checks=",checks," failures=",failures.size());quit(1 if not failures.is_empty() else 0)
