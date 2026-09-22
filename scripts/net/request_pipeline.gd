extends RefCounted
## Async-ready client -> server request dispatch. One call path bridges the synchronous
## scaffold (MockServer) and a future async transport, so request adapters do not need
## rewriting when the Go-backed server lands:
##
##   * synchronous server: `try_*(...)` returns `{ok, actions:[...]}` -> applied at once.
##   * async server:       `try_*(...)` returns `{deferred:true, request_id:N}` and later
##                         emits `response_ready(request_id, {ok, actions})` -> the
##                         pipeline correlates by request_id and applies on arrival.
##
## Correlation is by request_id (a universal pattern), independent of the eventual wire
## protocol, so this can ship before the Go protocol is finalized.

const Net = preload("res://scripts/net/net.gd")

## request_id -> { ctrl, applier: Callable }
static var _pending: Dictionary = {}
## The server node we are currently subscribed to for response_ready.
static var _subscribed: Object = null


## Call `method` on the active server with `args`; apply returned actions to `ctrl`
## (sync) or defer until the matching response_ready (async). Optional `applier` is
## called with the full result dict once resolved.
## Returns the immediate result dict: {ok, ...} (with deferred/request_id when async),
## or {ok:false, error} when the server can't service the call.
static func dispatch(ctrl, method: String, args: Array = [], applier: Callable = Callable()) -> Dictionary:
	var srv = Net.server()
	if srv == null or not srv.has_method(method):
		return {"ok": false, "error": "server missing method '%s'" % method}
	var result = srv.callv(method, args)
	if typeof(result) != TYPE_DICTIONARY:
		return {"ok": false, "error": "non-dictionary result from '%s'" % method}
	var res: Dictionary = result
	if bool(res.get("deferred", false)):
		var rid := int(res.get("request_id", -1))
		if rid < 0:
			return {"ok": false, "error": "deferred result without request_id"}
		_ensure_subscribed(srv)
		_pending[rid] = {"ctrl": ctrl, "applier": applier}
		return res
	_apply(ctrl, res, applier)
	return res


## Distinct in-flight deferred request ids (telemetry / tests).
static func pending_count() -> int:
	return _pending.size()


static func _apply(ctrl, result: Dictionary, applier: Callable) -> void:
	var actions_v: Variant = result.get("actions", [])
	if ctrl != null and is_instance_valid(ctrl) and ctrl.has_method("_apply_server_actions") and typeof(actions_v) == TYPE_ARRAY:
		ctrl._apply_server_actions(actions_v)
	if applier.is_valid():
		applier.call(result)


static func _ensure_subscribed(srv: Object) -> void:
	if srv == _subscribed:
		return
	if _subscribed != null and is_instance_valid(_subscribed) \
			and _subscribed.has_signal("response_ready") \
			and _subscribed.response_ready.is_connected(_on_response_ready):
		_subscribed.response_ready.disconnect(_on_response_ready)
	_subscribed = srv
	if srv.has_signal("response_ready") and not srv.response_ready.is_connected(_on_response_ready):
		srv.response_ready.connect(_on_response_ready)


static func _on_response_ready(request_id: int, result: Dictionary) -> void:
	var entry_v: Variant = _pending.get(request_id, null)
	if entry_v == null:
		return
	_pending.erase(request_id)
	var entry: Dictionary = entry_v
	_apply(entry.get("ctrl"), result, entry.get("applier", Callable()))


## Drop all correlation state (e.g. on transport swap / disconnect).
static func reset() -> void:
	if _subscribed != null and is_instance_valid(_subscribed) \
			and _subscribed.has_signal("response_ready") \
			and _subscribed.response_ready.is_connected(_on_response_ready):
		_subscribed.response_ready.disconnect(_on_response_ready)
	_subscribed = null
	_pending.clear()
