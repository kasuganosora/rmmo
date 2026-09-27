extends RefCounted
## Keep native dependency graphs intact instead of rebuilding skinned/animated meshes.
static func prepare(root: Node) -> void:
	if root.has_meta("native_graph_prepared"): return
	root.set_meta("native_graph_prepared", true)
	var nodes: Array = []
	_collect(root, nodes)
	var special := false
	var animated := {}
	for node in nodes:
		if node is AnimationPlayer:
			special = true
			var animation_root: Node = node.get_node_or_null(node.root_node)
			if animation_root == null: continue
			for name in node.get_animation_list():
				var animation: Animation = node.get_animation(name)
				for track in animation.get_track_count():
					var target := animation_root.get_node_or_null(NodePath(animation.track_get_path(track).get_concatenated_names()))
					if target != null: animated[target] = true
		if node is Skeleton3D or node is Light3D: special = true
		if node is Node3D and not node.visible: special = true
		if node is MeshInstance3D and node.mesh is ArrayMesh and node.mesh.get_blend_shape_count() > 0: special = true
		if node is Camera3D:
			special = true
			node.current = false # Imported cameras must not replace the gameplay camera.
	if not special: return
	root.set_meta("native_graph_preserved", true)
	var notices: Array = []
	for node in nodes:
		if not node is MeshInstance3D: continue
		node.set_meta("native_visual", true)
		var moving: bool = node.skin != null or (node.mesh is ArrayMesh and node.mesh.get_blend_shape_count() > 0)
		var ancestor: Node = node
		while ancestor != null:
			if animated.has(ancestor): moving = true
			if ancestor == root: break
			ancestor = ancestor.get_parent()
		if not moving: continue
		node.set_meta("native_dynamic", true)
		var extras: Dictionary = node.get_meta("extras", {})
		if node.skin != null:
			notices.append("蒙皮网格保留原骨骼；碰撞应由角色胶囊或独立碰撞体提供。")
		elif str(extras.get("rmmo_collision", "none")) != "none" and node.mesh != null:
			var body := AnimatableBody3D.new()
			body.name = "NativeAnimatedCollision"
			body.sync_to_physics = false
			body.set_meta("uuid", str(extras.get("uuid", node.name)))
			var shape := CollisionShape3D.new()
			shape.shape = node.mesh.create_trimesh_shape()
			body.add_child(shape)
			node.add_child(body)
	root.set_meta("native_import_notices", notices)

static func _collect(node: Node, result: Array) -> void:
	result.append(node)
	for child in node.get_children(): _collect(child, result)
