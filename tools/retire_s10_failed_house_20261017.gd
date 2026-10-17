extends SceneTree
## Reversible catalog withdrawal of this task's failed v3, retaining all files.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Imported=preload("res://scripts/world3d/imported_building.gd")
const FOLDER="D:/code/rmmo_runtime/packs/default/assets"
var SHA="cf85469f586104ab4c51b009f349befe1d846f94c16e042f4f58f7b56a71d33b"
var OUT="D:/code/rmmo_runtime/review_artifacts/s10_court_variants_20261017/publication/withdrawn_house_v3.json"
func _initialize()->void:call_deferred("run")
func run()->void:
	if "--v4" in OS.get_cmdline_user_args():
		SHA="522e58d7080bc010d0a512343ff8b7d9837818ebce454373f4b3ec0f28748d78";OUT=OUT.replace("v3.json","v4.json")
	if FileAccess.file_exists(OUT):quit(2);return
	var lib:=Library.new(FOLDER);var matches:Array=lib.entries.filter(func(e):return e.get("asset_path")==FOLDER+"/"+SHA+".glb")
	if matches.size()!=1 or matches[0].label!="S10 果树庭院住宅 · 高窗百叶木门":quit(2);return
	var entry:Dictionary=matches[0]
	if FileAccess.get_sha256(entry.asset_path)!=SHA:quit(2);return
	# Verify the precise failure before withdrawing; never withdraw a different fix.
	var source:=Imported.source_descriptor(entry.asset_path,SHA)
	if source.is_empty() or Imported.same(source,entry.model_building):quit(2);return
	var before:=lib._revision;lib.entries.erase(entry);var remaining:=JSON.stringify(lib.entries)
	if lib.save()!=OK:quit(2);return
	var fresh:=Library.new(FOLDER)
	if JSON.stringify(fresh.entries)!=remaining:quit(2);return
	var proof:Dictionary={"completed":true,"reason":"source/catalog numeric descriptor mismatch; formal HTTP save failed","withdrawn_entry":entry,"source_retained":true,"source_sha256":SHA,"catalog_sha_before":before,"catalog_sha_after":fresh._revision,"other_entries_unchanged":true,"recovery":"The exact withdrawn entry is preserved here; restore only after its invalid semantic data is corrected. Source, thumbnail and native remain retained separately."}
	var file:=FileAccess.open(OUT,FileAccess.WRITE);if file==null:quit(2);return
	file.store_string(JSON.stringify(proof,"  "));file.close();print("S10_V3_WITHDRAWN other_entries_unchanged=true");quit()
