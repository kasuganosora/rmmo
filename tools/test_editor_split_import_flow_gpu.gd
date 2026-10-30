extends "res://tools/test_cold_asset_operations_gpu.gd"
## Exercise the existing real UI/HTTP cold-operation flow using products from
## the actual public model importer, not hand-authored native registrations.
## The isolated runner selects the candidate default; no formal pack is edited.

func run()->void:
	if not OS.get_cmdline_user_args().has("--import-only"):
		await super.run();return
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root()
	if not folder.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(90).timeout.connect(func():quit(2))
	Paint.refresh_sources();original=fixture()
	var products:=Products.prepare(original,folder)
	check(products.ok,"source fixture extraction can be restored before public import")
	cube_product(products,"import_contract")
	Products.restore(products);products.clear();original.free();original=null
	finish()

func cube_product(prepared:Dictionary,label:String)->String:
	# The inherited fixture initially demonstrates standalone extraction. Restore
	# its source before exporting the GLB that the public importer must consume.
	Products.restore(prepared)
	var exported:=original.duplicate() as Node3D
	exported.name=label
	var source:=folder.path_join("art_sources/"+label+".glb")
	check(preload("res://scripts/world3d/gltf_map_io.gd").save_scene(exported,source)==OK,"export actual textured GLB for "+label)
	exported.free()
	var library:=Assets.new(folder.path_join("imported_assets"))
	var imported:Dictionary=library.import_file(source)
	check(imported.get("ok",false),"public importer publishes complete native registration for "+label)
	if not imported.get("ok",false):printerr(imported);return ""
	var path:String=imported.entry.asset_path
	var candidate:=Assets.native_candidate(path,folder)
	check(candidate.has("texture_table"),"default import separates native geometry and texture products for "+label)
	var packed:PackedScene=ResourceLoader.load(candidate.product,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(packed!=null and Compiled.strict_image_free(packed),"imported geometry contains no embedded image resource for "+label)
	packed=null
	if OS.get_cmdline_user_args().has("--reuse-contract"):
		var repeated:Dictionary=library.import_file(path)
		check(repeated.get("ok",false) and repeated.get("compiled_asset",{}).get("reused",false),"reimport reuses the complete split product for "+label)
		check(Assets.native_candidate(path,folder)==candidate,"reimport retains the same native and texture identities for "+label)
		# Reproduce an earlier import session's successful embedded product marker.
		# The new default must upgrade it rather than accepting the old shape.
		var legacy:=Compiled.build(path,false)
		Assets._compiled_imports[path]=Assets._verified_compiled_identity(path)
		check(legacy.get("ok",false) and not Assets._compiled_imports[path].has("texture_table"),"fixture establishes a valid cached embedded product for "+label)
		var upgraded:Dictionary=library.import_file(path)
		var current:=Assets.native_candidate(path,folder)
		check(upgraded.get("ok",false) and current.has("texture_table"),"reimport upgrades the cached embedded product to split products for "+label)
		packed=ResourceLoader.load(current.product,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(packed!=null and Compiled.strict_image_free(packed),"upgraded native geometry remains image-free for "+label)
		packed=null
		report["reimport_"+label]={"repeated":repeated,"legacy":legacy,"upgraded":upgraded,"candidate":current}
	report["import_"+label]={"result":imported,"candidate":candidate,"source_sha":FileAccess.get_sha256(source)}
	check(DirAccess.remove_absolute(source)==OK,"remove fixture authoring GLB for "+label)
	check(DirAccess.remove_absolute(path)==OK,"remove importer source copy for "+label)
	check(Assets.native_available(path),"native registration remains complete without either GLB for "+label)
	owned_paths.append(path)
	return path
