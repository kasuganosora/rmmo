extends "res://tools/test_initial_native_cpu_preparation.gd"
## Actual native product/coordinator/prefetch discard. Private-desktop GPU only.
const Prefetch=preload("res://scripts/world3d/initial_model_prefetch.gd")
var discard_measurements:Array=[]

class Observer extends RefCounted:
	var mutex:=Mutex.new()
	var objects:Array[WeakRef]=[]
	var kinds:Array[String]=[]
	var geometry_owner_bytes:=0
	var rid_owners:=0
	var prepared:=false
	var packet:Dictionary={}
	func observe(scene:Node,packed:PackedScene,capture:Dictionary)->void:
		var refs:Array[WeakRef]=[weakref(scene),weakref(packed)]
		var labels:Array[String]=["scene","packed"]
		var seen:Dictionary={}
		var render_owners:=0
		for node:MeshInstance3D in preload("res://scripts/world3d/surface_materials.gd").meshes(scene):
			refs.append(weakref(node));labels.append("visual")
			if node.get_instance().is_valid():render_owners+=1
			var mesh:Mesh=node.mesh
			if seen.has(mesh.get_instance_id()):continue
			seen[mesh.get_instance_id()]=true
			refs.append(weakref(mesh));labels.append("mesh")
			if mesh.get_rid().is_valid():render_owners+=1
			var cpu:Mesh=mesh.get_meta("ground_cpu_cache")
			refs.append(weakref(cpu));labels.append("cpu")
			for material:Material in cpu.materials:
				if material==null or seen.has(material.get_instance_id()):continue
				seen[material.get_instance_id()]=true
				refs.append(weakref(material));labels.append("material")
				if material.get_rid().is_valid():render_owners+=1
		mutex.lock()
		objects=refs;kinds=labels;rid_owners=render_owners
		geometry_owner_bytes=int(capture.capture_bytes)+int(capture.face_bytes)
		prepared=true;mutex.unlock()
	func ready()->bool:
		mutex.lock();var result:=prepared;mutex.unlock();return result
	func retain_alias(value:Dictionary)->void:
		mutex.lock();packet=value;mutex.unlock()
	func alive()->int:
		var count:=0
		for value:WeakRef in objects:
			if value.get_ref()!=null:count+=1
		return count
	func live_kinds()->Array:
		var result:Array=[]
		for i:int in objects.size():
			if objects[i].get_ref()!=null:result.append(kinds[i])
		return result

class ObservedPreparation extends "res://scripts/world3d/model_parse_preparation.gd":
	var observer:Observer
	var hold_prepared:=false
	var release_prepared:=Semaphore.new()
	func _prepare_initial_native(packed:PackedScene,path:String)->Dictionary:
		var result:=super._prepare_initial_native(packed,path)
		if result.get("scene") is Node:
			observer.observe(result.scene,packed,result.capture)
			if hold_prepared:release_prepared.wait()
		return result
	func run(paths:Array,parser:Callable=Callable(),worker_limit:int=2,thread_starter:Callable=Callable(),content_root:String="",verified_sources:Dictionary={})->Dictionary:
		var result:=super.run(paths,parser,worker_limit,thread_starter,content_root,verified_sources)
		observer.retain_alias(result)
		return result

func wait_ready(observer:Observer)->bool:
	var deadline:=Time.get_ticks_msec()+10000
	while not observer.ready() and Time.get_ticks_msec()<deadline:
		Pump.pump(1000)
		await process_frame
	return observer.ready()
func wait_packet(helper:RefCounted)->bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		helper._mutex.lock();var ready:bool=not helper._discarded.is_empty();helper._mutex.unlock()
		if ready:return true
		Pump.pump(1000)
		await process_frame
	return false
func finish_caller(worker:Thread)->Variant:
	var deadline:=Time.get_ticks_msec()+10000
	while worker.is_alive() and Time.get_ticks_msec()<deadline:
		Pump.pump(1000)
		await process_frame
	check(not worker.is_alive(),"parser caller completes")
	if worker.is_alive():quit(2);return null
	return worker.wait_to_finish()
func finish_retirement()->bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		var service:=root.get_node_or_null("ResourceRetirement")
		if service==null or (service.pending.is_empty() and service.known.is_empty()):return true
		await process_frame
	return false

func discard_case(row:Dictionary,mode:String)->void:
	var observer:=Observer.new()
	var controller:=ObservedPreparation.new();controller.observer=observer
	controller.require_native_products=true;controller.prepare_static_scenes=true
	controller.static_scene_paths={row.path:row.metadata}
	controller.hold_prepared=mode=="cancel"
	var helper:=Prefetch.new()
	check(helper.start([row.path,row.path],controller,2,directory),mode+": real coordinator starts with duplicate hints")
	check(await wait_ready(observer),mode+": worker owns real native scene, CPU geometry and renderer owners")
	if not observer.ready():controller.release_prepared.post();helper.cancel();quit(2);return
	check(observer.alive()==observer.objects.size() and observer.rid_owners>0 and observer.geometry_owner_bytes>0,mode+": every observed native/CPU/RID owner is live before discard")
	if mode=="cancel":helper.cancel();controller.release_prepared.post()
	var caller:=Thread.new()
	check(caller.start(helper.take.bind([row.path+"_different"]) if mode in ["mismatch","cancel_ack"] else helper.abandon)==OK,mode+": actual parser rejection starts")
	check(await wait_packet(helper),mode+": joined packet reaches actual discard quarantine")
	var packet:Dictionary=observer.packet
	check(packet.get("unique_count",0)==1 and packet.get("threads_started",0)==1 and packet.get("threads_joined",0)==1,mode+": duplicate hints did not create extra work")
	check(packet.get("inflight_reserved_at_return",-1)==0 and packet.get("inflight_jobs_at_return",-1)==0 and packet.get("result_resident_estimate_bytes",0)==row.budget,mode+": completed ledger is empty while full resident estimate stays in the owned packet")
	check(packet.get("entries",[]).size()==1 and packet.get("retained_resources",[]).size()==1 and is_same(packet.entries[0],packet.retained_resources[0]),mode+": real coordinator mirrors entries through the recursive ownership field")
	check(observer.alive()==observer.objects.size(),mode+": quarantine has not destroyed scene or resource owners early")
	if mode in ["mismatch","cancel_ack"]:check(caller.is_alive(),mode+": replacement is blocked until main disposal acknowledgement")
	if mode=="cancel_ack":
		helper.cancel()
		await finish_caller(caller)
		check(observer.alive()==observer.objects.size(),mode+": shutdown escape preserves packet until final main drain")
	elif mode not in ["mismatch"]:await finish_caller(caller)
	var released_before:int=helper._released
	helper.drain_discarded()
	if mode=="mismatch":
		var result:Variant=await finish_caller(caller)
		check(result is Dictionary and not result.get("accepted",true),mode+": no rejected graph reaches replacement parser")
	check(observer.alive()==0,mode+": scene, native mesh/material/PackedScene and CPU owners all expire after renderer fences")
	check(packet.is_empty() and observer.packet.is_empty(),mode+": every aliased result loses its resident ownership and byte claims")
	check(helper._released==released_before+1 and helper._discarded.is_empty(),mode+": exactly one packet is acknowledged after disposal")
	check(await finish_retirement(),mode+": CPU geometry retirement finishes with no queued payload")
	var after:int=helper._released
	helper.drain_discarded()
	check(helper._released==after and observer.alive()==0,mode+": repeated drain does not free or acknowledge twice")
	discard_measurements.append({"mode":mode,"observed_objects":observer.objects.size(),"rid_owners_before":observer.rid_owners,"remaining_objects":observer.alive(),"remaining_kinds":observer.live_kinds(),"geometry_payload_owner_bytes_before":observer.geometry_owner_bytes,"resident_estimate_before":row.budget,"packet_cleared":packet.is_empty(),"acknowledgements":helper._released-released_before,"note":"RID-owning Objects expired after renderer fences; not a measured driver allocation/VRAM count"})
	# A failed assertion must not contaminate subsequent cases or engine exit.
	for i:int in observer.objects.size():
		if observer.kinds[i]=="scene" and observer.objects[i].get_ref()!=null:Drainer.dispose_scene(observer.objects[i].get_ref())
	packet.clear();observer.packet.clear();controller.fallback_gate=Callable()

func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-root="):directory=arg.trim_prefix("--test-root=").replace("\\","/").simplify_path()
	if directory.is_empty() or not Paths.allowed(directory,"D:/code/rmmo_runtime/review_artifacts") or directory=="D:/code/rmmo_runtime/review_artifacts":quit(2);return
	if DisplayServer.get_name()=="headless":check(false,"test requires renderer owners on the private desktop");quit(1);return
	DirAccess.make_dir_recursive_absolute(directory)
	Drainer.for_tree(self)
	Preparation.initial_scene_preparation_enabled=true
	Preparation.initial_native_cpu_preparation_enabled=true
	var row:=product("safe")
	for mode:String in ["mismatch","cancel","abandon","cancel_ack"]:await discard_case(row,mode)
	check(not Pump.active() and preload("res://scripts/world3d/mesh_readback_batch.gd").snapshot().pending==0,"all discarded transactions leave no renderer pump/readback jobs")
	write_json(directory.path_join("result.json"),{"checks":checks,"failed":failed,"measurements":discard_measurements})
	print("INITIAL_NATIVE_PREFETCH_DISCARD_FINISHED checks=",checks," failures=",failed)
	quit(1 if failed else 0)
