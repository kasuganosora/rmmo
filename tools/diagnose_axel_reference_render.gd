extends RefCounted
## Read-only diagnostics of the live, asynchronously published editor scene.
const Mats=preload("res://scripts/world3d/surface_materials.gd")
static func digest(bytes:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
static func material(value:Material)->Dictionary:
	if value==null:return {}
	var result:={"class":value.get_class(),"name":value.resource_name,"path":value.resource_path}
	if value is StandardMaterial3D:
		result.albedo_color=str(value.albedo_color);result.normal_enabled=value.normal_enabled;result.normal_scale=value.normal_scale;result.cull_mode=value.cull_mode;result.shading_mode=value.shading_mode;result.transparency=value.transparency
		for key:String in ["albedo_texture","normal_texture","roughness_texture"]:
			var texture:Texture2D=value.get(key)
			if texture==null:result[key]=null;continue
			var img:=texture.get_image()
			result[key]={"class":texture.get_class(),"path":texture.resource_path,"width":texture.get_width(),"height":texture.get_height(),"pixel_sha256":digest(img.get_data()) if img!=null else ""}
	return result
static func meshes(node:Node,into:Array)->void:
	if node is MeshInstance3D:
		var m:=node as MeshInstance3D
		var row:={"path":str(m.get_path()),"visible":m.visible,"visible_in_tree":m.is_visible_in_tree(),"global_transform":str(m.global_transform),"transparency":m.transparency,"cast_shadow":m.cast_shadow,"extra_cull_margin":m.extra_cull_margin,"lod_bias":m.lod_bias,"material_override":material(m.material_override),"material_overlay":material(m.material_overlay),"extras":m.get_meta("extras",{}),"surfaces":[]}
		if m.mesh!=null:
			row.world_bounds=str(m.global_transform*m.mesh.get_aabb())
			for i in m.mesh.get_surface_count():
				var arrays:=m.mesh.surface_get_arrays(i)
				row.surfaces.append({"vertices":arrays[Mesh.ARRAY_VERTEX].size(),"indices":arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null else 0,"uv_count":arrays[Mesh.ARRAY_TEX_UV].size() if arrays[Mesh.ARRAY_TEX_UV]!=null else 0,"geometry_sha256":digest(var_to_bytes([arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_INDEX],arrays[Mesh.ARRAY_TEX_UV]])),"active_material":material(m.get_active_material(i)),"surface_material":material(m.mesh.surface_get_material(i)),"surface_override":material(m.get_surface_override_material(i))})
		into.append(row)
	for child:Node in node.get_children():meshes(child,into)
static func inspect(editor:Node)->Dictionary:
	var result:={"path":editor._path,"candidate_sha256":FileAccess.get_sha256(editor._path),"assets":[],"load_job":editor._load_job.state(),"batching":editor._ground_batches.stats()}
	for r:Dictionary in editor._doc.records:
		if r.get("editor_name","") not in ["Axel reference s12_arch_home/projecting_arch","Axel reference s12_arch_home/gable_relief"]:continue
		var n:Node=editor._view.get_node_or_null(str(r.uuid));var row:={"record":r,"nodes":[]}
		if n!=null:meshes(n,row.nodes)
		result.assets.append(row)
	return result
