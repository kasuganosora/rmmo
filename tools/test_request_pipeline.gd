extends SceneTree
## Headless: RequestPipeline dispatch — sync apply + async deferred/response_ready.


const Net = preload("res://scripts/net/net.gd")
const RequestPipeline = preload("res://scripts/net/request_pipeline.gd")


func _init() -> void:
	call_deferred("_run")


func _mk(src_lines: Array) -> Node:
	var s := GDScript.new()
	s.source_code = "\n".join(src_lines)
	s.reload()
	return s.new()


func _run() -> void:
	var failed := 0
	RequestPipeline.reset()

	var ctrl := _mk([
		"extends Node",
		"var applied := []",
		"func _apply_server_actions(actions):",
		"\tapplied.append_array(actions)",
	])
	root.add_child(ctrl)

	# --- Synchronous server: actions applied immediately ---
	var sync_srv := _mk([
		"extends Node",
		"func try_ping():",
		"\treturn {\"ok\": true, \"actions\": [{\"type\": \"system_message\", \"text\": \"sync-ok\"}]}",
	])
	root.add_child(sync_srv)
	Net.set_server(sync_srv)
	var r1: Dictionary = RequestPipeline.dispatch(ctrl, "try_ping", [])
	failed += _expect(bool(r1.get("ok", false)), "sync dispatch ok")
	failed += _expect(not bool(r1.get("deferred", false)), "sync result not deferred")
	failed += _expect(ctrl.applied.size() == 1, "sync applied 1 action immediately")
	failed += _expect(RequestPipeline.pending_count() == 0, "no pending after sync")

	# --- Missing method ---
	var rmiss: Dictionary = RequestPipeline.dispatch(ctrl, "try_nonexistent", [])
	failed += _expect(not bool(rmiss.get("ok", true)), "missing method -> ok false")
	failed += _expect(ctrl.applied.size() == 1, "missing method applied nothing")

	# --- Async server: deferred, then applied on response_ready ---
	var async_srv := _mk([
		"extends Node",
		"signal response_ready(request_id: int, result: Dictionary)",
		"var _next := 1",
		"var last_id := -1",
		"func try_ping():",
		"\tvar rid = _next",
		"\t_next += 1",
		"\tlast_id = rid",
		"\treturn {\"deferred\": true, \"request_id\": rid}",
		"func emit_response(rid):",
		"\tresponse_ready.emit(rid, {\"ok\": true, \"actions\": [{\"type\": \"system_message\", \"text\": \"async-ok\"}]})",
	])
	root.add_child(async_srv)
	Net.set_server(async_srv)
	var r2: Dictionary = RequestPipeline.dispatch(ctrl, "try_ping", [])
	failed += _expect(bool(r2.get("deferred", false)), "async dispatch deferred")
	failed += _expect(RequestPipeline.pending_count() == 1, "one pending after async dispatch")
	failed += _expect(ctrl.applied.size() == 1, "async not applied before response")
	async_srv.emit_response(int(async_srv.last_id))
	failed += _expect(ctrl.applied.size() == 2, "async applied after response_ready")
	failed += _expect(RequestPipeline.pending_count() == 0, "pending cleared after response")

	# --- Stray/duplicate response is ignored ---
	async_srv.emit_response(int(async_srv.last_id))
	failed += _expect(ctrl.applied.size() == 2, "duplicate/stray response ignored")

	# --- reset() drops correlation + subscription ---
	RequestPipeline.dispatch(ctrl, "try_ping", [])
	failed += _expect(RequestPipeline.pending_count() == 1, "pending before reset")
	RequestPipeline.reset()
	failed += _expect(RequestPipeline.pending_count() == 0, "reset clears pending")

	Net.clear_server_override()
	ctrl.queue_free()
	sync_srv.queue_free()
	async_srv.queue_free()
	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS test_request_pipeline")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
