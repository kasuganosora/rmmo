extends SceneTree
## Headless codec/cache regression; no texture upload or authored assets.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
var checks:=0
var failures:Array[String]=[]

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)

func _initialize()->void:run.call_deferred()

func check_upload_accounting(folder:String,fixture:Dictionary)->void:
	# Dummy/headless can exercise bookkeeping, but does not prove GPU upload.
	var source:=folder.path_join("upload_probe_%d.png"%OS.get_process_id())
	var image:=Image.create(int(fixture.width),int(fixture.height),false,Image.FORMAT_RGBA8)
	image.fill(Color(.35,.59,.86));check(image.save_png(source)==OK,"create isolated upload accounting source")
	var sidecar:=source+".dxt1.dds"
	var file:=FileAccess.open(sidecar,FileAccess.WRITE);file.store_buffer(FileAccess.get_file_as_bytes(fixture.path));file.close()
	Paint.refresh_sources();Paint.texture_profile_enabled=true;Paint.reset_profile()
	var texture:Texture2D=Paint.texture({"texture_path":source})
	check(texture!=null,"sidecar material creates a texture owner")
	var counters:Dictionary=Paint.profile_snapshot().counters
	check(int(counters.get("paint.texture.sidecar_upload_bytes",0))==int(fixture.image_bytes),"DDS compressed bytes have a separate counter")
	check(int(counters.get("paint.texture.upload_bytes",0))==int(fixture.image_bytes),"total uploaded bytes include DDS branch")
	check(int(counters.get("paint.texture.sidecar_uploads",0))==1,"one DDS submission recorded")
	check(Paint.texture({"texture_path":source})==texture,"repeat lookup keeps the same texture")
	check(Paint.profile_snapshot().counters==counters.merged({"paint.texture.gpu_cache_hit":1},true),"cache hit does not count another DDS upload")
	Paint.texture_profile_enabled=false;Paint.refresh_sources()

func check_editor_import(folder:String,dds:String)->void:
	var source:=folder.path_join("editor_source_%d.png"%OS.get_process_id())
	var library:=Library.new(folder.path_join("editor_library_%d"%OS.get_process_id()))
	var image:=Image.create(16,8,false,Image.FORMAT_RGBA8);image.fill(Color(.35,.59,.86))
	check(image.save_png(source)==OK,"create mutable editor import source")
	var first:Dictionary=library.import_texture(source,"shared UI/MCP import")
	check(first.ok,"existing editor business import publishes original")
	if not first.ok:return
	var original_path:String=first.material.texture_path
	var original_sha:=FileAccess.get_sha256(original_path)
	var old_dds:=original_path+".dxt1.dds"
	var file:=FileAccess.open(old_dds,FileAccess.WRITE);file.store_buffer(FileAccess.get_file_as_bytes(dds));file.close()
	var dds_sha:=FileAccess.get_sha256(old_dds)
	check(Paint.has_compressed_sidecar(original_path),"old published content has a resident sidecar key")
	image.fill(Color(.9,.2,.15));check(image.save_png(source)==OK,"modify only mutable import source")
	var second:Dictionary=library.import_texture(source,"shared UI/MCP import")
	check(second.ok,"existing editor business import publishes changed content")
	if not second.ok:return
	check(second.material.texture_path!=original_path and second.material_id!=first.material_id,"changed content receives new PNG and material identity")
	check(not Paint.has_compressed_sidecar(second.material.texture_path),"old DDS and lookup cache cannot cross new published path")
	check(FileAccess.get_sha256(original_path)==original_sha and FileAccess.get_sha256(old_dds)==dds_sha,"reimport preserves previous published PNG/DDS")
	var reopened:=Library.new(library.directory)
	check(reopened.find(first.material_id).texture_path==original_path,"reopened catalog retains original frozen reference")
	check(reopened.find(second.material_id).texture_path==second.material.texture_path,"reopened catalog resolves changed reference")
	var unchanged:Dictionary=reopened.import_texture(source,"shared UI/MCP import")
	check(unchanged.ok and unchanged.material.texture_path==second.material.texture_path,"unchanged import reuses immutable published identity")

func run()->void:
	var input:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixtures="):input=arg.trim_prefix("--fixtures=")
	input=input.replace("\\","/")
	if input.is_empty():push_error("--fixtures=<external fixtures.json> required");quit(1);return
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input))
	for fixture:Dictionary in manifest.fixtures:
		var image:=Image.new()
		check(image.load_dds_from_buffer(FileAccess.get_file_as_bytes(fixture.path))==OK,"decode complete DDS "+fixture.path.get_file())
		check(image.get_width()==int(fixture.width) and image.get_height()==int(fixture.height),"preserve source dimensions")
		check(image.has_mipmaps() and image.get_mipmap_count()==int(fixture.mipmaps),"preserve complete mip chain")
		check(image.get_data_size()==int(fixture.image_bytes),"account compressed mip bytes")
		check(image.decompress()==OK,"CPU decompress mip chain")
		var final_pixels:=image.get_data_size()-image.get_mipmap_offset(image.get_mipmap_count())
		check(final_pixels==2 or final_pixels==3 or final_pixels==4,"smallest decoded mip contains one RG/RGB/RGBA texel")
	var color_fixture:Dictionary={}
	for fixture:Dictionary in manifest.fixtures:
		if fixture.path.ends_with("opaque.png.dxt1.dds"):color_fixture=fixture;break
	check(not color_fixture.is_empty(),"fixture contains actual RGB DXT1")
	var path:=input.get_base_dir().path_join("cache_probe_%d.png"%OS.get_process_id())
	var sidecar:=path+".dxt1.dds"
	Paint.refresh_sources()
	check(not Paint.has_compressed_sidecar(path),"cache absent sidecar")
	var file:=FileAccess.open(sidecar,FileAccess.WRITE);file.store_buffer(FileAccess.get_file_as_bytes(color_fixture.path));file.close()
	check(not Paint.has_compressed_sidecar(path),"immutable generation keeps negative answer until explicit refresh")
	Paint.refresh_sources()
	check(Paint.has_compressed_sidecar(path),"editor source refresh discovers newly generated DDS")
	DirAccess.remove_absolute(sidecar)
	Paint.refresh_sources()
	check(not Paint.has_compressed_sidecar(path),"editor source refresh drops removed DDS")
	var flipped:=path+".flip.dxt5.dds"
	check(not Paint.has_compressed_sidecar(path,true),"cache absent converted normal")
	file=FileAccess.open(flipped,FileAccess.WRITE);file.store_buffer(FileAccess.get_file_as_bytes(color_fixture.path));file.close()
	Paint.refresh_sources()
	check(Paint.has_compressed_sidecar(path,true),"refresh invalidates normal-orientation lookup too")
	DirAccess.remove_absolute(flipped);Paint.refresh_sources()
	check_editor_import(input.get_base_dir(),color_fixture.path)
	check_upload_accounting(input.get_base_dir(),color_fixture)
	Paint.refresh_sources()
	print("DDS_SIDECAR_CHECKS ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
