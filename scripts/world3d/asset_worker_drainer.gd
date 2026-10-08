extends Node
## SceneTree-owned worker lifetime, independent of any map/service being freed.
## Normal cancellation never waits on a live GPU worker on the scene thread.
const NODE_NAME := "AssetWorkerDrainer"
var jobs: Array = []
var drained := 0
class CancelToken extends RefCounted:
	var mutex := Mutex.new()
	var cancelled := false
	func cancel() -> void:
		mutex.lock(); cancelled = true; mutex.unlock()
	func is_cancelled() -> bool:
		mutex.lock(); var value := cancelled; mutex.unlock(); return value

static func for_tree(tree: SceneTree) -> Node:
	var existing := tree.root.get_node_or_null(NODE_NAME)
	if existing != null: return existing
	var owner := new()
	owner.name = NODE_NAME
	owner.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(owner)
	return owner

func watch(worker: Thread, token: RefCounted) -> void:
	jobs.append({"worker":worker,"token":token,"abandoned":false})
	set_process(true)

func forget(worker: Thread) -> void:
	for i in range(jobs.size()-1,-1,-1):
		if jobs[i].worker == worker: jobs.remove_at(i)
	if jobs.is_empty(): set_process(false)

func abandon(worker: Thread) -> void:
	for job: Dictionary in jobs:
		if job.worker == worker:
			job.abandoned = true
			if job.token != null: job.token.cancel()
	set_process(true)

func _process(_delta: float) -> void:
	for i in range(jobs.size()-1,-1,-1):
		var job: Dictionary = jobs[i]
		if not job.abandoned or job.worker.is_alive(): continue
		_dispose_result(job.worker)
		jobs.remove_at(i); drained += 1
	if jobs.is_empty(): set_process(false)

static func _dispose_result(worker: Thread) -> void:
	if not worker.is_started(): return
	var result: Variant = worker.wait_to_finish()
	if result is Dictionary and is_instance_valid(result.get("scene")):
		dispose_scene(result.scene)

static func synchronize_transfer() -> void:
	# Joining a worker only joins CPU code. Its queued material/instance setup
	# must be executed before main-thread pack/free can destroy those same RIDs.
	# Do this on main, after the worker has returned; never on the GPU worker.
	RenderingServer.force_sync()

static func dispose_scene(scene: Node) -> void:
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
	if token != null: token.cancel()
	# Engine shutdown has no future process frames. Godot's force_sync maps to
	# RenderingServerDefault::sync: it flushes commands queued by other threads
	# on the main-render-thread backend. Never wait_to_finish while still alive.
	while worker.is_alive():
		RenderingServer.force_sync()
		OS.delay_msec(1)
	_dispose_result(worker)

func _exit_tree() -> void:
	for job: Dictionary in jobs:
		if job.token != null: job.token.cancel()
	for job: Dictionary in jobs: drain_shutdown(job.worker,job.token)
	jobs.clear()
