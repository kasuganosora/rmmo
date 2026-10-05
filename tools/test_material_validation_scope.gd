extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failed:=0
func check(ok: bool,label_: String) -> void:
	if not ok: failed+=1; push_error(label_)
	else: print("PASS: ",label_)
func _initialize() -> void:
	var directory:=Paths.cache_directory("material_validation_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("test.png"); var image:=Image.create(1,1,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE); image.save_png(path)
	var material:={"name":"test","color":[1.,1.,1.,1.],"roughness":1.,"texture_path":path}; var cache: Dictionary={}
	check(Paint.material_valid(material,false,Paths.external_root(),cache),"valid material enters operation-local cache")
	check(Paint.material_valid(material.duplicate(true),false,Paths.external_root(),cache) and cache.size()==1,"identical material reuses validation")
	check(not Paint.material_valid(material.merged({"roughness":2.},true),false,Paths.external_root(),cache),"changed invalid values cannot hit valid cache")
	check(not Paint.material_valid(material,false,directory.path_join("other_root"),cache),"different resource root cannot reuse permission result")
	var doc:=preload("res://scripts/world3d/world_document.gd").new(); doc.add_box("ground",Vector3.ZERO,Vector3(4,.5,4)); doc.records[0].terrain_material=material
	doc.records[0].terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-4.,"heights":[0.,0.,0.,0.,0.,0.,0.,0.,0.],"holes":[false,false,false,false]}
	var copy: Dictionary=doc.records[0].duplicate(true); copy.uuid="second"; copy.position=[10.,0.,0.]; doc.records.append(copy)
	var extra:={"rmmo_format":"rmmo_gltf_map","rmmo_version":1,"rmmo_records":doc.records}
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); loader._content_root=Paths.external_root()
	check(loader._valid_records(extra),"native validation accepts repeated valid materials")
	DirAccess.remove_absolute(path)
	check(not loader._valid_records(extra),"new validation rejects deleted texture despite previous success")
	image.save_png(path); doc.records[1].terrain_material=material.merged({"texture_path":"D:/outside_allowed_root.png"},true)
	check(not loader._valid_records(extra),"one escaping material rejects whole document")
	doc.records[1].terrain_material=material
	for i in 10:
		var r:Dictionary=doc.records[0].duplicate(true);r.uuid="batch_%d"%i;doc.records.append(r)
	check(loader._valid_records(extra),"all parallel validation batches accept valid records")
	doc.records.back().terrain_mesh.heights[0]=NAN
	check(not loader._valid_records(extra),"one malformed terrain rejects the whole parallel snapshot")
	doc.records.back().terrain_mesh.heights[0]=0.
	doc.records.back().uuid=doc.records[0].uuid
	check(not loader._valid_records(extra),"duplicate UUID across worker batches is rejected")
	doc.records.back().uuid="fixed"
	doc.records.back().house_prefab={"version":0,"sha256":"bad","length":4,"data":"bad"}
	check(not loader._valid_records(extra),"invalid prefab rejects snapshot after all validation workers retire")
	loader.free(); print("MATERIAL_VALIDATION_SCOPE_FINISHED failures=",failed); quit(1 if failed else 0)
