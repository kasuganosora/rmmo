extends RefCounted
## Worker-only derived index LODs. Base arrays/materials/collision stay exact.
const MIN_TRIANGLES=2048
static func derive(arrays:Array)->Dictionary:
	var count:=0
	for surface:Array in arrays:
		for channel in [Mesh.ARRAY_BONES,Mesh.ARRAY_WEIGHTS]:
			if surface[channel]!=null and not surface[channel].is_empty():return {}
		count+=(surface[Mesh.ARRAY_INDEX].size() if surface[Mesh.ARRAY_INDEX]!=null else surface[Mesh.ARRAY_VERTEX].size())/3
	if count<MIN_TRIANGLES:return {}
	var original:=var_to_bytes(arrays);var importer:=ImporterMesh.new();var canonical:Array=[]
	for surface:Array in arrays:
		# Native frozen surfaces may encode unused channels as empty packed arrays.
		# ImporterMesh normalizes those to null; only that empty representation is
		# canonicalized privately, never the authoritative nonempty channels.
		var input:Array=surface.duplicate()
		for channel in Mesh.ARRAY_MAX:
			if input[channel]!=null and input[channel].is_empty():input[channel]=null
		canonical.append(input);importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,input)
	importer.generate_lods(60,25,[])
	var lods:Array=[];var counts:Array=[]
	for slot in arrays.size():
		if var_to_bytes(importer.get_surface_arrays(slot))!=var_to_bytes(canonical[slot]):return {}
		var levels:Dictionary={};var sizes:Array=[]
		for level in importer.get_surface_lod_count(slot):
			var indices:=importer.get_surface_lod_indices(slot,level)
			levels[importer.get_surface_lod_size(slot,level)]=indices;sizes.append(indices.size()/3)
		lods.append(levels);counts.append(sizes)
	if var_to_bytes(arrays)!=original:return {}
	return {"lods":lods,"base_triangles":count,"triangles":counts}
