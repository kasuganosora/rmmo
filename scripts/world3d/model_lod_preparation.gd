extends RefCounted
## Explicit import/native build only. Raw streaming fallback keeps full detail.
## Screen-error LOD changes index buffers only; base geometry and collision stay.
static func prepare(state:GLTFState)->Dictionary:
	var marked:Dictionary={};var counts:Array=[]
	if not state.json.get("skins",[]).is_empty() or not state.json.get("animations",[]).is_empty():return {"meshes":[]}
	for node:Dictionary in state.json.get("nodes",[]):
		if node.get("extras",{}).get("rmmo_auto_lod",false) and node.has("mesh"):marked[int(node.mesh)]=true
	for index:int in marked:
		if index<0 or index>=state.meshes.size():continue
		var mesh:ImporterMesh=state.meshes[index].mesh
		if mesh==null or mesh.get_blend_shape_count()>0:continue
		var before:Array=[];var triangles:=0
		for slot in mesh.get_surface_count():
			var arrays:Array=mesh.get_surface_arrays(slot);before.append(var_to_bytes(arrays))
			triangles+=arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size()/3
		if triangles<2000:continue
		mesh.generate_lods(60,25,[])
		var levels:Array=[]
		for slot in mesh.get_surface_count():
			assert(before[slot]==var_to_bytes(mesh.get_surface_arrays(slot)),"LOD must preserve base geometry")
			var row:Array=[]
			for level in mesh.get_surface_lod_count(slot):row.append({"error":mesh.get_surface_lod_size(slot,level),"triangles":mesh.get_surface_lod_indices(slot,level).size()/3})
			levels.append(row)
		counts.append({"mesh":index,"base_triangles":triangles,"levels":levels})
	return {"meshes":counts}
