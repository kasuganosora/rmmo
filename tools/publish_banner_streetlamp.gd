extends SceneTree
## Publish the verified prefab into the shared editor shelf; no map placement.
func _initialize()->void:
	var base:=preload("res://scripts/asset/art_paths.gd").external_root()
	var source:=base.path_join("assets/banner_streetlamp/banner_streetlamp.glb")
	var library:=preload("res://scripts/world_editor/asset_library.gd").new(base.path_join("packs/default/assets"))
	library.entries=library.entries.filter(func(entry):return entry.get("label","") not in ["banner_streetlamp","古铜旗幡路灯（静态）","古铜旗幡路灯（可换旗·随风）"])
	var imported:=library.import_file(source)
	if not imported.ok:push_error(str(imported));quit(1);return
	var doc:=preload("res://scripts/world3d/world_document.gd").new();var id:=doc.add_asset(imported.entry,Vector3.ZERO);doc._find(id).collision="block"
	var result:=preload("res://scripts/world_editor/prefab_library.gd").capture(doc.records,library,"古铜旗幡路灯（可换旗·随风）")
	if not result.ok:push_error(str(result));quit(1);return
	var report:={"asset_sha256":FileAccess.get_sha256(source),"entry":result.entry,"formal_map_modified":false}
	var file:=FileAccess.open(base.path_join("review_artifacts/banner_streetlamp/published.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("BANNER_PUBLISHED ",JSON.stringify(report));quit()
