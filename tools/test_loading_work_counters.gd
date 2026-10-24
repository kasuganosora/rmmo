extends SceneTree
## Tiny in-memory geometry only. Checks diagnostic counts against known work;
## no map, native product, disk cache, or scheduling policy changes.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Cursor=preload("res://scripts/world3d/instance_spec_preparation.gd")
const Asset=preload("res://scripts/world3d/asset_instance_preparation.gd")
const Template=preload("res://scripts/world3d/asset_spec_template.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Collision=preload("res://scripts/world3d/stream_collision_preparer.gd")
const Terrain=preload("res://scripts/world3d/terrain_collision_preparer.gd")
const Prefetch=preload("res://scripts/world3d/collision_face_prefetch.gd")
const Bvh=preload("res://scripts/world3d/collision_bvh_preparation.gd")
var checks:=0
var failures:=0

class Queue extends "res://scripts/world3d/deferred_asset_loader.gd":
	var published_specs:=0
	var failed_instances:=0
	func _publication_discarded(item:Dictionary,_staged:Dictionary)->bool:return not _demanded_by_id.has(item.record.uuid)
	func _runtime_supports_ready(_uuid:String)->bool:return true
	func _collision_publication_status(_uuid:String)->Dictionary:return {}
	func _main_thread_budget_usec()->int:return 6000
	func _publish_items(_items:Array,specs:Array)->bool:published_specs+=specs.size();return true
	func _instance_failed(_uuid:String,_reason:String)->void:failed_instances+=1

class Document extends RefCounted:
	var load_paint_validation:Dictionary={}
	var load_texture_checks:Dictionary={}
	func _begin_asset_instance(_value:Dictionary,_prepared:Dictionary)->Dictionary:
		var holder:=Node3D.new();var model:=Node3D.new();holder.add_child(model)
		model.set_meta("extras",{"delivery_stage":"textured_repair_v2"})
		for i:int in 8:model.add_child(Node3D.new())
		return {"holder":holder,"model":model}
	func _namespace_asset_node(_node:Node,_uuid:String,_model:Node3D,_collision:String)->void:pass
	func _asset_components_ready(_holder:Node3D,_model:Node3D)->void:pass
	func _finish_asset_instance(holder:Node3D,_record:Dictionary)->Node3D:return holder
	func begin_asset_finish(holder:Node3D,record:Dictionary,nodes:Array[Node])->RefCounted:
		var finish:=preload("res://scripts/world3d/asset_finish_preparation.gd").new();finish.begin(self,holder,record,nodes);return finish

class Gate extends RefCounted:
	var semaphore:=Semaphore.new()
	func start(thread:Thread,task:Callable)->int:
		return thread.start(func():semaphore.wait();return task.call())

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func cpu_mesh(triangles:int=1)->Mesh:
	var faces:=PackedVector3Array()
	for i:int in triangles:faces.append_array(PackedVector3Array([Vector3(i,0,0),Vector3(i,0,1),Vector3(i+1,0,0)]))
	var cpu:=Cpu.new();cpu._collision_faces=faces;cpu.bounds=AABB(Vector3.ZERO,Vector3(triangles,1,1))
	return cpu

func graph(mesh_count:int)->Node3D:
	var holder:=Node3D.new();var mesh:=BoxMesh.new()
	for i:int in mesh_count:
		var node:=MeshInstance3D.new();node.name="part%d"%i;node.mesh=mesh;node.set_meta("extras",{"uuid":"part%d"%i})
		holder.add_child(node);node.add_child(Node3D.new())
	return holder

func cursor_counts()->void:
	for local:bool in [false,true]:
		var holder:=graph(32);var alive:WeakRef=weakref(holder);var cursor:=Cursor.new();cursor.begin(holder,local,0)
		check(not cursor.advance(1),"projection budget leaves diagnostic work private")
		check(cursor.profile.nodes_visited==0,"work totals are handed off only at completion/cancel")
		while not cursor.advance(1):pass
		check(cursor.profile.nodes_visited==65 and cursor.profile.nodes_freed==65 and cursor.profile.meshes_projected==32,"exact projection visits/explicit frees/meshes for local="+str(local))
		check(alive.get_ref()==null,"completed projection frees the known graph")
		cursor.advance(0);cursor.dispose()
		check(cursor.profile.nodes_visited==65 and cursor.profile.nodes_freed==65 and cursor.profile.subtree_free_calls==0,"completed no-op/dispose never recounts graph work")
	var partial:=Cursor.new();var holder:=graph(32);var alive:WeakRef=weakref(holder);partial.begin(holder,false,0);partial.advance(1)
	partial.dispose();partial.dispose()
	check(alive.get_ref()==null and partial.profile.nodes_visited>0 and partial.profile.nodes_visited<65 and partial.profile.subtree_free_calls==1,"cancel reports only visited nodes and one unknown-size subtree free")
	var asset:=Asset.new();asset.begin_from_source(Document.new(),{"uuid":"asset"})
	while not asset.advance(1):pass
	check(asset.profile.namespace_nodes_visited==9,"asset namespace visits exclude the unvisited holder")
	check(asset.profile.component_node_steps==27 and asset.profile.finish_nodes_visited==10 and asset.profile.finish_visuals_registered==0,"existing component and finish passes report real steps without rescanning")
	asset.take_holder().free();asset.dispose()
	check(asset.profile.namespace_nodes_visited==9 and asset.profile.subtree_free_calls==0,"normal asset handoff is not a cancelled subtree free")

func template_counts()->void:
	var cpu:=cpu_mesh();var rows:Array=[]
	for i:int in 33:
		rows.append({"name":"part%d"%i,"path":"part%d"%i,"parent":-1 if i==0 else 0,"local":Transform3D.IDENTITY,"extra":{"rmmo_light_socket":{"position":[0,0,0],"color":[1,1,1],"range":2.0,"energy":1.0,"flame":false,"indoor":false}} if i==0 else {},"mesh":null if i==0 else cpu,"cpu":cpu,"bounds":cpu.bounds,"overrides":[],"shadow":GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"owner_path":".","hinge_owner":i})
	var packed:=PackedScene.new();packed.set_meta(Template.META,{"rows":rows,"sockets":[{"node":0,"anchor":1}],"generic":false,"components":true})
	var record:={"uuid":"template","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
	var cursor:=Template.new();cursor.begin(packed,record,0)
	check(not cursor.advance(1),"template adaptation spans a bounded slice")
	while not cursor.advance(1):pass
	check(cursor.profile.rows_adapted==33 and cursor.profile.rows_projected==33 and cursor.profile.sockets_applied==1 and cursor.profile.meshes_projected==32,"template rows, real sockets and emitted meshes counted separately")
	var adopted:=Template.new();adopted.specs=cursor.specs;adopted.profile=cursor.profile.duplicate();adopted.phase=3
	adopted.advance(1);adopted.dispose()
	check(adopted.profile.rows_adapted==33 and adopted.profile.rows_projected==33,"accepted worker packet does not overwrite its counts with receiver zeros")
	var partial:=Template.new();partial.begin(packed,record,0);partial.advance(1);partial.dispose()
	check(partial.profile.rows_adapted>0 and partial.profile.rows_adapted<33 and partial.profile.rows_projected==0,"cancel preserves only performed template work")
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.set_process(false)
	for calls:int in [1,2]:
		var initial:Array=await loader._prepare_asset_specs(packed,record,0)
		check(initial.size()==32 and loader._profile.accepted_initial_template_rows_adapted==33*calls and loader._profile.accepted_initial_template_rows_projected==33*calls and loader._profile.accepted_initial_template_sockets_applied==calls and loader._profile.accepted_initial_template_meshes_projected==32*calls,"initial loader accepts each worker template profile exactly once: "+str(calls))
	loader.free()

func queue_counts()->void:
	var queue:=Queue.new();root.add_child(queue)
	var gone:={"path":"fixture","record":{"uuid":"gone"}};var live:={"path":"fixture","record":{"uuid":"live"}}
	queue._jobs.fixture={"accepted":true};queue._prepared_paths.fixture=true
	queue._demanded_by_id.live=live;queue._demanded_by_path.fixture=[gone,live];queue._demanded_rank.live=0
	check(queue._publication_ready()==[live],"real ready selector returns the eligible head")
	check(queue.profile.ready_scan_items==1 and queue.profile.ready_paths_checked==1 and queue.profile.ready_prefix_discard_checks==2 and queue.profile.ready_eligible_calls==1,"returned head count differs from actual prefix and eligible checks")
	queue._publication_ready()
	check(queue.profile.ready_selection_calls==2 and queue.profile.ready_prefix_discard_checks==3 and queue.profile.ready_eligible_calls==2,"repeated selection adds only work actually repeated")
	var cursor:=Cursor.new();cursor.begin(graph(32),false,0)
	var job:={"instance_preparation":{"uuid":"live","cursor":cursor,"phase":"spec","prefab_us":0,"instance_us":0,"prefab_parts_ms":null,"instance_parts_ms":null}}
	queue._advance_instance_specs(live,job,Time.get_ticks_usec(),1)
	check(job.has("instance_preparation") and int(queue.profile.get("instance_work_completed_stages",0))==0,"budgeted cursor is not counted complete early")
	while job.has("instance_preparation"):queue._advance_instance_specs(live,job,Time.get_ticks_usec(),1)
	check(queue.profile.instance_projection_nodes_visited==65 and queue.profile.instance_projection_nodes_freed==65 and queue.profile.instance_meshes_projected==32 and queue.profile.instance_work_completed_stages==1,"real completion hands off precise cursor work exactly once")
	var cancelled:=Cursor.new();cancelled.begin(graph(8),false,0);cancelled.advance(1)
	queue._jobs.fixture.instance_preparation={"uuid":"live","cursor":cancelled};queue._demanded_by_id.clear()
	queue._publication_ready();queue._publication_ready()
	check(queue.profile.instance_work_cancelled_stages==1 and queue.profile.instance_cancel_subtree_free_calls==1,"withdrawn demand accounts cancellation once, without a recount scan")
	var failed:=Node3D.new();failed.set_meta("missing_asset",true)
	check(queue._instance_error(failed,live) and queue.failed_instances==1 and queue.profile.instance_failed_holder_free_calls==1,"failed-holder subtree free has a separate counter")
	queue._jobs.clear();queue.free()

func collision_counts()->void:
	var cpu:=cpu_mesh();var collision:=Collision.new()
	var shape:Shape3D=collision._install_shape(cpu._collision_faces)
	check(collision.bvh_main_shapes==1 and collision.bvh_main_face_vertices==3,"ordinary main BVH counts installed face vertices")
	if Bvh.active():
		var packet:Dictionary=PhysicsServer3D.call(&"prepare_concave_shape_data",cpu._collision_faces,false)
		shape=collision._install_shape(cpu._collision_faces,packet)
		check(collision.bvh_worker_shapes==1 and collision.bvh_worker_face_vertices==3,"ordinary prepared BVH counts its actual install")
	shape=null;collision.free()
	var enabled:bool=Bvh.enabled;Bvh.enabled=false
	var terrain:=Terrain.new();var host:=Node3D.new();root.add_child(host)
	var large:=cpu_mesh(1025);var spec:={"uuid":"terrain","mesh":large,"ground_batch_record":{"terrain_mesh":{}},"transform":Transform3D.IDENTITY}
	check(not terrain.prepare(spec,host,1),"terrain two-slice geometry respects the install budget")
	check(terrain.bvh_main_installed_slices==1 and terrain.bvh_main_face_vertices==3072,"first slice counts only actual installed payload")
	while not terrain.prepare(spec,host,1):await process_frame
	check(terrain.bvh_main_installed_slices==2 and terrain.bvh_main_face_vertices==3075 and terrain.bvh_worker_slices==0,"completed fallback separates installs from prepared slice count")
	terrain.cancel()
	while not terrain.prepare(spec,host,1):await process_frame
	check(terrain.bvh_main_installed_slices==2 and terrain.bvh_main_face_vertices==3075,"cached terrain reuse does not count another BVH build")
	terrain.cancel();Bvh.enabled=enabled
	if Bvh.active():
		var worker_terrain:=Terrain.new();var fresh:=cpu_mesh(1025)
		var worker_spec:={"uuid":"worker_terrain","mesh":fresh,"ground_batch_record":{"terrain_mesh":{}},"transform":Transform3D.IDENTITY}
		while worker_terrain.bvh_worker_slices==0:worker_terrain.prepare(worker_spec,host,1);await process_frame
		check(worker_terrain.bvh_worker_slices==2 and worker_terrain.bvh_worker_installed_slices==1 and worker_terrain.bvh_worker_face_vertices==3072,"accepted worker slices and actually installed slices have distinct counts")
		worker_terrain.cancel()
		check(worker_terrain.bvh_worker_installed_slices==1 and worker_terrain.bvh_worker_face_vertices==3072,"cancelled prepared slice never becomes another install")
	host.free()

func settle(prefetch:RefCounted)->void:
	while prefetch._thread!=null:prefetch.poll();await process_frame
	prefetch.poll()

func prefetch_counts()->void:
	var cpu:=cpu_mesh();var row:={"source":cpu,"cpu":cpu,"basis":Basis.IDENTITY}
	var prefetch:=Prefetch.new()
	check(prefetch.request([row,row],self),"prefetch admits one deduplicated CPU source")
	await settle(prefetch)
	check(prefetch.submitted_face_vertices==3 and prefetch.prepared_face_vertices==3,"submitted and accepted face vertices do not count duplicate requests")
	prefetch.take(cpu,cpu,Basis.IDENTITY);prefetch.take(cpu,cpu,Basis.IDENTITY);prefetch.release(cpu,cpu,Basis.IDENTITY)
	check(prefetch.taken_face_vertices==3 and prefetch.discarded_ready_face_vertices==0,"taking a result twice cannot count the same payload twice")
	prefetch.request([row],self);await settle(prefetch);prefetch.request([],self)
	check(prefetch.discarded_ready_face_vertices==3,"obsolete ready output counts discarded face vertices")
	prefetch.request([row],self);await settle(prefetch);prefetch.cancel();prefetch.cancel()
	check(prefetch.discarded_ready_face_vertices==6,"cancelled ready output is discarded once")
	prefetch.thread_starter=func(_thread:Thread,_task:Callable)->int:return ERR_CANT_CREATE
	check(not prefetch.request([row],self) and prefetch.start_failed_face_vertices==3 and prefetch.submitted_face_vertices==9,"thread-start failure never counts as submitted work")
	var gate:=Gate.new();prefetch.thread_starter=gate.start
	check(prefetch.request([row],self),"inflight cancellation fixture owns a blocked worker")
	var worker:Thread=prefetch._thread;prefetch.cancel();gate.semaphore.post()
	while worker.is_started():prefetch.poll();await process_frame
	prefetch.poll()
	check(prefetch.cancelled_inflight_face_vertices==3 and prefetch.prepared_face_vertices==9 and prefetch.profile.reserved_bytes==0,"cancelled inflight input is separate from completed output and drains safely")
	prefetch.thread_starter=func(thread:Thread,_task:Callable)->int:return thread.start(func():return {"faces":{}})
	check(prefetch.request([row],self),"failed-result fixture is successfully submitted")
	await settle(prefetch)
	check(prefetch.submitted_face_vertices==15 and prefetch.failed_face_vertices==3 and prefetch.prepared_face_vertices==9,"invalid completed packet counts failed input, never successful preparation")
	prefetch.cancel()

func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	cursor_counts();await template_counts();queue_counts()
	await collision_counts();await prefetch_counts()
	print("LOADING_WORK_COUNTERS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
