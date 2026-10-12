extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var failed:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failed+=1
func put(path:String)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string("existence-only validation fixture");file.close()
func run()->void:
	var folder:=Paths.cache_directory("save_validation_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("model.glb");put(path)
	var doc:=Doc.new()
	for i in 1000:doc.records.append({"uuid":"model_%d"%i,"kind":"asset","asset_path":path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"surface_id":"model"})
	var started:=Time.get_ticks_usec();var valid:=true
	for record:Dictionary in doc.records:valid=valid and doc.validate_save_record(record)==OK
	var uncached:=(Time.get_ticks_usec()-started)/1000.
	check(valid,"ordinary validation accepts repeated valid model references")
	var checked:Dictionary={};var materials:Dictionary={};started=Time.get_ticks_usec()
	for record:Dictionary in doc.records:valid=valid and doc.validate_save_record(record,materials,checked)==OK
	check(valid and checked.size()==1 and doc.validate_save_asset_paths(checked)==OK,"one operation reuses repeated model path checks with final verification")
	print("VALIDATION_PATH_TIMING uncached_ms=",uncached," scoped_ms=",(Time.get_ticks_usec()-started)/1000.)
	DirAccess.remove_absolute(path)
	check(doc.validate_save_asset_paths(checked)==ERR_FILE_NOT_FOUND,"file removed after sliced record checks rejects save")
	check(doc.validate_save()==ERR_FILE_NOT_FOUND,"next validation does not trust previous pass existence")
	put(path);check(doc.validate_save()==OK,"repaired file is visible on the next validation")
	var wrong:Dictionary=doc.records[0].duplicate(true);wrong.asset_path="D:/outside_validation_root.glb"
	check(doc.validate_save_record(wrong,materials,checked)==ERR_INVALID_DATA,"different escaping path cannot reuse a valid decision")
	var image:=folder.path_join("image.png");put(image)
	var paint_record:Dictionary={"terrain_material":{"texture_path":image}}
	check(Paint.missing([paint_record,paint_record,paint_record]).is_empty(),"repeated image existence checked within one operation")
	DirAccess.remove_absolute(image)
	check(Paint.missing([paint_record,paint_record]).size()==1,"fresh material pass reports removed shared image exactly once")
	put(image);check(Paint.missing([paint_record]).is_empty(),"material absence is not cached across operations")
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(folder)
	print("REFERENCE_SAVE_VALIDATION_FINISHED failures=",failed);quit(0 if failed==0 else 1)
