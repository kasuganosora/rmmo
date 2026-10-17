extends "res://tools/test_guild_street_published_catalog.gd"
## Selected S12 structure-stage assets through the real shared library and HTTP.
## Inherited verifier owns a fresh cache map; it never writes the real town.
## --receipt=<publication/receipt.json> --out=<fresh report directory>
var expected_ids:Array[String]=["s12_freestanding_courtyard_gate","s12_riverside_residence","s12_red_gold_pennant_a","s12_red_gold_pennant_b","s12_doorstep_jar"]

func prepare_published_catalog()->bool:
	var initial:=failed
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	check(value is Dictionary and value.get("ok",false) and value.get("completed",false),"completed S12 structural publication receipt")
	if failed!=initial:return false
	published=value
	check(published.get("items") is Array and published.items.size()==expected_ids.size(),"exact selected reviewed S12 model count")
	catalog_path=canonical(str(published.get("catalog_path","")))
	check(catalog_path==canonical(Paths.external_root().path_join("packs/default/assets/library.json")),"normal shared library path")
	check(Packs.new().packs().any(func(pack):return canonical(pack.root)==catalog_path.get_base_dir().get_base_dir() and pack.shared),"shared pack discovered normally")
	if failed!=initial:return false
	var library:=Library.new(catalog_path.get_base_dir())
	readonly_guards[receipt_path]=FileAccess.get_sha256(receipt_path)
	readonly_guards[catalog_path]=library._revision
	var seen:Dictionary={}
	for item:Dictionary in published.items:
		var id:String=str(item.get("id",""));var target:=canonical(str(item.get("target","")))
		var sha:String=str(item.get("sha256",""))
		check(id in expected_ids and not seen.has(id),"exact unique selected ID "+id);seen[id]=true
		check(Paths.allowed(target,catalog_path.get_base_dir()) and target.get_file()==sha+".glb" and sha.length()==64,"immutable target confined "+id)
		check(FileAccess.get_sha256(target)==sha,"actual formal source SHA "+id)
		check(FileAccess.get_sha256(item.acceptance_report)==item.acceptance_report_sha256,"same exact scoped review "+id)
		if failed!=initial:return false
		var proof:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(item.acceptance_report))
		check(proof.get("passed",false) and proof.get("acceptance_stage")=="structure_and_layout_candidate" and proof.get("source_sha256")==sha,"explicit structure-stage acceptance only "+id)
		check(proof.get("generator")==Compile.generator(),"same reviewed production generator "+id)
		check(FileAccess.get_sha256(proof.gpu_report.path)==proof.gpu_report.sha256,"unchanged native/GPU report "+id)
		var matches:Array=library.entries.filter(func(entry):return canonical(str(entry.get("asset_path","")))==target)
		check(matches.size()==1 and matches[0].get("label")==item.label and matches[0].get("category")==item.category,"exact formal catalog entry "+id)
		if failed!=initial:return false
		var entry:Dictionary=matches[0];var thumb:String=entry.thumbnail_path
		var pixels:=Image.load_from_file(thumb)
		check(pixels!=null and not pixels.is_empty() and not pixels.is_invisible(),"normal published thumbnail readable "+id)
		var native:=Library._verified_compiled_identity(target)
		check(not native.is_empty() and native.get("source_sha")==sha,"formal native payload/current generator "+id)
		for path:String in [target,thumb,item.acceptance_report,proof.gpu_report.path]:readonly_guards[path]=FileAccess.get_sha256(path)
		audit.items.append({"id":id,"input_sha":sha,"output_sha":sha,"output_path":target,"entry":entry.duplicate(true),"formal_native_identity":native,"prior_visual_review":item.acceptance_report,"prior_visual_review_sha256":item.acceptance_report_sha256,"near_material_pending":proof.get("near_material_pending"),"acceptance_stage":proof.acceptance_stage})
	for path:String in published.get("protected_maps",{}):
		check(FileAccess.get_sha256(path)==published.protected_maps[path],"protected real map unchanged since publication "+path)
		readonly_guards[path]=FileAccess.get_sha256(path)
	audit.scope="Selected S12 models: real shared catalog discovery, placement, selection, activity, undo/redo, save/reopen in a new owned cache map. No real-town deployment; visual approval is limited to each cited source review."
	audit.published_count=expected_ids.size();audit.catalog_sha_at_publication=published.catalog_sha_after;audit.catalog_sha_at_verification=library._revision
	audit.mcp_import_limit="No generic GLB file-import endpoint; publication used shared UI AssetLibrary importer. This verifies real HTTP discovery/use/persistence."
	return failed==initial
