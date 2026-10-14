extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
func _initialize()->void:
	var doc=Doc.open_file("D:/code/rmmo_runtime/cache/world3d/axel_town_roads_20261014/map.gltf")
	for record:Dictionary in doc.records:
		if not record.has("bridge_mesh"):continue
		var data:=Frozen.decode(record.house_prefab)
		for mi in data.meshes.size():
			var mesh:Dictionary=data.meshes[mi]
			for si in mesh.surfaces.size():
				var a:Array=mesh.surfaces[si];var tangents:PackedFloat32Array=a[Mesh.ARRAY_TANGENT]
				var positions:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var uv:PackedVector2Array=a[Mesh.ARRAY_TEX_UV];var normals:PackedVector3Array=a[Mesh.ARRAY_NORMAL];var indices:PackedInt32Array=a[Mesh.ARRAY_INDEX]
				for i in positions.size():
					if Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2]).length_squared()>=.1:continue
					var triangles:Array=[]
					for at in range(0,indices.size(),3):
						if i not in [indices[at],indices[at+1],indices[at+2]]:continue
						var ids:Array=[indices[at],indices[at+1],indices[at+2]]
						triangles.append({"indices":ids,"p":ids.map(func(id):return str(positions[id])),"uv":ids.map(func(id):return str(uv[id])),"n":ids.map(func(id):return str(normals[id])),"area":(positions[ids[1]]-positions[ids[0]]).cross(positions[ids[2]]-positions[ids[0]]).length()*.5,"uv_det":(uv[ids[1]]-uv[ids[0]]).cross(uv[ids[2]]-uv[ids[0]])})
					print(JSON.stringify({"bridge":record.uuid,"mesh":mi,"surface":si,"bad_vertex":i,"p":str(positions[i]),"n":str(normals[i]),"tangent":[tangents[i*4],tangents[i*4+1],tangents[i*4+2],tangents[i*4+3]],"triangles":triangles}))
	quit()
