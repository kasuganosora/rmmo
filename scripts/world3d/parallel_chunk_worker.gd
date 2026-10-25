extends RefCounted
## Main-thread-owned join handle for two admitted CPU tasks. The existing job
## owns the combined byte lease, cancellation token and shared image consumer.
## Each joined half gives back its execution slot immediately; neither half
## releases retained bytes or shared owners before the complete handoff.
var admission:RefCounted
var path:String
var pixels:Callable
var _geometry:=Thread.new()
var _pixels:=Thread.new()
var _geometry_result:Dictionary={}
var _pixel_result:Dictionary={}
var _started:=false
var _geometry_done:=false
var _pixels_done:=false
var _begin_us:=0

func start(task:Callable)->int:
	_begin_us=Time.get_ticks_usec()
	var error:=_start_thread(_geometry,_run.bind(task))
	if error!=OK:
		admission.finish_worker_slot(path);return error
	_started=true
	error=_start_thread(_pixels,_run.bind(pixels))
	if error!=OK:
		_pixel_result={"error":"Unable to start admitted texture worker","cancelled":false}
		_pixels_done=true;admission.finish_worker_slot(path)
	return OK

func _start_thread(worker:Thread,task:Callable)->int:return worker.start(task)

static func _run(task:Callable)->Dictionary:
	var began:=Time.get_ticks_usec()
	var result:Variant=task.call()
	if not result is Dictionary:result={"error":"CPU preparation returned no packet","cancelled":false}
	result.parallel_start_us=began;result.parallel_end_us=Time.get_ticks_usec()
	return result

func is_started()->bool:return _started

func is_alive()->bool:
	if not _started:return false
	if not _geometry_done and not _geometry.is_alive():
		_geometry_result=_geometry.wait_to_finish();_geometry_done=true;admission.finish_worker_slot(path)
	if not _pixels_done and not _pixels.is_alive():
		_pixel_result=_pixels.wait_to_finish();_pixels_done=true;admission.finish_worker_slot(path)
	return not _geometry_done or not _pixels_done

func wait_to_finish()->Dictionary:
	# All callers use the same nonblocking is_alive gate as ordinary Thread.
	assert(_started and not is_alive())
	_started=false
	var result:Dictionary=_geometry_result
	var ends:=maxi(int(result.get("parallel_end_us",0)),int(_pixel_result.get("parallel_end_us",0)))
	var overlap:=maxi(0,mini(int(result.get("parallel_end_us",0)),int(_pixel_result.get("parallel_end_us",0)))-maxi(int(result.get("parallel_start_us",0)),int(_pixel_result.get("parallel_start_us",0))))
	result.parallel_cpu={"geometry_us":int(result.get("parallel_end_us",0))-int(result.get("parallel_start_us",0)),"pixels_us":int(_pixel_result.get("parallel_end_us",0))-int(_pixel_result.get("parallel_start_us",0)),"overlap_us":overlap}
	result.elapsed_us=maxi(0,ends-_begin_us)
	if result.has("audit_worker_start_us"):
		result.audit_worker_start_us=mini(int(result.get("parallel_start_us",_begin_us)),int(_pixel_result.get("parallel_start_us",_begin_us)))
		result.audit_worker_end_us=ends
	if str(result.get("error","")).is_empty():
		result.prefab_texture_packet=_pixel_result;result.waiting_pixels=_pixel_result.get("waiting_pixels",false)
		result.get("read_profile",{}).prefab_textures=_pixel_result.get("profile",{})
		result.error=_pixel_result.get("error","")
		for field:String in ["cancelled","retry_pixels","source_revisions"]:
			if _pixel_result.has(field):result[field]=_pixel_result[field]
		if not result.error.is_empty():result.reference_failure=true
	else:_pixel_result.clear()
	_geometry_result={};_pixel_result={};pixels=Callable()
	return result
