extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const SOURCE="D:/code/rmmo_runtime/cache/world3d/bridge_perf_20261006/map.gltf"
var _last_frame:=0
var _max_frame_us:=0
var _frame_count:=0

func sample_frame()->void:
	var now:=Time.get_ticks_usec()
	_max_frame_us=maxi(_max_frame_us,now-_last_frame);_last_frame=now;_frame_count+=1

class ProbeEditor:
	extends "res://scripts/world_editor/world_editor.gd"
	func _ready()->void:pass

class ProfileCache:
	extends "res://scripts/world_editor/picking_shape_cache.gd"
	var rows:Array=[]
	func shape_for(source:Mesh)->ConcavePolygonShape3D:
		var started:=Time.get_ticks_usec();var cpu:Mesh=Cpu.capture(source)
		var capture_ms:=(Time.get_ticks_usec()-started)/1000.
		var cached:bool=_entries.has(cpu.get_instance_id())
		started=Time.get_ticks_usec();var faces:PackedVector3Array=cpu.collision_faces()
		var expand_ms:=(Time.get_ticks_usec()-started)/1000.
		started=Time.get_ticks_usec();var result:=super.shape_for(source)
		rows.append({"source":source.resource_name,"surfaces":source.get_surface_count(),"vertices":faces.size(),"cache_hit":cached,"capture_ms":capture_ms,"expand_ms":expand_ms,"set_shape_ms":(Time.get_ticks_usec()-started)/1000.})
		return result

func _initialize()->void:call_deferred("run")
func run()->void:
	Engine.max_fps=60
	var args:=OS.get_cmdline_user_args();var uuid:String=args[0];var output:String=args[1]
	var parsed:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SOURCE));var record:Dictionary={}
	for node in parsed.nodes:
		for candidate in node.get("extras",{}).get("rmmo_records",[]):
			if candidate.uuid==uuid:record=candidate;break
	if record.is_empty():quit(1);return
	parsed.clear()
	var document=preload("res://scripts/world3d/world_document.gd").new()
	var started:=Time.get_ticks_usec()
	var visual:Node3D=document._asset(record) if record.kind=="asset" else document._mesh(record)
	var asset_ms:=(Time.get_ticks_usec()-started)/1000.
	var editor:=ProbeEditor.new();root.add_child(editor);editor.add_child(visual)
	var cache:=ProfileCache.new();editor._picking_shapes=cache
	await process_frame
	var sliced:Dictionary={};var job:Node
	started=Time.get_ticks_usec();_last_frame=started;process_frame.connect(sample_frame)
	if args.has("--sliced"):
		job=preload("res://scripts/world_editor/load_job.gd").new();editor.add_child(job);job.editor=editor
		job._timings={"build":{"units":{},"max_slice_ms":0.,"yields":0}}
		sliced=await job._add_record_bodies(visual,uuid,started,uuid)
	else:editor._add_bodies(visual)
	var elapsed_ms:=(Time.get_ticks_usec()-started)/1000.
	sample_frame();process_frame.disconnect(sample_frame)
	var result:={"uuid":uuid,"asset_path":record.get("asset_path",""),"asset_ms":asset_ms,"add_bodies_ms":elapsed_ms,"mesh_rows":cache.rows,"max_frame_ms":_max_frame_us/1000.,"yielded_frames":_frame_count-1}
	if job!=null:result.sliced_timings=job._timings;result.main_ms=elapsed_ms-sliced.wait_us/1000.
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("EDITOR_PICK_PROFILE ",JSON.stringify(result));editor.free();quit(0)
