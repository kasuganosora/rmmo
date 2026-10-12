extends RefCounted
## Opt-in static single-mesh crops share the normal spatial render batcher.
static func eligible(r:Dictionary)->bool:
	if r.get("vegetation_batch",false)!=true or r.get("kind")!="asset" or r.get("invisible",false):return false
	for key in ["fixture","surface_paint","event","event_template","hostile","ally","seat","parametric_tree","bridge_mesh","building","house_prefab","model_component_states"]:
		if r.has(key):return false
	return r.get("wind_response",{}).get("profile","off")=="off"
static func flatten(holder:Node3D,r:Dictionary)->Node3D:
	if not eligible(r):return holder
	for key in ["missing_asset","paint_error","model_component_batch_sources"]:
		if holder.has_meta(key):return holder
	var meshes:=preload("res://scripts/world3d/surface_materials.gd").meshes(holder)
	if meshes.size()!=1:return holder
	var mesh:MeshInstance3D=meshes[0]
	if mesh.mesh==null or not plain_hierarchy(holder,mesh):return holder
	if mesh.skin!=null or mesh.skeleton!=NodePath("") and mesh.get_node_or_null(mesh.skeleton) is Skeleton3D:return holder
	if mesh.mesh is ArrayMesh and mesh.mesh.get_blend_shape_count()>0:return holder
	var node:Node=mesh;var local:=Transform3D.IDENTITY
	while node!=holder:
		if node is Node3D:local=node.transform*local
		node=node.get_parent()
	# Generic imported hierarchies stay intact. The crop exports deliberately have
	# identity transforms, so editor position/scale edits keep the same local mesh.
	if not local.is_equal_approx(Transform3D.IDENTITY):return holder
	if not holder.find_children("*","AnimationPlayer",true,false).is_empty():return holder
	mesh.get_parent().remove_child(mesh);mesh.name=holder.name;mesh.transform=holder.transform
	mesh.set_meta("asset_uuid",str(r.uuid));mesh.set_meta("ground_batch_record",r.duplicate(true))
	holder.free();return mesh

static func plain_hierarchy(node:Node,visual:MeshInstance3D)->bool:
	# Row placement also accepts ordinary props. Preserve sibling lights,
	# physics, active components, diagnostics and parent visibility semantics.
	if node.get_script()!=null:return false
	if node!=visual:
		if node.get_class()!="Node3D" or not node.visible or node.top_level or not node.visibility_parent.is_empty():return false
		if node.get_child_count()!=1:return false
		return plain_hierarchy(node.get_child(0),visual)
	if node.get_child_count()!=0 or visual.top_level or not visual.visibility_parent.is_empty():return false
	# These settings belong to each instance's position. A MultiMesh visibility
	# range would be measured from the whole batch and changes the source policy.
	if visual.visibility_range_begin!=0 or visual.visibility_range_end!=0 or visual.visibility_range_begin_margin!=0 or visual.visibility_range_end_margin!=0:return false
	if visual.visibility_range_fade_mode!=GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED or visual.lod_bias!=1.0:return false
	if visual.extra_cull_margin!=0 or visual.custom_aabb!=AABB() or visual.ignore_occlusion_culling:return false
	return true
