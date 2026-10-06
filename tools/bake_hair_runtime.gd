extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var base:String=preload("res://scripts/util/json_util.gd").content_root()+"/assets/characters/hair"
	for gender in ["female","male"]:
		var document:=GLTFDocument.new();var state:=GLTFState.new()
		assert(document.append_from_file(base+"/"+gender+"/hairstyles.glb",state)==OK)
		var source:=document.generate_scene(state)
		for id in range(10,16):
			var scene:=source.duplicate()
			for mesh in scene.find_children("*","MeshInstance3D",true,false):
				if not str(mesh.name).begins_with("Hair_%d_"%id):mesh.free()
			for node in scene.find_children("*","",true,false):node.owner=scene
			var packed:=PackedScene.new();assert(packed.pack(scene)==OK)
			assert(ResourceSaver.save(packed,base+"/"+gender+"/hair_%d.scn"%id)==OK)
			scene.free()
		source.free()
	print("PASS baked 12 external hairstyle scenes")
	quit()
