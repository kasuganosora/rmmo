extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	assert(document.append_from_file(ArtPaths.path("characters/imported/artoria/character.glb"),state)==OK)
	var scene:=document.generate_scene(state);root.add_child(scene)
	for node in scene.find_children("*","",true,false):
		if node is Skeleton3D:
			print("SKELETON ",node.get_path()," transform ",node.global_transform)
			for i in range(node.get_bone_count()):
				if not "Hand" in node.get_bone_name(i):print(node.get_bone_name(i)," ",node.get_bone_global_rest(i))
		if node is MeshInstance3D:print("MESH ",node.name," ",node.get_aabb()," ",node.global_transform)
	quit()
