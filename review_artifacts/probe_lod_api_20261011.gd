extends SceneTree
func _initialize()->void:
	for type:String in ["Mesh","ArrayMesh","RenderingServer","ImporterMesh"]:
		for method:Dictionary in ClassDB.class_get_method_list(type):
			if "lod" in str(method.name) or str(method.name)=="mesh_get_surface":print(type," ",method.name," ",method.args)
	quit()
