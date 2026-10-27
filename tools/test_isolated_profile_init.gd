extends "res://tools/profile_axel_worker_capacity.gd"
## Headless contract check for the exact benchmark inheritance/initialization.
## Overrides run() so no gameplay, frame benchmark or GPU can start.
func run()->void:
	var failed:=0
	var manager:=root.get_node_or_null("AssetManager")
	var ok:bool=isolated_fixture and manager!=null and manager.is_node_ready() and manager.content_root()==selected_content_root and preload("res://scripts/world3d/map_paths.gd").external_root()==selected_content_root
	print("PASS " if ok else "FAIL ","actual benchmark initialization selected fixture root before autoload ready")
	if not ok:failed+=1
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(selected_map));var records:Array=[];var extra:Dictionary={}
	if data is Dictionary and data.get("nodes") is Array:
		for node:Dictionary in data.nodes:
			if node.get("extras",{}).has("rmmo_records"):extra=node.extras;break
	var restored:Dictionary=preload("res://scripts/world3d/map_resource_store.gd").read_records(extra.get("rmmo_records",[]),selected_map,selected_content_root,extra.get("rmmo_resource_dependencies",{}),1,false)
	if restored.get("ok",false):records=restored.records
	ok=restored.get("ok",false) and records.size()==3
	print("PASS " if ok else "FAIL ","real map store loads relocated fixture")
	if not ok:failed+=1
	if records.size()==3:
		preload("res://scripts/world3d/runtime_probe_controls.gd").enable_native_geometry_only()
		var path:String=records[2].asset_path
		var product:Dictionary=preload("res://scripts/world3d/white_native_asset_cache.gd").read(path,"9a1bb221422047ec2bba1393752f44c7dd8523ac431ec5f8d0da89a94ed60de9",selected_content_root,true)
		ok=product.get("hit",false) and not FileAccess.file_exists(path)
		print("PASS " if ok else "FAIL ","native cache hit on relocated key with no GLB")
		if not ok:failed+=1
	var state:="";var variant_output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture-state="):state=arg.trim_prefix("--fixture-state=")
		if arg.begins_with("--variant-report="):variant_output=arg.trim_prefix("--variant-report=")
	if state in ["A","B"]:
		var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(selected_content_root.path_join("fixture_manifest.json")))
		var rows:Array=[];var variant_failures:=0
		for variant:Dictionary in manifest.get("texture_variants",[]):
			var source:String=variant.source;var expected:String=variant.candidate_sidecar if state=="B" and not variant.candidate_sidecar.is_empty() else variant.baseline_sidecar
			var header:Dictionary=variant.candidate_header if state=="B" and not variant.candidate_sidecar.is_empty() else variant.baseline_header
			var plan:=preload("res://scripts/world3d/compressed_texture_source.gd").plan(source,variant.flip,variant.normal,selected_content_root)
			var actual:=str(plan.get("sidecar",""));var matched:=actual==expected
			if matched and not plan.is_empty():
				for key:String in ["width","height","mip_count","format"]:
					if plan.get(key)!=header.get(key):matched=false
			if not matched:variant_failures+=1
			rows.append({"source":source,"source_sha256":FileAccess.get_sha256(source),"normal":variant.normal,"flip":variant.flip,"sidecar":actual,"header":plan,"matches":matched})
		ok=variant_failures==0 and not rows.is_empty() and preload("res://scripts/world3d/map_paths.gd").allowed(variant_output,TEST_ROOT) and not FileAccess.file_exists(variant_output)
		if ok:
			var file:=FileAccess.open(variant_output,FileAccess.WRITE)
			if file==null:ok=false
			else:file.store_string(JSON.stringify({"state":state,"variants":rows,"errors":variant_failures},"\t"));file.close()
		print("PASS " if ok else "FAIL ","Godot variant source, role, selected sidecar and header recorded count=",rows.size())
		if not ok:failed+=1
	print("ISOLATED_PROFILE_INIT failures=",failed," map=",selected_map," root=",selected_content_root," user=",ProjectSettings.globalize_path("user://"))
	quit(0 if failed==0 else 1)
