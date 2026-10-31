extends "res://tools/test_draw_descriptor_scratch.gd"
## Real GPU workload for whole-list recording. Compare identical work/pixels
## with RMMO_SECONDARY_DRAW_LISTS=0/1/2/4; no engine default is changed.
var targets:Array[RID]=[]
var target_textures:Array[RID]=[]
var expected_draws:=0
var trace_output:=""
var dependency_pixel_sha:=""

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--trace="):trace_output=arg.trim_prefix("--trace=")
	run.call_deferred()

func prepare_targets()->void:
	targets.append(framebuffer);target_textures.append(texture)
	for index:int in range(1,8):
		var format:=RDTextureFormat.new();format.width=8;format.height=8;format.format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		format.usage_bits=RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		var image:=keep(rd.texture_create(format,RDTextureView.new()))
		target_textures.append(image);targets.append(keep(rd.framebuffer_create([image])))

func encode_target(index:int,count:int,iteration:int)->void:
	var list:=rd.draw_list_begin(targets[index],RenderingDevice.DRAW_CLEAR_COLOR_0,PackedColorArray([Color.BLACK]))
	rd.draw_list_bind_render_pipeline(list,pipelines[0]);rd.draw_list_bind_vertex_array(list,vertex_array)
	for i:int in 3:rd.draw_list_bind_uniform_set(list,sets[i][0],[0,2,3][i])
	for i:int in count:
		rd.draw_list_bind_uniform_set(list,sets[0][i%2],0)
		rd.draw_list_bind_uniform_set(list,sets[2][(i+index)%2],3)
		rd.draw_list_bind_render_pipeline(list,pipelines[((i>>4)+index)%2])
		rd.draw_list_draw(list,false,1,3)
	# All four histories remain visible after worker recording and submission.
	var variants:Array=[Vector3i(0,0,0),Vector3i(0,1,0),Vector3i(1,1,1),Vector3i(0,0,1)]
	for tile:int in 4:
		var state:Vector3i=variants[(tile+index+iteration)%4]
		rd.draw_list_bind_render_pipeline(list,pipelines[state.z])
		rd.draw_list_bind_uniform_set(list,sets[0][state.x],0)
		rd.draw_list_bind_uniform_set(list,sets[2][state.y],3)
		rd.draw_list_enable_scissor(list,Rect2(tile*2,0,2,8));rd.draw_list_draw(list,false,1,3)
	rd.draw_list_end();expected_draws+=count+4

func verify_target(index:int,iteration:int)->String:
	var bytes:=rd.texture_get_data(target_textures[index],0)
	var pixels:=Image.create_from_data(8,8,false,Image.FORMAT_RGBA8,bytes)
	var scales:Array[int]=[3,4,7,4];var good:=bytes.size()==256
	for tile:int in 4:
		var scale:int=scales[(tile+index+iteration)%4]
		var expected:=Color(.05*scale,.025*scale,.0125*scale,1.)
		for y:int in 8:
			for x:int in range(tile*2,tile*2+2):
				var actual:=pixels.get_pixel(x,y)
				good=good and absf(actual.r-expected.r)<.005 and absf(actual.g-expected.g)<.005 and absf(actual.b-expected.b)<.005 and actual.a==1.
	check(good,"all queued target pixels, target %d iteration %d"%[index,iteration])
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes)
	return digest.finish().hex_encode()

func batch(count:int,iteration:int)->void:
	# Explicit empty submissions exercise graph/device sequencing as well as
	# resetting the command pools used by the preceding real submission.
	rd.submit();rd.sync();rd.submit();rd.sync()
	var began:=Time.get_ticks_usec()
	for i:int in targets.size():encode_target(i,count,iteration)
	var encoded:=Time.get_ticks_usec();rd.submit();var submitted:=Time.get_ticks_usec();rd.sync();var finished:=Time.get_ticks_usec()
	var pixels:Array[String]=[]
	for i:int in targets.size():pixels.append(verify_target(i,iteration))
	rows.append({"iteration":iteration,"warmup":iteration==0,"lists":targets.size(),"draws":targets.size()*(count+4),"draws_per_list":count+4,"encode_us":encoded-began,"submit_us":submitted-encoded,"sync_us":finished-submitted,"pixel_sha256":pixels})

func dependent_target_chain()->void:
	var buffer:=keep(rd.uniform_buffer_create(16,PackedFloat32Array([.05,.025,.0125,0.]).to_byte_array()))
	var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER;uniform.binding=0;uniform.add_id(buffer)
	var uniform_set:=keep(rd.uniform_set_create([uniform],shaders[0],0))
	for tile:int in 4:
		# One shared UBO is rewritten between dependent passes. Later passes
		# must load/preserve the previous stripes, and each must see its own data.
		var factor:=float(tile+1)
		rd.buffer_update(buffer,0,16,PackedFloat32Array([.05*factor,.025*factor,.0125*factor,0.]).to_byte_array())
		var list:=rd.draw_list_begin(targets[0],RenderingDevice.DRAW_CLEAR_COLOR_0 if tile==0 else 0,PackedColorArray([Color.BLACK]))
		rd.draw_list_bind_render_pipeline(list,pipelines[0]);rd.draw_list_bind_vertex_array(list,vertex_array)
		rd.draw_list_bind_uniform_set(list,uniform_set,0);rd.draw_list_bind_uniform_set(list,sets[1][0],2);rd.draw_list_bind_uniform_set(list,sets[2][0],3)
		rd.draw_list_enable_scissor(list,Rect2(tile*2,0,2,8))
		for draw:int in 4096:rd.draw_list_draw(list,false,1,3)
		rd.draw_list_end();expected_draws+=4096
	rd.submit();rd.sync()
	var bytes:=rd.texture_get_data(target_textures[0],0);var pixels:=Image.create_from_data(8,8,false,Image.FORMAT_RGBA8,bytes)
	for tile:int in 4:
		var expected:=Color(.05*(tile+3),.025*(tile+3),.0125*(tile+3),1.);var good:=true
		for y:int in 8:
			for x:int in range(tile*2,tile*2+2):
				var actual:=pixels.get_pixel(x,y)
				good=good and absf(actual.r-expected.r)<.005 and absf(actual.g-expected.g)<.005 and absf(actual.b-expected.b)<.005 and actual.a==1.
		check(good,"dependent render passes retain prior stripes and ordered UBO writes, tile "+str(tile))
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes);dependency_pixel_sha=digest.finish().hex_encode()

func run()->void:
	check(not output.is_empty() and DisplayServer.get_name()!="headless","output and real GPU")
	rd=RenderingServer.create_local_rendering_device();check(rd!=null,"local rendering device")
	var trace:Dictionary={}
	if rd!=null:
		prepare();prepare_targets()
		if failures.is_empty():
			if not trace_output.is_empty():check(Performance.call("debug_trace_start",1048576,true)==OK,"native capture start")
			for iteration:int in 6:
				batch(4096,iteration)
				batch(16,iteration) # Small-list serial path, with identical bindings.
			dependent_target_chain()
			if not trace_output.is_empty():
				trace=Performance.call("debug_trace_stop");check(trace.dropped==0,"native trace has no drops")
				check(Performance.call("debug_trace_export",trace_output)==OK,"native capture export")
		for i:int in range(owned.size()-1,-1,-1):rd.free_rid(owned[i])
		owned.clear();rd.free()
	var result:={"checks":checks,"failures":failures,"rows":rows,"expected_draw_commands":expected_draws,"dependency_pixel_sha256":dependency_pixel_sha,"trace":trace,"requested_secondary_lists":OS.get_environment("RMMO_SECONDARY_DRAW_LISTS"),"scope":"Real local RD. Eight independent render targets, sparse descriptor and pipeline changes, per-target visible history, large and small lists, empty submissions, dependent passes with shared UBO updates, and resource disposal. Does not claim main-device multi-frame-ring coverage or map performance."}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("PARALLEL_DRAW_RECORDING checks=",checks," failures=",failures.size());quit(1 if not failures.is_empty() else 0)
