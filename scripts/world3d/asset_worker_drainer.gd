extends Node
## SceneTree-owned worker lifetime, independent of any map/service being freed.
## Normal cancellation never waits on a live GPU worker on the scene thread.
const NODE_NAME := "AssetWorkerDrainer"
const FrameBudget=preload("res://scripts/world3d/frame_work_budget.gd")
var jobs: Array = []
var drained := 0
class CancelToken extends RefCounted:
	var mutex := Mutex.new()
	var cancelled := false
	var cancel_callback:=Callable() # CPU-only wakeup, installed before worker start.
	func cancel() -> void:
		mutex.lock();var first:bool=not cancelled;cancelled = true;var wake:Callable=cancel_callback;mutex.unlock()
		if first and wake.is_valid():wake.call()
	func is_cancelled() -> bool:
		mutex.lock(); var value := cancelled; mutex.unlock(); return value

static func for_tree(tree: SceneTree) -> Node:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer.for_tree") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var existing := tree.root.get_node_or_null(NODE_NAME)
	if existing != null: return existing
	var owner := new()
	owner.name = NODE_NAME
	owner.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(owner)
	return owner

func watch(worker: Thread, token: RefCounted) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer.watch") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	jobs.append({"worker":worker,"token":token,"abandoned":false})
	set_process(true)

func forget(worker: Thread) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer.forget") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	for i in range(jobs.size()-1,-1,-1):
		if jobs[i].worker == worker: jobs.remove_at(i)
	if jobs.is_empty(): set_process(false)

func abandon(worker: Thread) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer.abandon") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	for job: Dictionary in jobs:
		if job.worker == worker:
			job.abandoned = true
			if job.token != null: job.token.cancel()
	set_process(true)

func _process(_delta: float) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer._process") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	for i in range(jobs.size()-1,-1,-1):
		var job: Dictionary = jobs[i]
		if not job.abandoned or job.worker.is_alive(): continue
		if FrameBudget.allowance("retire",1000,false)<=0:break
		var began:=Time.get_ticks_usec()
		_dispose_result(job.worker,job.token)
		jobs.remove_at(i); drained += 1
		FrameBudget.charge("retire",began)
	if jobs.is_empty(): set_process(false)

static func _dispose_result(worker: Thread, token: RefCounted = null) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer._dispose_result") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not worker.is_started(): return
	var result: Variant = worker.wait_to_finish()
	# A parser can hand off a private PackedScene/GLTFState without a Node.
	# Finish its renderer commands before releasing the unconsumed resources.
	if result is Dictionary:dispose_result(result)
	else:synchronize_transfer()
	release_shared(token)
	# A detached map can no longer own the ledger. Its token retains only this
	# RefCounted ledger and its callback, never the map/queue being destroyed.
	if token!=null and token.has_meta("admission_release"):
		var release:Variant=token.get_meta("admission_release")
		token.remove_meta("admission_release")
		if release is Callable and release.is_valid():release.call()
	if token!=null and token.has_meta("admission_owner"):token.remove_meta("admission_owner")

static func release_shared(token:RefCounted)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer.release_shared") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Both normal consumption and detached-map disposal call this only after the
	# worker joined and every owned result alias was cleared on main.
	if token==null:return
	if token.has_meta("prefab_continuation_result"):
		var retained:Dictionary=token.get_meta("prefab_continuation_result");dispose_result(retained);token.remove_meta("prefab_continuation_result")
	if token.has_meta("prefab_shared_release"):
		var callback:Callable=token.get_meta("prefab_shared_release");token.remove_meta("prefab_shared_release")
		if callback.is_valid():callback.call()
	for key:String in ["prefab_shared_owner","prefab_texture_tickets","reuse_face_owners","reuse_template_owner"]:
		if token.has_meta(key):token.remove_meta(key)
	if token is CancelToken:token.cancel_callback=Callable()

static func dispose_result(result:Dictionary)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer.dispose_result") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Clear the packet itself, not just a caller's reference. Polling code and a
	# job can alias it; neither may retain native resources after budget release.
	# Only ownership fields recurse: records/index/author dictionaries are borrowed
	# data and must never be recursively cleared by the resource drainer.
	synchronize_transfer()
	_dispose_owned_packet(result,[])

static func _dispose_owned_packet(packet:Dictionary,seen:Array)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer._dispose_owned_packet") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	for previous:Variant in seen:
		if previous is Dictionary and is_same(previous,packet):return
	seen.append(packet)
	var scene:Variant=packet.get("scene")
	if is_instance_valid(scene) and scene is Node and not scene.is_inside_tree() and scene.get_parent()==null:dispose_scene(scene)
	for key:String in ["native_packet","private_preparation","prefab_texture_packet"]:
		_dispose_owned_value(packet.get(key),seen)
	_dispose_owned_value(packet.get("retained_resources"),seen)
	packet.clear()

static func _dispose_owned_value(value:Variant,seen:Array)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer._dispose_owned_value") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if value is Dictionary:_dispose_owned_packet(value,seen)
	elif value is Array:
		for previous:Variant in seen:
			if previous is Array and is_same(previous,value):return
		seen.append(value)
		while not value.is_empty():
			var item:Variant=value.pop_back()
			_dispose_owned_value(item,seen)
			if preload("res://scripts/world3d/load_trace.gd").enabled and item is Resource:
				var kind:String=item.get_class();var began:=Time.get_ticks_usec()
				item=null
				preload("res://scripts/world3d/load_trace.gd").elapsed("retirement.resource_release",began,{"class":kind})
			else:item=null
	elif is_instance_valid(value) and value is Node and not value.is_inside_tree() and value.get_parent()==null:dispose_scene(value)

static func synchronize_transfer() -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer.synchronize_transfer") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Joining a worker only joins CPU code. Its queued material/instance setup
	# must be executed before main-thread pack/free can destroy those same RIDs.
	# Do this on main, after the worker has returned; never on the GPU worker.
	RenderingServer.force_sync()

static func dispose_scene(scene: Node) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer.dispose_scene") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	synchronize_transfer()
	if not is_instance_valid(scene): return
	# MeshInstance3D's derived members (mesh/surface overrides) can drop their
	# last Resource references before GeometryInstance3D frees its render RID.
	# Keep all dependencies alive until every instance has been destroyed and
	# the corresponding renderer commands have completed.
	var retained: Array[Resource] = []
	_retain_visual_resources(scene,retained)
	scene.free()
	synchronize_transfer()
	retained.clear()

static func _retain_visual_resources(node: Node, retained: Array[Resource]) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer._retain_visual_resources") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if node is MeshInstance3D:
		if node.mesh != null: retained.append(node.mesh)
		if node.skin != null: retained.append(node.skin)
		for slot in node.get_surface_override_material_count():
			var material: Material = node.get_surface_override_material(slot)
			if material != null: retained.append(material)
	if node is GeometryInstance3D:
		if node.material_override != null: retained.append(node.material_override)
		if node.material_overlay != null: retained.append(node.material_overlay)
	for child in node.get_children(): _retain_visual_resources(child,retained)

static func drain_shutdown(worker: Thread, token: RefCounted = null) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer.drain_shutdown") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if token != null: token.cancel()
	# Engine shutdown has no future process frames. Godot's force_sync maps to
	# RenderingServerDefault::sync: it flushes commands queued by other threads
	# on the main-render-thread backend. Never wait_to_finish while still alive.
	while worker.is_alive():
		RenderingServer.force_sync()
		OS.delay_msec(1)
	_dispose_result(worker,token)

func _exit_tree() -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_worker_drainer._exit_tree") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	for job: Dictionary in jobs:
		if job.token != null: job.token.cancel()
	for job: Dictionary in jobs: drain_shutdown(job.worker,job.token)
	jobs.clear()
