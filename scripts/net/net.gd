extends RefCounted
## Safe accessors for autoload singletons. Use via: const Net = preload("res://scripts/net/net.gd")
##
## `server()` returns the authoritative game server the client talks to. By default that
## is the in-process `MockServer` autoload, but a real transport (see net_client.gd) can
## be injected via `set_server()` so the whole UI keeps working without changes when the
## Go-backed server replaces the scaffold.

static var _session_node: Node = null
static var _server_node: Node = null
## Injected server override (a NetClient-conforming node). When set and valid, it wins
## over the MockServer autoload.
static var _server_override: Node = null


static func _root() -> Window:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	return ml.root


static func session() -> Node:
	if _session_node != null and is_instance_valid(_session_node):
		return _session_node
	var root := _root()
	if root == null:
		return null
	_session_node = root.get_node_or_null("GameSession")
	if _session_node == null:
		push_error("Net: autoload 'GameSession' not found")
	return _session_node


static func server() -> Node:
	## An injected transport wins over the scaffold MockServer.
	if _server_override != null and is_instance_valid(_server_override):
		return _server_override
	if _server_node != null and is_instance_valid(_server_node):
		return _server_node
	var root := _root()
	if root == null:
		return null
	_server_node = root.get_node_or_null("MockServer")
	if _server_node == null:
		push_error("Net: autoload 'MockServer' not found")
	return _server_node


## Inject the authoritative server the client should talk to (a NetClient-conforming
## node — see net_client.gd). Pass a node to override the MockServer autoload; the whole
## UI then routes through it transparently. Validates the contract and warns on any gap.
static func set_server(node: Node) -> Dictionary:
	_server_override = node
	if node == null:
		return {"ok": true, "missing_signals": [], "missing_methods": []}
	var NetClient = load("res://scripts/net/net_client.gd")
	var report: Dictionary = NetClient.validate(node)
	if not bool(report.get("ok", false)):
		push_warning("Net.set_server: server does not fully satisfy NetClient contract — missing methods: %s | signals: %s" % [
			str(report.get("missing_methods", [])), str(report.get("missing_signals", [])),
		])
	return report


## Drop the injected override; `server()` falls back to the MockServer autoload.
static func clear_server_override() -> void:
	_server_override = null


## True when a transport override is currently active.
static func has_server_override() -> bool:
	return _server_override != null and is_instance_valid(_server_override)