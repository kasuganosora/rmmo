extends RefCounted
## Pure-data white-stage demand only. Actual attach retains all live Node gates.
## This helper never loads a material, creates a Resource or reads GPU buffers.
static func white_render_slot(data:Dictionary)->int:
	var render_id:int=data.entries[0][1][0]
	var mesh:Dictionary=data.meshes[render_id]
	if mesh.surfaces.size()<2 or mesh.get("box_size",Vector3.ZERO)!=Vector3.ZERO:return -1
	var culls:Dictionary={}
	for material_id:int in mesh.materials:
		var material:Dictionary=data.materials[material_id]
		# Match runtime_mesh_cache.restore_material's existing white projection.
		var cull:int=int(material.get("cull",BaseMaterial3D.CULL_BACK)) if material.has("paint") else int(material.get("values",{}).get("cull_mode",BaseMaterial3D.CULL_BACK))
		culls[cull]=true
	return render_id if culls.size()<mesh.surfaces.size() else -1

static func selected_slots(data:Dictionary,source_only:bool,shadow_render:bool)->Dictionary:
	var result:Dictionary={}
	if not source_only:
		for i:int in data.meshes.size():result[i]=true
		return result
	result[int(data.entries[0][1][1])]=true
	if shadow_render:
		var render_id:=white_render_slot(data)
		if render_id>=0:result[render_id]=true
	return result
