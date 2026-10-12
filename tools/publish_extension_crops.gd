extends SceneTree
## Explicit additive publication using the same immutable importer and thumbnails as UI.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	var library:=Library.new(preload("res://scripts/world3d/map_paths.gd").external_root().path_join("packs/default/assets"))
	var thumbnails:=preload("res://scripts/world_editor/asset_thumbnails.gd").new();root.add_child(thumbnails)
	var report:Array=[]
	for variant:String in ["ripe","green"]:
		var source:="D:/code/rmmo_runtime/art_sources/editor_extensions_20261012/wheat_lod_v2/wheat_"+variant+".glb"
		var result:=library.import_file(source)
		if not result.ok:printerr(result);quit(1);return
		var entry:Dictionary=result.entry;entry.label="成熟小麦 · 五茎（LOD）" if variant=="ripe" else "青麦 · 五茎（LOD）";entry.category="作物"
		if library.save()!=OK:printerr("catalog conflict");quit(1);return
		thumbnails.queue_import(entry)
		while thumbnails.state(entry).status=="pending":await process_frame
		if thumbnails.state(entry).status!="ready":printerr("thumbnail failed");quit(1);return
		var model:=Library.instantiate_preview(entry.asset_path)
		var vertices:=0;var triangles:=0;var surfaces:=0;var lods:=0;var images:={}
		for mesh:MeshInstance3D in Paint.meshes(model):
			for slot in mesh.mesh.get_surface_count():
				surfaces+=1;var a:Array=mesh.mesh.surface_get_arrays(slot);vertices+=a[Mesh.ARRAY_VERTEX].size();triangles+=(a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size())/3
				if mesh.mesh is ArrayMesh:lods+=RenderingServer.mesh_get_surface(mesh.mesh.get_rid(),slot).get("lods",[]).size()
				var material:Material=mesh.get_active_material(slot)
				if material is StandardMaterial3D:
					for key in ["albedo_texture","normal_texture","roughness_texture","metallic_texture","ao_texture"]:
						var texture:Texture2D=material.get(key)
						if texture!=null:
							var img:=texture.get_image();var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(img.get_data())
							images[digest.finish().hex_encode()]={"width":img.get_width(),"height":img.get_height(),"decoded_bytes":img.get_data_size(),"mips":img.has_mipmaps()}
		var item:={"entry":entry,"sha256":FileAccess.get_sha256(entry.asset_path),"source_bytes":FileAccess.get_file_as_bytes(entry.asset_path).size(),"vertices":vertices,"triangles":triangles,"surfaces":surfaces,"lod_entries":lods,"images":images,"compiled":result.get("compiled_asset",{})}
		report.append(item);model.free()
	var target:="D:/code/rmmo_runtime/review_artifacts/editor_boundaries_20261012/crops_published.json"
	DirAccess.make_dir_recursive_absolute(target.get_base_dir());FileAccess.open(target,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CROPS_PUBLISHED ",target);thumbnails.queue_free();await process_frame;quit(0)
