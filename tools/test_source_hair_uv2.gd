extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:
	var checked:=0
	for number in [1,3,6]:
		var packed:PackedScene=load(Art.path("characters/hair/female_base_v2/source_%02d.scn"%number))
		var node:Node3D=packed.instantiate()
		for part in node.get_children():
			var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Art.path("characters/source_hair/koikatu/"+str(part.name)+"/source.json")))
			for mesh:MeshInstance3D in part.find_children("*","MeshInstance3D",true,false):
				var original:Dictionary={}
				for item:Dictionary in data.meshes.values():
					if item.name==mesh.mesh.resource_name:original=item;break
				assert(not original.is_empty(),"Cannot trace runtime hair mesh to source")
				for surface in mesh.mesh.get_surface_count():
					var arrays:Array=mesh.mesh.surface_get_arrays(surface)
					var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
					assert(tangents.size()==original.tangents.size()*4,"Source tangents lost during baking")
					for i in original.tangents.size():
						var t:Array=original.tangents[i]
						var actual:=Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])
						assert(actual.distance_to(Vector3(t[0],t[1],-t[2]))<0.002,"Source tangent direction changed")
						assert(is_equal_approx(tangents[i*4+3],t[3]),"UV/coordinate handedness changed")
					var uv2:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2]!=null else PackedVector2Array()
					assert(uv2.size()==original.uv2.size(),"Source UV2 lost during baking")
					for i in uv2.size():
						var expected:=Vector2(original.uv2[i][0],1.0-original.uv2[i][1])
						assert(uv2[i].distance_to(expected)<0.00001,"UV2 changed beyond coordinate conversion")
					checked+=uv2.size()
		node.free()
	assert(checked>0)
	print("PASS original UV2 retained in 3 runtime pairs: ",checked," surface vertices")
	quit()
