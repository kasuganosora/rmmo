extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
var failures:=0
var passed:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if ok:passed+=1
	else:failures+=1
func run()->void:
	var source=Doc.open_file("D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf")
	if source==null:quit(2);return
	var bridge:Dictionary={}
	for r:Dictionary in source.records:
		if r.has("bridge_mesh"):bridge=r.duplicate(true);break
	check(not bridge.is_empty() and House.valid(bridge),"actual frozen bridge has complete validated geometry/material dependencies")
	if bridge.is_empty():quit(2);return
	var dir:="D:/code/rmmo_runtime/cache/world3d/frozen_source_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	bridge.asset_path=dir+"/missing_authoring_kit.glb"
	var doc=Doc.new();doc.records=[bridge]
	check(doc.missing_assets().is_empty(),"authoring-only kit is not a runtime dependency")
	check(doc.validate_save()==OK,"complete frozen bridge saves without its source GLB")
	var state:Dictionary={}
	check(doc.validate_save_record(bridge,{},state)==OK and doc.validate_save_asset_paths(state)==OK,"sliced save uses the same source dependency rule")
	check(doc.save(dir+"/map.gltf")==OK,"native reference map atomic save succeeds without kit")
	var reopened=Doc.open_file(dir+"/map.gltf")
	check(reopened!=null and reopened.records[0].house_prefab==bridge.house_prefab,"saved frozen bridge reopens with exact geometry payload")
	var live:=bridge.duplicate(true)
	for key in ["house_prefab","prefab_locked","prefab_materials"]:live.erase(key)
	check(House.requires_source_model(live),"unfrozen bridge still requires authoring model")
	for order in [[bridge,live],[live,bridge]]:
		doc.records=order;state={}
		for r:Dictionary in order:doc.validate_save_record(r,{},state)
		check(not doc.missing_assets().is_empty() and doc.validate_save_asset_paths(state)==ERR_FILE_NOT_FOUND,"live instance sharing path cannot inherit frozen exemption")
	doc.records=[bridge]
	var corrupt:=bridge.duplicate(true);corrupt.house_prefab.sha256="0".repeat(64)
	check(not House.valid(corrupt) and doc.validate_save_record(corrupt)!=OK,"corrupt frozen payload fails validation")
	var outside:=bridge.duplicate(true);outside.asset_path="C:/Windows/missing_authoring_kit.glb"
	check(doc.validate_save_record(outside)!=OK,"frozen authoring path still obeys resource root authority")
	var missing_texture:=bridge.duplicate(true)
	missing_texture.prefab_materials[0].texture_path=dir+"/missing_texture.png"
	House.retarget_materials(missing_texture)
	doc.records=[missing_texture]
	check(not doc.missing_assets().is_empty() and doc.validate_save()!=OK,"actual frozen texture dependency is still required")
	print("FROZEN_SOURCE passed=",passed," failures=",failures," map=",dir);quit(1 if failures else 0)
