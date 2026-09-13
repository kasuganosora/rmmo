extends RefCounted
## Safe accessors for autoload singletons. Use via: const Net = preload("res://scripts/net/net.gd")

static var _session_node: Node = null
static var _server_node: Node = null


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
	if _server_node != null and is_instance_valid(_server_node):
		return _server_node
	var root := _root()
	if root == null:
		return null
	_server_node = root.get_node_or_null("MockServer")
	if _server_node == null:
		push_error("Net: autoload 'MockServer' not found")
	return _server_node