extends "res://tools/test_editor_native_admission_gpu.gd"
## Real native GPU resources and decoded PNGs exercise mixed-lane pressure.
## Private-desktop GPU only. The parent owns the already-tested HTTP helpers.
var _dispatch_lanes:Array=[]

class OwnedAudit extends Audit:
	var owner_key:String
	var owning_lease_present:Array=[]
	func released(kind:String)->void:
		var owner:RefCounted=ledger.get_ref() if OS.get_thread_caller_id()==OS.get_main_thread_id() else null
		owning_lease_present.append(owner!=null and owner._entries.has(owner_key))
		super.released(kind)

class Dispatches extends RefCounted:
	var starts:Array=[]
	func start(worker:Thread,task:Callable,queue:Node)->int:
		for key:String in queue.order:
			if queue.rows[key].state=="pending" and queue.ledger._entries.has(key):
				var states:Dictionary={}
				for other:String in queue.order:states[other]=queue.rows[other].state
				starts.append({"key":key,"lane":queue.rows[key].lane,"states":states,
					"jobs":queue.ledger.count(),"workers":queue.ledger.active_workers(),"bytes":queue.ledger.reserved_bytes})
				return worker.start(task,Thread.PRIORITY_LOW)
		return ERR_INVALID_DATA

static func read_pixels(path:String,expected_sha:String)->Dictionary:
	var bytes:=FileAccess.get_file_as_bytes(path)
	var pixels:=Image.new();var error:=pixels.load_png_from_buffer(bytes)
	if error!=OK or FileAccess.get_sha256(path)!=expected_sha:return {"error":ERR_FILE_CORRUPT}
	return {"error":OK,"images":{path:pixels},"source_sha":expected_sha}

func pixels_match(packet:Dictionary,path:String)->bool:
	var pixels:Variant=packet.get("images",{}).get(path)
	return pixels is Image and pixels.get_size()==Vector2i(512,512) and pixels.get_pixel(2,2).is_equal_approx(Color(.2,.4,.6,1))

func join_only(queue:Node,keys:Array)->void:
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		# An expired dispatch deadline joins at most one completed worker and
		# starts none. This deterministically retains real ready/held packets.
		queue._pump(Time.get_ticks_usec())
		if keys.all(func(key):return queue.is_ready(key)):return
		await process_frame
	check(false,"real mixed-lane workers join before fixture deadline")

func prepare_fixture_job(path:String,candidate:Dictionary)->Dictionary:
	Library._scenes.erase(path)
	var job:=Job.new();root.add_child(job)
	job._timings={"build":{"units":{}},"asset_lookahead":{"ready_on_consume":0,"native_retries":0,"native_retry_reasons":{},"consumed":0,"started":0,"start_failures":0,"peak_unconsumed":0,"compiled_hits":0,"compiled_misses":0}}
	job._model_candidates[path]=candidate.duplicate(true)
	var queue:=Queue.new();queue.lanes_enabled=true;queue.diagnostics_enabled=true;job.add_child(queue);job._preparation=queue
	var audit:=Audit.new();audit.ledger=weakref(queue.ledger)
	var key:="model:"+path
	_dispatch_lanes=[]
	queue.thread_starter=func(worker:Thread,task:Callable)->int:
		_dispatch_lanes.append(queue.rows[key].lane)
		return audit.start(worker,task,queue,key)
	var estimate:={"estimated_bytes":int(candidate.estimated_bytes),"exclusive":bool(candidate.exclusive),"stage":"compiled_read"}
	check(queue.enqueue(key,audit.read_native.bind(path,Paths.external_root(),candidate),estimate,"model"),"real model reader enters explicit model lane")
	return {"job":job,"queue":queue,"audit":audit,"key":key}

func mixed_lane_pressure(path:String,candidate:Dictionary,other_path:String,other_candidate:Dictionary)->void:
	var png:=temporary_directory.path_join("pixels.png")
	var pixels:=Image.create(512,512,false,Image.FORMAT_RGBA8);pixels.fill(Color(.2,.4,.6,1))
	check(pixels.save_png(png)==OK,"temporary real PNG saved for image lane")
	pixels=null
	var digest:=FileAccess.get_sha256(png)
	var queue:=Queue.new();queue.lanes_enabled=true;queue.diagnostics_enabled=true;root.add_child(queue);queue.set_process(false)
	var dispatches:=Dispatches.new();queue.thread_starter=dispatches.start.bind(queue)
	var image_estimate:={"estimated_bytes":8*1024*1024,"exclusive":false,"cpu_only":true,"stage":"pixels"}
	var model_estimate:={"estimated_bytes":int(candidate.estimated_bytes),"exclusive":bool(candidate.exclusive),"stage":"compiled_read"}
	var other_estimate:={"estimated_bytes":int(other_candidate.estimated_bytes),"exclusive":bool(other_candidate.exclusive),"stage":"compiled_read"}
	var first:=OwnedAudit.new();first.ledger=weakref(queue.ledger);first.owner_key="model:a"
	var second:=OwnedAudit.new();second.ledger=weakref(queue.ledger);second.owner_key="model:b"
	for key in ["texture:a","texture:b","texture:c"]:
		check(queue.enqueue(key,read_pixels.bind(png,digest),image_estimate,"texture"),"real PNG request enters texture lane: "+key)
	check(queue.enqueue("model:a",first.read_native.bind(path,Paths.external_root(),candidate),model_estimate,"model"),"first real PackedScene read enters model lane")
	check(queue.enqueue("model:b",second.read_native.bind(other_path,Paths.external_root(),other_candidate),other_estimate,"model"),"second distinct real PackedScene read enters model lane")
	queue._pump(Time.get_ticks_usec()+100000)
	await join_only(queue,["texture:a","texture:b"])
	var held:Dictionary=queue.acquire("texture:a")
	check(pixels_match(held,png) and pixels_match(queue.rows["texture:b"].packet,png),"ready and held texture packets contain actual decoded pixels")
	check(queue.ledger.reserved_bytes==2*image_estimate.estimated_bytes,"ready and held PNG packets both retain their complete byte leases")
	queue._pump(Time.get_ticks_usec()+100000)
	var model_starts:Array=dispatches.starts.filter(func(row):return row.lane=="model")
	check(model_starts.size()==2 and model_starts.all(func(row):return row.states["texture:a"]=="held" and row.states["texture:b"]=="ready"),"both native models start while two preceding texture results remain held and ready")
	check(queue.rows["texture:c"].state=="pending" and queue._lane_count("texture")==2 and queue._lane_count("model")==2,"third texture cannot monopolize the shared four-result window")
	await join_only(queue,["model:a","model:b"])
	check(first.alive() and second.alive() and queue.ledger.count()==4 and queue.ledger.active_workers()==0,"four real completed or held packets remain charged after joining workers")
	check(dispatches.starts.all(func(row):return row.jobs<=4 and row.workers<=2 and row.bytes<=queue.byte_limit),"every actual dispatch respects total result worker and byte limits")
	check(first.resources.any(func(row):return row.kind=="mesh") and first.resources.any(func(row):return row.kind=="texture"),"native speculation owns real mesh and renderer texture resources")
	var exclusive:Dictionary=image_estimate.duplicate();exclusive.exclusive=true
	check(queue.enqueue("texture:exclusive",read_pixels.bind(png,digest),exclusive,"texture"),"actual exclusive image demand queued behind speculative native packets")
	queue.demand("texture:exclusive");queue._pump(Time.get_ticks_usec()+100000)
	check(queue.metrics.preempted==0 and first.alive() and second.alive() and queue.rows["texture:exclusive"].state=="pending","held texture blocks exclusive admission without needlessly destroying any ready GPU results")
	queue.release("texture:a")
	check(held.is_empty(),"releasing held image clears consumer alias before freeing its credit")
	queue._pump(Time.get_ticks_usec()+100000)
	check(first.native_packet.is_empty() and second.native_packet.is_empty(),"exclusive demand clears all retired native packet aliases")
	check(first.charged_main_retirement() and second.charged_main_retirement(),"both speculative mesh material texture and PackedScene graphs retire on main while their leases are charged")
	check(not first.owning_lease_present.is_empty() and not second.owning_lease_present.is_empty() and first.owning_lease_present.all(func(value):return value) and second.owning_lease_present.all(func(value):return value),"each native resource destructor observes its own lease still present in the shared ledger")
	check(queue.metrics.preempted==3 and queue.rows["model:a"].state=="pending" and queue.rows["model:b"].state=="pending","exclusive demand retires exactly the three joined blockers and preserves replayable model tasks")
	await join_only(queue,["texture:exclusive"])
	var demand_packet:Dictionary=queue.acquire("texture:exclusive")
	check(pixels_match(demand_packet,png) and queue.ledger.count()==1,"exclusive demand publishes valid PNG pixels under its sole charged lease")
	queue.release("texture:exclusive");queue.cancel()
	check(demand_packet.is_empty() and queue.ledger.reserved_bytes==0,"final consume and cancellation leave no mixed-lane reservation or result alias")
	results.append({"mode":"mixed_lane_pressure","starts":dispatches.starts.duplicate(true),"first_native_releases":first.releases.duplicate(true),"second_native_releases":second.releases.duplicate(true),"queue":queue.snapshot()})
	queue.free();await process_frame

func http_case(path:String)->void:
	var observed:={"queue_seen":false,"all_lanes":true,"completed":false}
	var watch:=func()->void:
		if not is_instance_valid(editor):return
		var job:Node=editor._load_job
		if job==null:return
		if job.phase=="complete":observed.completed=observed.completed or job._timings.get("preparation",{}).get("lanes_enabled",false)
		if not is_instance_valid(job._preparation):return
		observed.queue_seen=true;observed.all_lanes=observed.all_lanes and job._preparation.lanes_enabled
	process_frame.connect(watch)
	await super.http_case(path)
	process_frame.disconnect(watch)
	check(observed.queue_seen and observed.all_lanes and observed.completed,"actual HTTP load queues use the enabled lane policy through successful completion")

func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Run via tools/run_godot_background.py with a GPU backend");quit(2);return
	Engine.max_fps=60;rpc_timeout_ms=30000
	create_timer(150).timeout.connect(func():push_error("EDITOR_PREPARATION_LANES_GPU timeout");quit(2))
	var original_native:bool=Job.native_model_footprints_enabled;var original_lanes:bool=Job.preparation_lanes_enabled
	var previous_precheck:bool=Native.source_precheck_enabled
	var require_default:bool="--require-lanes-default" in OS.get_cmdline_user_args()
	if require_default:check(original_lanes,"production lane policy is enabled by default")
	Job.native_model_footprints_enabled=true;Job.preparation_lanes_enabled=true;Native.source_precheck_enabled=false
	temporary_directory=Paths.cache_directory("preparation_lanes_gpu_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(temporary_directory)
	var path:=temporary_directory.path_join("fixture.glb");var changed:=temporary_directory.path_join("changed.glb")
	check(fixture(path,1,8,Color(.7,.2,.1)),"closed ordinary textured GLB exported")
	check(fixture(changed,4,2048,Color(.1,.6,.2)),"larger replacement GLB exported for raw retry")
	var original:=FileAccess.get_file_as_bytes(path);var replacement:=FileAccess.get_file_as_bytes(changed)
	check(Compiled.build(path).get("ok",false),"actual native PackedScene product compiled")
	check(Footprint.build(path).get("ok",false),"actual native resource footprint compiled")
	var candidate:=Footprint.candidate(path,Paths.external_root())
	check(not candidate.is_empty(),"temporary model has source-bound native candidate")
	if candidate.is_empty():quit(1);return
	var other_path:=temporary_directory.path_join("other.glb")
	check(fixture(other_path,2,8,Color(.2,.1,.7)),"distinct second model exported for concurrent native reads")
	check(Compiled.build(other_path).get("ok",false) and Footprint.build(other_path).get("ok",false),"distinct second native product and footprint compiled")
	var other_candidate:=Footprint.candidate(other_path,Paths.external_root())
	check(not other_candidate.is_empty() and other_candidate.get("product")!=candidate.product,"concurrent native tasks use independently identified derived products")
	if other_candidate.is_empty():quit(1);return
	await mixed_lane_pressure(path,candidate,other_path,other_candidate)
	check(put(path,replacement),"source replacement precedes frozen candidate dispatch")
	await direct_case(path,candidate,"source_retry",4,2048)
	check(_dispatch_lanes==["model","model"],"real native-to-raw retry preserves model lane across fresh admission")
	check(put(path,original),"temporary source restored before real HTTP editor load")
	await http_case(path)
	check(FileAccess.get_sha256(path)==candidate.source_sha and FileAccess.get_sha256(candidate.product)==candidate.payload_sha,"source and native product identities remain unchanged after mixed-lane and HTTP tests")
	check(FileAccess.get_sha256(other_path)==other_candidate.source_sha and FileAccess.get_sha256(other_candidate.product)==other_candidate.payload_sha,"second model source and product identities remain unchanged")
	Job.native_model_footprints_enabled=original_native;Job.preparation_lanes_enabled=original_lanes;Native.source_precheck_enabled=previous_precheck
	var report:={"passed":passed,"failures":failed,"fixture_directory":temporary_directory,"cases":results,"required_production_default":require_default,"original_lane_default":original_lanes}
	var output:=Paths.external_root().path_join("review_artifacts/editor_preparation_lanes_gpu_20261011.json")
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("EDITOR_PREPARATION_LANES_GPU passed=",passed," failures=",failed);quit(1 if failed else 0)
