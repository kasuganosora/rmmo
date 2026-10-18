extends SceneTree
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func timed_return()->void:
	var _scope:=Trace.method_scope("test.method.return")
	return
func timed_wait()->void:
	var _scope:=Trace.method_scope("test.method.await")
	await process_frame
func run()->void:
	Trace.start();Trace.methods_enabled=true
	timed_return();await timed_wait()
	# Await completion callbacks run before the suspended call's locals retire.
	# Observe after that signal stack unwinds, as the production monitor does.
	await process_frame
	var trace:=Trace.stop();Trace.methods_enabled=false
	var labels:Array=[]
	for row:Dictionary in trace.stats:labels.append(row.label)
	check(labels.has("test.method.return") and labels.has("test.method.await"),"method clocks close on early return and coroutine completion")
	if DisplayServer.get_name()=="headless":quit(0 if failures==0 else 1);return
	var original_taa:=root.use_taa;var original_msaa:=root.msaa_3d
	var loader:=Loader.new();root.add_child(loader);loader._prepare_startup_render_context()
	var viewport:SubViewport=loader._startup_viewport
	check(viewport!=null and viewport.own_world_3d and viewport.size==Vector2i(16,16),"2D loading uses a private minimal 3D render context")
	check(viewport.use_taa==original_taa and viewport.msaa_3d==original_msaa,"startup context matches real antialiasing features")
	check(viewport.find_children("*","MeshInstance3D",true,false).is_empty() and viewport.get_world_3d()!=root.get_world_3d(),"no map mesh, physics, actor or authored script enters the private world")
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	check(viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED and loader._startup_draw_count==2,"startup context parks after two warmup frames and adds no continuing draw work")
	check(viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)==0,"empty context draws no map or warmup ghost meshes")
	var weak_viewport:WeakRef=weakref(viewport);loader.free();viewport=null
	check(weak_viewport.get_ref()==null and root.find_children("LoadingRenderContext","SubViewport",true,false).is_empty(),"loader destruction releases the context and all of its rendering resources")
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	loader=Loader.new();root.add_child(loader);loader._prepare_startup_render_context()
	check(loader._startup_viewport==null,"an existing active 3D viewport needs no extra context")
	loader.free();camera.free()
	loader=Loader.new();loader.background_preload=true;root.add_child(loader);loader._prepare_startup_render_context()
	check(loader._startup_viewport==null,"background target preparation keeps its existing viewport ownership")
	loader.free()
	check(root.use_taa==original_taa and root.msaa_3d==original_msaa,"loading never changes the playable viewport quality settings")
	print("LOADING_RENDER_CONTEXT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
