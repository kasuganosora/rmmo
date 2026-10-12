extends RefCounted
## Explicit, asset-local editor geometry. Render distance is not picking identity.
## v1 extras.rmmo_editor_picking = {version:1, group:"local-id",
## role:"canonical"|"render_lod"}. Mouse picking/painting uses the exact canonical
## mesh; explicit material targets still address every original mesh independently.
## No scene metadata is changed and no derived decision enters WorldDocument.
static var enabled:=false # Candidate: enable only after model + HTTP/GPU acceptance.
const FIELD:="rmmo_editor_picking"

static func build(root:Node,node_enabled:Callable,record_lookup:Callable)->Dictionary:
	var skipped:Dictionary={}
	if not enabled or root==null:return skipped
	var groups:Dictionary={}
	var initial_scope:Node=root.get_parent()
	while initial_scope!=null and not initial_scope.has_meta("asset_uuid"):initial_scope=initial_scope.get_parent()
	# A caller may rebuild one child. Never infer a closed group from that child
	# alone while a second canonical/member exists elsewhere in its asset.
	if not root.has_meta("asset_uuid") and initial_scope!=null:root=initial_scope
	var ancestors_enabled:=true
	var ancestor:Node=root.get_parent()
	while ancestor!=null:
		ancestors_enabled=ancestors_enabled and bool(node_enabled.call(ancestor))
		ancestor=ancestor.get_parent()
	var pending:Array=[{"node":root,"scope":initial_scope,"available":ancestors_enabled}]
	while not pending.is_empty():
		var row:Dictionary=pending.pop_back()
		var node:Node=row.node
		var scope:Node=node if node.has_meta("asset_uuid") else row.scope
		var available:bool=row.available and bool(node_enabled.call(node))
		var extras:Variant=node.get_meta("extras",{})
		if scope!=null and extras is Dictionary and extras.has(FIELD):
			var declaration:Variant=extras[FIELD]
			# Without a usable group key this node remains on the ordinary path.
			if declaration is Dictionary and declaration.get("group") is String and not declaration.group.is_empty():
				var key:=str(scope.get_instance_id())+":"+str(declaration.group)
				if not groups.has(key):groups[key]={"scope":scope,"members":[],"canonical":[],"valid":true}
				var group:Dictionary=groups[key]
				group.members.append(node)
				var valid:=_valid_declaration(declaration) and node is MeshInstance3D
				if valid:
					var visual:=node as MeshInstance3D
					valid=visual.mesh!=null and _valid_transform(visual)
				if declaration.get("role")=="canonical":
					group.canonical.append(node)
					valid=valid and available
					if valid:valid=_has_pick_geometry(node as MeshInstance3D)
				elif declaration.get("role")=="render_lod":
					# Never remove collision merely because a node is a render LOD.
					valid=valid and extras.get("rmmo_collision")=="none"
				group.valid=group.valid and valid
		for child in node.get_children():pending.append({"node":child,"scope":scope,"available":available})
	var allowed_scopes:Dictionary={}
	for group:Dictionary in groups.values():
		if not group.valid or group.canonical.size()!=1 or group.members.size()<2:continue
		var scope:Node=group.scope
		var scope_id:=scope.get_instance_id()
		if not allowed_scopes.has(scope_id):
			var uuid:Variant=scope.get_meta("asset_uuid")
			var record:Variant=record_lookup.call(uuid) if uuid is String else null
			# _namespace_asset writes an explicit `none` onto every source mesh:
			# those alternatives have no WALK_MASK to preserve, while canonical
			# geometry still supplies exact editor picking. Physical/unknown
			# overrides remain conservative and retain every authored body.
			allowed_scopes[scope_id]=record is Dictionary and record.get("uuid")==uuid and record.get("kind")=="asset" and record.get("collision","") in ["","none"]
		if not allowed_scopes[scope_id]:continue
		for node:Node in group.members:
			if node!=group.canonical[0]:skipped[node.get_instance_id()]=true
	return skipped

static func _valid_declaration(value:Dictionary)->bool:
	if value.size()!=3 or not value.has_all(["version","group","role"]):return false
	var version:Variant=value.version
	if not (version is int or version is float) or version!=1:return false
	if not value.group is String or value.group.is_empty() or value.group.length()>128:return false
	return value.role is String and value.role in ["canonical","render_lod"]

static func _valid_transform(node:Node3D)->bool:
	var current:Node=node
	var combined:=Transform3D.IDENTITY
	while current!=null:
		if current is Node3D:
			var pose:Transform3D=current.transform
			if not pose.is_finite() or not is_finite(pose.basis.determinant()) or absf(pose.basis.determinant())<0.000000001:return false
			combined=pose*combined
			if not combined.is_finite():return false
			if current.top_level:break
		current=current.get_parent()
	return true

static func _has_pick_geometry(node:MeshInstance3D)->bool:
	var source:Variant=node.get_meta("paint_source",node.mesh)
	if source is BoxMesh:return source.size.is_finite() and source.size.x>0 and source.size.y>0 and source.size.z>0
	if not source is ArrayMesh:return false
	# Cpu.capture/collision_faces append EVERY surface into one triangle soup.
	# Finding one valid surface is insufficient: a later line/point surface can
	# make that canonical shape unusable, leaving no picker after LOD suppression.
	# Counts/topology are descriptors, not surface array readback or cooking.
	if source.get_surface_count()==0:return false
	for index in source.get_surface_count():
		if source.surface_get_primitive_type(index)!=Mesh.PRIMITIVE_TRIANGLES:return false
		var vertices:int=source.surface_get_array_len(index)
		var indices:int=source.surface_get_array_index_len(index)
		var face_vertices:int=indices if indices>0 else vertices
		if vertices<3 or face_vertices<3 or face_vertices%3!=0:return false
	return true
