extends SceneTree
## Isolated native I/O failure. Engine diagnostics from the deliberately missing
## private fixture are listed separately, never masked as a zero-error run.
const Product=preload("res://scripts/world3d/streamed_texture_product.gd")
var failures:Array[String]=[]
var report:Dictionary={"transitions":[]}
var folder:String
class Errors extends Logger:
	var mutex:=Mutex.new()
	var errors:Array[Dictionary]=[]
	func _log_error(function:String,file:String,line:int,code:String,rationale:String,_notify:bool,type:int,_backtraces:Array)->void:
		mutex.lock();errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":type});mutex.unlock()
	func snapshot()->Array[Dictionary]:mutex.lock();var result:=errors.duplicate();mutex.unlock();return result
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func used()->int:return int(Engine.get_singleton("TextureStreaming").call("get_memory_budget_bytes_used"))
func flush()->void:
	var streaming:=Engine.get_singleton("TextureStreaming");streaming.call("flush_texture_streaming");await streaming.flush_completed
func request(level:int)->void:
	var streaming:=Engine.get_singleton("TextureStreaming");streaming.call("set_min_lod_override",level);streaming.call("set_max_lod_override",level)
func tail(level:int)->int:
	var result:=0
	for mip:int in range(level,9):result+=(256>>mip)*(256>>mip)*4
	return result
func layout(texture:Texture2D)->Dictionary:
	var result:Dictionary={};var accept:=func(value:Dictionary):result.assign(value)
	RenderingServer.call_on_render_thread(func():
		var format:=RenderingServer.get_rendering_device().texture_get_format(RenderingServer.texture_get_rd_texture(texture.get_rid()))
		accept.call_deferred({"width":format.width,"height":format.height,"mipmaps":format.mipmaps}))
	while result.is_empty():await process_frame
	return result
func verify_level(texture:Texture2D,level:int,label:String)->void:
	var shape:=await layout(texture)
	var actual:int=int(texture.call("get_streaming_mip_level")) if texture.has_method("get_streaming_mip_level") else int(round(log(256./float(shape.width))/log(2.)))
	var row:={"label":label,"requested_mip":level,"actual_mip":actual,"actual_mip_source":"native_getter" if texture.has_method("get_streaming_mip_level") else "rd_dimensions","rd_layout":shape,"engine_budget_bytes":used(),"expected_bytes":tail(level)}
	report.transitions.append(row)
	check(actual==level and shape.width==(256>>level) and shape.height==(256>>level) and shape.mipmaps==9-level and used()==tail(level),label)
func reload_errors(errors:Array[Dictionary])->int:
	var count:=0
	for error:Dictionary in errors:
		if str(error.function).ends_with("texture_reload"):count+=1
	return count
func finish()->void:
	report.failures=failures;FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STREAMED_RELOAD_FAILURE ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	folder=str(ProjectSettings.get_setting("rmmo/content_root"));DirAccess.make_dir_recursive_absolute(folder)
	create_timer(35).timeout.connect(func():quit(2))
	var errors:=Errors.new();OS.add_logger(errors)
	ProjectSettings.set_setting("rendering/textures/streaming/min_lod",3);ProjectSettings.set_setting("rendering/textures/streaming/max_lod",3);request(3)
	var image:=Image.create(256,256,false,Image.FORMAT_RGBA8);image.fill(Color(.2,.6,.3));image.generate_mipmaps()
	var path:=folder.path_join("reload.stex");var held:=folder.path_join("reload.stex.held");var file:=FileAccess.open(path,FileAccess.WRITE)
	check(Product.write(file,image)==OK,"write native full-chain fixture");file.close();image=null
	var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D");check(texture.call("load",path)==OK,"load initial coarse mip")
	await flush();await verify_level(texture,3,"initial actual mip and declared-tail accounting agree")
	request(1);await flush();await flush();await verify_level(texture,1,"full chain upgrades to actual finer mip")
	request(4);await flush();await flush();await verify_level(texture,4,"full chain downgrades to actual coarser mip")
	# Isolate one explicit failed attempt from the normal 30ms feedback retry.
	# These are private-test-only signal changes, restored before retirement.
	var streaming:=Engine.get_singleton("TextureStreaming");var callbacks:Array[Dictionary]=[]
	for connection:Dictionary in RenderingServer.frame_post_draw.get_connections():
		if connection.callable.get_object()==streaming:
			callbacks.append(connection);RenderingServer.frame_post_draw.disconnect(connection.callable)
	check(not callbacks.is_empty(),"temporarily isolate automatic feedback for bounded failure test")
	if callbacks.is_empty():texture=null;OS.remove_logger(errors);finish();return
	for frame:int in 8:await process_frame;await RenderingServer.frame_post_draw
	await flush()
	check(DirAccess.rename_absolute(path,held)==OK,"temporarily withhold only the private fixture file")
	request(1);await flush()
	await create_timer(.12).timeout
	report.failed_reload_count=reload_errors(errors.snapshot())
	check(report.failed_reload_count==1,"one explicit failed reload does not immediately requeue an I/O loop")
	await verify_level(texture,4,"failed read preserves the old actual mip, RD layout and budget")
	check(DirAccess.rename_absolute(held,path)==OK,"restore the same private native file")
	await flush();await flush();await verify_level(texture,1,"later successful retry updates actual mip and budget")
	report.expected_diagnostics=errors.snapshot();var unexpected:Array[Dictionary]=[]
	for error:Dictionary in report.expected_diagnostics:
		if not (str(error.function).ends_with("_parse_header") or str(error.function).ends_with("_load_data") or str(error.function).ends_with("texture_reload")):unexpected.append(error)
	check(unexpected.is_empty() and reload_errors(errors.snapshot())==1,"only the documented private missing-file diagnostics occurred")
	report.unexpected_diagnostics=unexpected
	for connection:Dictionary in callbacks:RenderingServer.frame_post_draw.connect(connection.callable,int(connection.flags))
	var weak:WeakRef=weakref(texture);texture=null
	for frame:int in 4:await process_frame;await RenderingServer.frame_post_draw
	await flush();check(weak.get_ref()==null and used()==0,"native final owner retires after failed and successful reloads")
	OS.remove_logger(errors);finish()
