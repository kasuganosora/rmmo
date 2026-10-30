extends RefCounted
## Detached visual/body construction, shared by prepared editor transactions.
const Dependencies=preload("res://scripts/world3d/record_asset_dependencies.gd")
const Picking=preload("res://scripts/world_editor/picking_lod_policy.gd")

static func create_visual(document:RefCounted,record:Dictionary,context:RefCounted,effects:bool=true)->Node3D:
	var prepared:Dictionary=context.prepared(record) if context!=null else {}
	if Dependencies.model(record) and prepared.is_empty():return null
	return document._asset(record,prepared) if record.get("kind")=="asset" else document._mesh(record,effects,null,context)

static func visual_step(op:Dictionary,editor:Node3D)->bool:
	var record:Dictionary=op.records[op.cursor];op.cursor+=1
	var visual:Node3D=create_visual(op.target,record,op.prepared_context)
	if visual==null:return false
	op.root.add_child(visual);op.visuals[str(record.uuid)]=visual
	if visual.get_meta("missing_asset",false) or visual.has_meta("paint_error") or visual.has_meta("tile_error"):return false
	if op.kind=="mutate" and record.has("tree_settings") and record.tree_settings!=op.document._find(str(record.uuid)).get("tree_settings",{}):
		# Tree generation already ran once on the private READY instance. Capture
		# its new local bounds here rather than importing/generating a second tree.
		var bounds:AABB=preload("res://scripts/world_editor/asset_library.gd").bounds_of(visual.get_child(0))
		record.bounds_position=[bounds.position.x,bounds.position.y,bounds.position.z];record.bounds_size=[bounds.size.x,bounds.size.y,bounds.size.z]
	op.authoring.decorate(record,visual)
	if op.kind=="preview":op.work.visuals+=1;return true
	op.picking=Picking.build(visual,editor._body_node_enabled,op.target._find)
	op.nodes.append(visual);op.work.visuals+=1
	return true
static func body_step(op:Dictionary,editor:Node3D)->bool:
	var node:Node=op.nodes.pop_back();op.work.body_nodes+=1
	if not editor._body_node_enabled(node):return true
	if node is MeshInstance3D and node.mesh!=null and not op.picking.has(node.get_instance_id()) and editor._body_layers(node)!=0:
		var pose:=Transform3D.IDENTITY;var current:Node=node
		while current!=null and current!=op.root:
			if current is Node3D:
				pose=current.transform*pose
				if current.top_level:break
			current=current.get_parent()
		var uuid:String=editor._body_uuid(node)
		var body:StaticBody3D=editor._prepare_body(node,op.shapes,op.target.terrain_neighbors.data.get(uuid,{}),pose)
		if body==null:return false
		for shape:Node in body.get_children():
			if shape is CollisionShape3D and shape.shape==null:body.free();return false
		if not op.bodies.has(uuid):op.bodies[uuid]=[]
		op.bodies[uuid].append(body)
	for child:Node in node.get_children():op.nodes.append(child)
	return true
