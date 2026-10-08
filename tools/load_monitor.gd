extends RefCounted
const Trace=preload("res://scripts/world3d/load_trace.gd")
var tree:SceneTree
var started:=0
var epoch:=0.
var main_thread_id:=0
var samples:Array=[]
var frames:Array[float]=[]
var phase_frames:Dictionary={}
var _previous_phase:="startup"
var _sample_cost:Dictionary={"count":0,"total_us":0,"max_us":0}
var _render_started:=0
var _previous:=0
var _sample_at:=0
var _viewports:Array[Viewport]=[]
var active:=false

func start(value:SceneTree)->void:
	tree=value;started=Time.get_ticks_usec();epoch=Time.get_unix_time_from_system();main_thread_id=OS.get_thread_caller_id()
	_previous=started;_sample_at=started;active=true;Trace.start()
	RenderingServer.frame_pre_draw.connect(_before_draw)
	RenderingServer.frame_post_draw.connect(_after_draw)
	tree.node_added.connect(_node_added)
	_watch(tree.root)
	for node in tree.root.find_children("*","SubViewport",true,false):_watch(node)

func _node_added(node:Node)->void:
	if node is SubViewport:_watch(node)

func _before_draw()->void:
	if active:_render_started=Time.get_ticks_usec()

func _after_draw()->void:
	if active and _render_started>0:Trace.elapsed("monitor.render_frame_span",_render_started)

func _watch(viewport:Viewport)->void:
	if _viewports.has(viewport):return
	_viewports.append(viewport)
	# Profiling tools own these fresh viewports; measurement starts disabled.
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)

func frame(phase:String,details:Dictionary={})->void:
	if not active:return
	var now:=Time.get_ticks_usec()
	var interval:=(now-_previous)/1000.
	frames.append(interval)
	if not phase_frames.has(_previous_phase):phase_frames[_previous_phase]=[]
	phase_frames[_previous_phase].append(interval)
	_previous=now;_previous_phase=phase
	if now-_sample_at<200000:return
	_sample_at=now
	var viewports:Array=[]
	for viewport in _viewports:
		if not is_instance_valid(viewport):continue
		var rid:=viewport.get_viewport_rid()
		viewports.append({"path":str(viewport.get_path()),"cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(rid),"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(rid),"update_mode":viewport.render_target_update_mode if viewport is SubViewport else -1})
	var pipelines:Dictionary={}
	for name:String in ["PIPELINE_COMPILATIONS_CANVAS","PIPELINE_COMPILATIONS_MESH","PIPELINE_COMPILATIONS_SURFACE","PIPELINE_COMPILATIONS_DRAW","PIPELINE_COMPILATIONS_SPECIALIZATION"]:
		if ClassDB.class_has_integer_constant("Performance",name):pipelines[name]=Performance.get_monitor(ClassDB.class_get_integer_constant("Performance",name))
	samples.append({"ticks_us":now,"at_ms":(now-started)/1000.,"phase":phase,"details":details,"viewports":viewports,"render_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.,"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"render_buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"render_texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"pipelines":pipelines,"render_loop_enabled":RenderingServer.render_loop_enabled})
	var cost:=Time.get_ticks_usec()-now
	_sample_cost.count+=1;_sample_cost.total_us+=cost;_sample_cost.max_us=maxi(_sample_cost.max_us,cost)

func _percentiles(values:Array)->Dictionary:
	var sorted:=values.duplicate();sorted.sort()
	var result:Dictionary={}
	for p:int in [50,95,99]:result[str(p)]=sorted[mini(sorted.size()-1,int(ceil(sorted.size()*p/100.))-1)] if not sorted.is_empty() else 0.
	result.max=sorted[-1] if not sorted.is_empty() else 0.;result.count=values.size()
	return result

func finish()->Dictionary:
	active=false
	RenderingServer.frame_pre_draw.disconnect(_before_draw)
	RenderingServer.frame_post_draw.disconnect(_after_draw)
	tree.node_added.disconnect(_node_added)
	for viewport in _viewports:
		if is_instance_valid(viewport):RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),false)
	var phases:Dictionary={}
	for phase:String in phase_frames:phases[phase]=_percentiles(phase_frames[phase])
	return {"pid":OS.get_process_id(),"main_thread_id":main_thread_id,"start_ticks_us":started,"start_epoch_s":epoch,"span_ms":(Time.get_ticks_usec()-started)/1000.,"frame_count":frames.size(),"frame_percentiles_ms":_percentiles(frames),"phase_frame_percentiles_ms":phases,"sample_cost":_sample_cost,"samples":samples,"trace":Trace.stop(),"note":"Viewport times are the last rendered frame and may be stale while UPDATE_DISABLED; wall spans overlap. No GPU fences or OS wait reasons are measured."}
