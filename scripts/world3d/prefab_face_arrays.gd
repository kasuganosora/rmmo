extends RefCounted
## Exact ordered triangle expansion shared by offline products and raw fallback.
static func build(mesh:Dictionary,native_unindexed:bool=true)->PackedVector3Array:
	var triangles:=PackedVector3Array();var count:=0;var indexed:=false
	for arrays:Array in mesh.surfaces:
		var indices:Variant=arrays[Mesh.ARRAY_INDEX]
		indexed=indexed or (indices!=null and not indices.is_empty())
		count+=indices.size() if indices!=null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
	if native_unindexed and not indexed:
		for arrays:Array in mesh.surfaces:triangles.append_array(arrays[Mesh.ARRAY_VERTEX])
		return triangles
	triangles.resize(count);var at:=0
	for arrays:Array in mesh.surfaces:
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:Variant=arrays[Mesh.ARRAY_INDEX]
		if indices!=null and not indices.is_empty():
			for index:int in indices:triangles[at]=vertices[index];at+=1
		else:
			for vertex:Vector3 in vertices:triangles[at]=vertex;at+=1
	return triangles
