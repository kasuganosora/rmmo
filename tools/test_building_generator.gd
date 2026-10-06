extends SceneTree
const Generator=preload("res://scripts/editor/domain/building_generator.gd")
const Document=preload("res://scripts/editor/domain/map_document.gd")
func _init() -> void:call_deferred("run")
func run() -> void:
	var kit: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/style_work/town_m/house_kit.json"))
	for bays in range(1,4):
		for floors in range(1,4):
			for roof in ["red","slate"]:
				var built:=Generator.compose(kit,{"bays":bays,"floors":floors,"roof":roof})
				assert(built.ok and built.w==bays*3+2 and built.h==floors*2+4)
				var door_count:=0;var layers: Dictionary={}
				for c in built.cells:
					assert(c.x>=0 and c.y>=0 and c.x<built.w and c.y<built.h)
					layers[c.z]=true
					if kit.parts.door.tiles.any(func(t): return int(t)==int(c.tile_id)):door_count+=1
				assert(door_count==4 and layers.size()==3,"fixed door size and three layers")
	var doc=Document.new();doc.setup_blank("HouseTest","HouseTest",32,32)
	var args={"x":3,"y":4,"bays":1,"floors":2,"instance_id":"test"}
	var placed:=Generator.place(doc,kit,args);assert(placed.ok)
	var first = doc.data.duplicate()
	assert(doc.undo() and doc.building_instances.is_empty())
	assert(doc.tile(3,7,1)==0 and doc.ext_tile("meta",3,7)==0)
	assert(doc.redo() and doc.data==first and doc.building_instances.has("test"))
	var conflict:=Generator.place(doc,kit,{"x":3,"y":4,"instance_id":"other"})
	assert(not conflict.ok and doc.data==first,"overlap rejection is atomic")
	args.floors=3;assert(Generator.place(doc,kit,args).ok)
	assert(doc.building_instances.test.h==10)
	assert(doc.undo() and doc.data==first and doc.building_instances.test.h==8)
	var save_path:="user://test_building_generator"
	assert(doc.save_dir(save_path))
	var loaded=Document.new();assert(loaded.load_dir(save_path))
	assert(loaded.data==doc.data)
	assert(loaded.building_instances.test.cells.size()==doc.building_instances.test.cells.size())
	assert(int(loaded.building_instances.test.h)==8)
	assert(Generator.place(loaded,kit,args).ok, "regenerate after reload")
	loaded.setup_blank("Blank","Blank",8,8)
	assert(loaded.building_instances.is_empty())
	assert(loaded.save_dir(save_path))
	var empty_map: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(save_path+"/map.json"))
	assert(not empty_map.has("building_instances"), "legacy maps gain no empty field")
	print("PASS 18 house variants, fixed-size openings, 3 layers, atomic overlap, regeneration, undo/redo and persistence")
	quit(0)
