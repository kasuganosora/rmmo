extends "res://tools/review_guild_full_batch.gd"
func run()->void:
	var manifest:=read_json("D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/repair_manifest.json")
	var failures:Array=[]
	for row:Dictionary in manifest.library:
		var filters:=OS.get_cmdline_user_args()
		if not filters.is_empty() and str(row.asset_id) not in filters:continue
		row.id=row.asset_id
		var doc:=GLTFDocument.new();var state:=GLTFState.new()
		if doc.append_from_file(row.path,state)!=OK:failures.append(row.id);continue
		var lod:=preload("res://scripts/world3d/model_lod_preparation.gd").prepare(state)
		var scene:Node=Io.generate_scene(doc,state);doc=null;state=null
		var folder:="D:/code/rmmo_runtime/review_artifacts/axel_guild_finish_20261012/repair_review/library/"+str(row.id)
		await review_one(scene,row,folder)
		report.lod_derivation=lod
		check(FileAccess.get_sha256(row.path)==row.sha256,"source unchanged")
		for texture:Dictionary in report.texture_diagnostics:check(texture.get("mips",false) or maxi(texture.get("width",1),texture.get("height",1))==1,"production texture has mips")
		report.passed=report.failures.is_empty();put(folder+"/report.json",report)
		if not report.passed:failures.append(row.id)
	var suffix:="library_summary" if OS.get_cmdline_user_args().is_empty() else "library_subset_summary"
	put("D:/code/rmmo_runtime/review_artifacts/axel_guild_finish_20261012/repair_review/"+suffix+".json",{"count":manifest.library.size() if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args().size(),"failures":failures})
	print("REPAIRED_LIBRARY_COMPLETE failures=",failures);quit(0 if failures.is_empty() else 1)
