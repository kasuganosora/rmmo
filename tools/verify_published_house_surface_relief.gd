extends "res://tools/diagnose_house_surface_relief.gd"
## Reads the real shared material catalog after publication. Only new owned
## cache maps and this review report are writable; historical maps stay guarded.
var publication_path:=""

func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("PUBLISHED_SURFACE_VERIFY syntax only");quit();return
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--receipt="):publication_path=arg.trim_prefix("--receipt=")
	if DisplayServer.get_name()=="headless" or publication_path.is_empty():quit(2);return
	var receipt:Variant=JSON.parse_string(FileAccess.get_file_as_string(publication_path))
	check(receipt is Dictionary and receipt.get("passed",false) and receipt.get("mode")=="publish","complete successful publication receipt")
	if failed>0:quit(1);return
	variant="published";output_label="";evidence=diagnostic
	evidence.catalog_source="Actual formal default pack; no catalog snapshot or content-root override."
	evidence.receipt_path=publication_path;evidence.receipt_sha256=FileAccess.get_sha256(publication_path)
	guards=receipt.protected_files_after.duplicate(true);guards[publication_path]=FileAccess.get_sha256(publication_path)
	fixture_root=Paths.cache_directory("house_surface_published_verify_%d"%Time.get_ticks_usec())
	check(not DirAccess.dir_exists_absolute(fixture_root),"new owned cache map directory")
	DirAccess.make_dir_recursive_absolute(fixture_root)
	var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(INVENTORY))
	inventory={"items":[]}
	for published:Dictionary in receipt.items:
		var family:String=published.id
		var definition_path:String=published.definition_path
		check(FileAccess.get_sha256(definition_path)==published.actual_after_sha256 and published.actual_after_sha256==published.planned_after_sha256,"formal descriptor matches publication "+family)
		guards[definition_path]=published.actual_after_sha256
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(definition_path))
		check(data.material==published.formal_material,"formal material dictionary exact "+family)
		var accepted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(published.evidence.gpu_report_path))
		check(accepted.passed and accepted.http and FileAccess.get_sha256(published.evidence.gpu_report_path)==published.evidence.gpu_report_sha256,"selected GPU evidence intact "+family)
		var costs:Dictionary={"definition_path":definition_path,"definition_sha256":guards[definition_path],"definition":data.material,"channels":{}}
		for field:String in Paint.MAP_FIELDS:
			var path:=str(data.material.get(field,""))
			if path.is_empty():continue
			if not path.is_absolute_path():path=definition_path.get_base_dir().path_join(path).simplify_path()
			var digest:=FileAccess.get_sha256(path)
			check(accepted.material.channels.has(field) and digest==accepted.material.channels[field].source_sha256,"formal channel identical to accepted candidate "+family+" "+field)
			guards[path]=digest
			var image:=Image.load_from_file(path)
			var file:=FileAccess.open(path,FileAccess.READ);var bytes:=file.get_length();file.close()
			costs.channels[field]={"source":path,"source_sha256":digest,"test_path":path,"test_sha256":digest,"encoded_bytes":bytes,"width":image.get_width(),"height":image.get_height(),"decoded_format":image.get_format(),"decoded_bytes":image.get_data().size(),"rgba8_full_mips_budget_bytes":ceili(image.get_width()*image.get_height()*4.*4./3.)}
		channels[family]=costs
		var item:Dictionary=baseline.items.filter(func(value):return value.id==family)[0].duplicate(true)
		item.definition_path=definition_path;item.definition_sha256=published.actual_after_sha256
		inventory.items.append(item)
	check(inventory.items.size()==3,"only two published roofs and one published exterior wall")
	check(Paths.external_root()=="D:/code/rmmo_runtime","actual formal content root active")
	if failed>0:flush();quit(1);return
	Engine.max_fps=60;rpc_timeout_ms=240000;root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	evidence.fixture_root=fixture_root;evidence.render={"msaa":"4x","taa":true,"exposure":1.,"tonemap":"ACES","environment":fixed_env}
	await setup_editor()
	for item:Dictionary in inventory.items:
		await review_family(item)
		if failed>0:break
		var row:Dictionary=evidence.items[-1]
		row.bound_formal_materials=audit_bound_materials(row)
		row.passed=failed==0
		put(current_folder.path_join("report.json"),row);flush()
	editor._mcp.stop();editor.queue_free();await settle()
	for path:String in guards:check(FileAccess.get_sha256(path)==guards[path],"formal material/map/catalog/receipt read-only "+path.get_file())
	evidence.erase("active");evidence.completed=true;flush()
	print("PUBLISHED_SURFACE_VERIFY failures=",failed);quit(0 if failed==0 else 1)
