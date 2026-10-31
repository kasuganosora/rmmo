extends "res://tools/test_map_decoded_record_retirement.gd"
## Reproduce the real late consumer: navigation donates its specs only AFTER
## map disposal tickets have drained. CPU metadata must follow this handoff.
const Nav=preload("res://scripts/world3d/world_navigation.gd")
func run()->void:
	load_input()
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	var service:=Retirement._service();service.set_process(false)
	var journal:=Journal.new();var map:=fixture(journal,true);root.add_child(map)
	var host:=Node.new();root.add_child(host)
	var nav:=Nav.new();host.add_child(nav);nav.set_process(false)
	install_sources(nav,map)
	var args:Array=[map,self]
	if not baseline:args.append(nav)
	Callable(Stream,"prepare_map_disposal").callv(args)
	service.set_process(false)
	check(nav._specs.size()==count,"permanent map preparation keeps the delayed navigation reader intact")
	map.free();map=null;args=[]
	var before_batches:int=int(service.profile.get("geometry_batches",0))
	var first:Dictionary=await drain(service)
	check(journal.freed==0,"draining map tickets cannot destroy navigation source Resources")
	check(int(service.profile.get("geometry_batches",0))==before_batches,"decoded metadata does not retire before the delayed navigation handoff")
	for i in 3:await process_frame
	check(nav._specs.size()==count,"navigation can still read sources after earlier tickets have drained")
	var watch:WeakRef=weakref(nav)
	var started:=Semaphore.new();var release:=Semaphore.new();var worker:=Thread.new()
	var worker_error:=worker.start(_wait_worker.bind(started,release))
	check(worker_error==OK,"navigation has a real pending background consumer")
	if worker_error==OK:started.wait();nav._face_worker=worker
	check(nav.retire_background("fixture_delayed_consumer"),"normal navigation retirement reparents without synchronous destruction")
	nav.set_process(false);nav._process(0.)
	check(service.pending.is_empty() and is_instance_valid(nav),"reparenting and live worker drain do not release the decoded metadata lease")
	release.post()
	while worker.is_alive():await process_frame
	nav._process(0.)
	service.set_process(false);nav=null
	for i in 3:
		await process_frame
		service.set_process(false)
	check(watch.get_ref()==null,"navigation itself is gone before releasing its donated owners")
	check(not service.pending.is_empty() and service.pending[0].kind=="private_array","navigation submits mixed source owners to MAIN first")
	check(not service.pending.is_empty() and service.pending.back().kind=="cpu_geometry","decoded metadata follows the late MAIN source ticket")
	var units_before:int=service.profile.private_values
	var second:Dictionary=await drain(service)
	check(journal.freed==count and journal.off_main==0,"navigation's last Resource owners die exactly once on main")
	check(int(service.profile.get("geometry_batches",0))==1,"decoded metadata is released once by the existing CPU lane")
	var result:={"checks":checks,"failures":failures,"baseline":baseline,"entries":count,"early_tickets":first,"navigation_tickets":second,"navigation_private_units":service.profile.private_values-units_before,"cpu_worker_us":service.profile.get("geometry_worker_us",0),"scope":"real navigation retirement ordering fixture, no map/FPS claim"}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	host.free();service.free()
	print("NAVIGATION_RECORD_RETIREMENT ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
func install_sources(nav:Node,map:Node)->void:
	nav.streaming_geometry=true
	nav._specs=map.get_meta("stream_by_id").values()
	nav._spec_ids=map.get_meta("stream_by_id").duplicate()
	nav._doors=[nav._specs[0]]
static func _wait_worker(started:Semaphore,release:Semaphore)->Dictionary:
	started.post();release.wait();return {}
