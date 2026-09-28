extends SceneTree
const Builder = preload("res://tools/source_hair_builder.gd")
const Art = preload("res://scripts/asset/art_paths.gd")
func _initialize() -> void:call_deferred("run")
func own_children(node: Node, owner_: Node) -> void:
	for child in node.get_children():
		child.owner = owner_
		own_children(child, owner_)
func run() -> void:
	var folder: String = Art.path("characters/hair/female_base_v2")
	DirAccess.make_dir_recursive_absolute(folder)
	for n in [1,3,6]:
		var node := Node3D.new()
		node.name = "SourceHair"
		root.add_child(node)
		var builder := Builder.new()
		for part in ["f","b"]:node.add_child(builder.load_source("p_cf_hair_%s_%02d" % [part,n]))
		own_children(node,node)
		var packed := PackedScene.new()
		assert(packed.pack(node)==OK)
		assert(ResourceSaver.save(packed,folder+"/source_%02d.scn"%n)==OK)
		node.free()
	print("PASS: 3 native hair pairs baked with separate original skeletons")
	quit()
