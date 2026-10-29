extends SceneTree
## Engine contract repro: ask for mip 8 of a 256px native file. A file with
## fewer declared levels must clamp both actual storage and budget to its end.
## The partial fixture deliberately stays at its last single-image mip; it
## does not exercise the separate Image partial-chain representation problem.
var failures:Array[String]=[]
var checks:=0
var report:Dictionary={"cases":[]}
var folder:String
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func write_fixture(path:String,levels:int)->void:
	var data:=PackedByteArray();var offsets:Array[int]=[];var sizes:Array[int]=[]
	for level:int in levels:
		var image:=Image.create(256>>level,256>>level,false,Image.FORMAT_RGBA8);image.fill(Color(.2,.6,.3))
		var bytes:=image.get_data();offsets.append(data.size());sizes.append(bytes.size());data.append_array(bytes)
	var header:=PackedByteArray();header.resize(44+8*levels);header[0]=71;header[1]=83;header[2]=84;header[3]=70
	var fields:=[1,256,256,data.size(),Image.FORMAT_RGBA8,levels-1]
	for index:int in fields.size():header.encode_u32(4+4*index,fields[index])
	for level:int in levels:header.encode_u32(28+8*level,offsets[level]);header.encode_u32(32+8*level,sizes[level])
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(header);file.store_buffer(data);file.close()
func engine_bytes()->int:return int(Engine.get_singleton("TextureStreaming").call("get_memory_budget_bytes_used"))
func flush()->void:
	var streaming:=Engine.get_singleton("TextureStreaming")
	streaming.call("flush_texture_streaming");await streaming.flush_completed
func rd_layout(texture:Texture2D)->Dictionary:
	var result:Dictionary={}
	var accept:=func(value:Dictionary):result.assign(value)
	RenderingServer.call_on_render_thread(func():
		var device:=RenderingServer.get_rendering_device()
		var format:=device.texture_get_format(RenderingServer.texture_get_rd_texture(texture.get_rid()))
		accept.call_deferred({"width":format.width,"height":format.height,"mipmaps":format.mipmaps,"format":format.format}))
	while result.is_empty():await process_frame
	return result
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	folder=str(ProjectSettings.get_setting("rmmo/content_root"));DirAccess.make_dir_recursive_absolute(folder)
	create_timer(40).timeout.connect(func():quit(2))
	var streaming:=Engine.get_singleton("TextureStreaming")
	ProjectSettings.set_setting("rendering/textures/streaming/min_lod",8);ProjectSettings.set_setting("rendering/textures/streaming/max_lod",8)
	streaming.call("set_min_lod_override",8);streaming.call("set_max_lod_override",8)
	for levels:int in [9,1,2]:
		var path:=folder.path_join("mips_%d.stex"%levels);write_fixture(path,levels)
		var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D")
		check(texture.call("load",path)==OK,"load declared %d-level native fixture"%levels)
		await flush();var layout:=await rd_layout(texture)
		var side:=256>>(levels-1);var expected:=side*side*4
		var row:={"declared_levels":levels,"requested_mip":8,"expected_resident_rgba8_bytes":expected,"engine_budget_bytes":engine_bytes(),"rd_layout":layout}
		report.cases.append(row);print("MIP_CASE ",JSON.stringify(row))
		check(layout.width==side and layout.height==side and layout.mipmaps==1,"actual RD allocation clamps to declared last mip (%d levels)"%levels)
		check(engine_bytes()==expected,"engine budget equals the actual declared resident bytes (%d levels)"%levels)
		var weak:WeakRef=weakref(texture);texture=null
		# The awaited RD probe's function state can own its argument until the
		# next frame. Drain those test-only aliases before testing final retirement.
		for frame:int in 4:await process_frame;await RenderingServer.frame_post_draw
		RenderingServer.force_sync();await flush()
		row.owner_alive_after_release=weak.get_ref()!=null;row.engine_budget_after_release=engine_bytes()
		check(engine_bytes()==0,"final native owner retires all budget (%d levels)"%levels)
	report.checks=checks;report.failures=failures
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STREAMED_MIP_BOUNDS ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
