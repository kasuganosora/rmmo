extends RefCounted
## Scene nodes exist only for the view list the worker published.

static var _mesh: CapsuleMesh


static func apply(host: Node, view: Array) -> int:
	if _mesh == null:
		_mesh = CapsuleMesh.new()
		_mesh.radius = 0.28
		_mesh.height = 1.2
	var keep := {}
	for item in view:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var actor: Dictionary = item
		var id := int(actor.get("id", -1))
		if id < 0:
			continue
		keep[id] = true
		var name := "Actor%d" % id
		var node := host.get_node_or_null(name) as MeshInstance3D
		if node == null:
			node = MeshInstance3D.new()
			node.name = name
			node.mesh = _mesh
			host.add_child(node)
		node.position = Vector3(float(actor.get("x", 0.0)), 0.9, float(actor.get("z", 0.0)))
	var stale: Array = []
	for child in host.get_children():
		var text := str(child.name)
		if not text.begins_with("Actor"):
			continue
		var id := int(text.substr(5))
		if not keep.has(id):
			stale.append(child)
	for child in stale:
		(child as Node).free()
	return keep.size()
