extends Node
## MockServer autoload stand-in. The authoritative server's script graph (~330
## scripts) and its start map pack are prepared on a dedicated thread, then this
## same node becomes the server, so its name, path and every cached reference stay
## valid. Game entry and main-loop scripts declaring MOCK_SERVER_BACKGROUND install
## once the thread is done; other --script main loops keep the old autoload order
## and install when this node becomes ready. Earlier server access joins through
## require() (Net.server()); call_when_ready() defers optional notices.
##
## GDScriptCache holds one lock for a whole script reload including its unresolved
## dependencies, so the thread compiles the graph leaves-first, one script per lock
## hold, and yields between scripts to let main-thread loads interleave.

const SERVER_PATH := "res://scripts/net/mock_server.gd"
const PREPARATION := &"mock_server_preparation"
const BACKGROUND_OPT_IN := "MOCK_SERVER_BACKGROUND"
const PREPARED_START_PACK := &"mock_server_prepared_start_pack"
const YIELD_USEC := 50
const DISABLE_ARGUMENT := "--without-mock-server"

class Preparation extends RefCounted:
	var thread := Thread.new()
	var pack_requested := Semaphore.new()
	var provided := false
	var pack_ref := ""
	var pack_dir := ""
	var server_script: Script
	var pack: RefCounted
	var pending: Array = []
	var profile := {}


func _init() -> void:
	if DISABLE_ARGUMENT in OS.get_cmdline_user_args():
		# Performance probes measure the client alone; the node stays an inert host.
		set_meta(&"mock_server_disabled", true)
		return
	var job := Preparation.new()
	job.profile = {"started_us": Time.get_ticks_usec(), "background": _background()}
	set_meta(PREPARATION, job)
	if job.profile.background:
		job.thread.start(Callable(get_script(), "_prepare").bind(job))
	else:
		# Emitted after this _ready returns and before the next autoload's, i.e. where
		# the old server autoload became ready. No frame of this instance is active.
		# This compatibility path is synchronous: loading on a worker and then
		# busy-waiting here deadlocks shader includes whose changed connections
		# must be attached by the main MessageQueue before the worker can return.
		connect(&"ready", Callable(get_script(), "_install").bind(self), CONNECT_ONE_SHOT)


func _ready() -> void:
	_provide_start_pack(self)


func _process(_delta: float) -> void:
	var job: Preparation = get_meta(PREPARATION) if has_meta(PREPARATION) else null
	if job != null and not job.thread.is_alive():
		set_process(false)
		Callable(get_script(), "_install").call_deferred(self)


## Install the server now if it is still being prepared (blocks until ready).
static func require(node: Node) -> void:
	if node != null and node.has_meta(PREPARATION):
		_install(node)


## Call method on the server now, or right after installation if still preparing.
static func call_when_ready(node: Node, method: StringName, args: Array) -> void:
	var job: Preparation = node.get_meta(PREPARATION) if node != null and node.has_meta(PREPARATION) else null
	if job != null:
		job.pending.append([method, args])
	elif node != null and node.has_method(method):
		node.callv(method, args)


## Preparation timings of the installed server (empty before installation).
static func profile_of(node: Node) -> Dictionary:
	return node.get_meta(&"mock_server_preparation_profile", {}) if node != null else {}


static func _background() -> bool:
	var script: Script = Engine.get_main_loop().get_script() if Engine.get_main_loop() != null else null
	if script == null:
		return true
	while script != null:
		if script.get_script_constant_map().has(BACKGROUND_OPT_IN):
			return true
		script = script.get_base_script()
	return false


static func _provide_start_pack(node: Node) -> void:
	var job: Preparation = node.get_meta(PREPARATION) if node.has_meta(PREPARATION) else null
	if job == null or job.provided:
		return
	job.provided = true
	var am: Node = Engine.get_main_loop().root.get_node_or_null("AssetManager")
	if am != null and am.has_method("start_map_pack_ref"):
		job.pack_ref = str(am.start_map_pack_ref())
		job.pack_dir = str(am.resolve_map_pack_path(job.pack_ref)) if am.has_method("resolve_map_pack_path") else ""
	job.pack_requested.post()


static func _prepare(job: Preparation) -> void:
	var began := Time.get_ticks_usec()
	var order := _compile_order(SERVER_PATH)
	job.profile.scan_us = Time.get_ticks_usec() - began
	for path: String in order:
		load(path)
		if job.profile.background:OS.delay_usec(YIELD_USEC)
	job.server_script = load(SERVER_PATH)
	job.profile.scripts = order.size()
	job.profile.compile_us = Time.get_ticks_usec() - began
	job.pack_requested.wait()
	began = Time.get_ticks_usec()
	if not job.pack_ref.is_empty():
		var Pack: Script = load("res://scripts/map/tilemap_pack.gd")
		job.pack = Pack.load_pack(Pack.choose_pack_dir(job.pack_ref, job.pack_dir), "", true)
	job.profile.pack_us = Time.get_ticks_usec() - began
	job.profile.finished_us = Time.get_ticks_usec()


## Post-order of the preload graph below root (root last): exactly the scripts the
## root's compilation pulls in. Runtime load() calls stay lazy. Exported builds
## ship no .gd sources, so the order degrades to the root alone.
static func _compile_order(root: String) -> PackedStringArray:
	var reference := RegEx.create_from_string("preload\\(\\s*\"(res://[^\"]+\\.gd)\"")
	var order := PackedStringArray()
	var state := {}
	var stack: Array = [[root, false]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var path: String = top[0]
		if top[1]:
			order.append(path)
			continue
		if state.has(path):
			continue
		state[path] = true
		stack.append([path, true])
		for found: RegExMatch in reference.search_all(FileAccess.get_file_as_string(path)):
			var dependency := found.get_string(1)
			if not state.has(dependency) and FileAccess.file_exists(dependency):
				stack.append([dependency, false])
	return order


static func _install(node: Node) -> void:
	var job: Preparation = node.get_meta(PREPARATION) if node.has_meta(PREPARATION) else null
	if job == null:
		return
	var waited := Time.get_ticks_usec()
	_provide_start_pack(node)
	if not job.thread.is_started():
		_prepare(job)
	else:
		# An early synchronous Net.server() can arrive before the event loop.
		# ResourceLoader's native wait services deferred resource connections;
		# a plain Thread join/renderer sync cannot do that. Join the same cached
		# script graph through that API, then wait for the detached CPU pack work.
		var _progress_owner: Resource
		if job.thread.is_alive() and ResourceLoader.load_threaded_request(SERVER_PATH,"Script")==OK:
			_progress_owner=ResourceLoader.load_threaded_get(SERVER_PATH)
		while job.thread.is_alive():
			# Loading-thread renderer calls may wait on main-thread command flushes.
			RenderingServer.force_sync()
			OS.delay_usec(200)
		job.thread.wait_to_finish()
	job.profile.install_wait_us = Time.get_ticks_usec() - waited
	node.remove_meta(PREPARATION)
	var am: Node = Engine.get_main_loop().root.get_node_or_null("AssetManager")
	if job.pack != null and am != null and am.has_method("start_map_pack_ref") and str(am.start_map_pack_ref()) == job.pack_ref:
		job.pack.attach_detached(am)
		node.set_meta(PREPARED_START_PACK, job.pack)
	var was_ready := node.is_node_ready()
	var began := Time.get_ticks_usec()
	node.set_script(job.server_script if job.server_script != null else load(SERVER_PATH))
	if was_ready:
		node._ready()
		node.set_process(node.has_method("_process"))
	job.profile.install_us = Time.get_ticks_usec() - began
	job.profile.installed_us = Time.get_ticks_usec()
	node.set_meta(&"mock_server_preparation_profile", job.profile)
	for row: Array in job.pending:
		if node.has_method(row[0]):
			node.callv(row[0], row[1])
