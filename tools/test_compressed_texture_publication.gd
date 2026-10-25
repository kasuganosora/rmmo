extends "res://tools/test_streamed_texture_publication.gd"
## Reproduce DDS escaping the admitted CPU packet and one-upload publication
## slices. Codec fixtures are copied to a temporary external resource root.
func run()->void:
	if not check_gpu():quit(1);return
	var manifest:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixtures="):manifest=arg.trim_prefix("--fixtures=")
	if manifest.is_empty():push_error("--fixtures=<DDS fixtures.json> required");quit(2);return
	var input:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(manifest))
	var color:Dictionary={};var normal:Dictionary={}
	for row:Dictionary in input.fixtures:
		if row.path.ends_with("/opaque.png.dxt1.dds") or row.path.ends_with("\\opaque.png.dxt1.dds"):color=row
		if row.path.ends_with("/normal.png.flip.bc5.dds") or row.path.ends_with("\\normal.png.flip.bc5.dds"):normal=row
	if color.is_empty() or normal.is_empty():push_error("BC1 and flipped BC5 fixtures required");quit(2);return
	var logger:=Errors.new();OS.add_logger(logger)
	files=Files.new();files.content_root=Prep.Paths.external_root();files.folder=Prep.Paths.cache_directory("compressed_publication_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var materials:Array=[]
	for layer:int in 2:
		var paint:Dictionary={"name":"DDS layer "+str(layer),"color":[1.,1.,1.,1.],"roughness":.8,"normal_format":"directx"}
		for field:String in Paint.MAP_FIELDS:
			var fixture:Dictionary=normal if field=="normal_path" else color
			var path:String=files.folder.path_join(str(layer)+"_"+field+".png")
			var source:=Image.create(int(fixture.width),int(fixture.height),false,Image.FORMAT_RGBA8)
			source.fill(Color(.2,.6,.9,1.));check(source.save_png(path)==OK,"save isolated authored source")
			files.created.append(path);paint[field]=path
			var side:String=path+(".flip.bc5.dds" if field=="normal_path" else ".dxt1.dds")
			files.write_bytes(side,FileAccess.get_file_as_bytes(fixture.path));files.created.append(side)
		materials.append(paint)
	var terrain_helper:=TerrainFixture.new();var terrain:Dictionary=terrain_helper.fixture("dds_terrain",0);terrain_helper.free()
	terrain.collision="none";terrain.terrain_material=materials[0]
	terrain.terrain_slope_blend={"rock_material":materials[1],"steep_start":40.,"steep_end":65.}
	var requests:Dictionary=declared(terrain)
	var plan:Dictionary=Prep.estimate(requests,files.content_root)
	check(requests.size()==12 and plan.rows.size()==12,"all 12 DDS roles enter the CPU admission plan")
	var compressed:=0
	for row:Dictionary in plan.rows.values():
		if row.get("extension")=="dds":compressed+=1
	check(compressed==12,"DDS admission charges compressed mip blocks, not original PNG decoding")
	var stored:Dictionary=files.fixture("dds_request",[terrain])
	var index:Dictionary=Index.build(stored.path,files.content_root,[terrain])
	var helper:=References.new();var entries:Array=helper.entries(index,[0]);helper.free()
	var queue:=Deferred.new();queue._reference_root=files.content_root;queue._reference_index=index
	var admitted:Dictionary=queue._prefab_texture_plan({"path":"reference:dds"},entries)
	check(admitted.get("rows",{}).size()==12,"real Deferred request does not silently erase DDS sources")
	queue.free()
	var packet:Dictionary=await prepare_worker(requests,plan)
	check(packet.error.is_empty(),"DDS CPU preparation succeeds")
	for key:String in packet.get("images",{}):
		var prepared:Image=packet.images[key]
		check(prepared.is_compressed(),"worker retains compressed blocks: "+key.get_file())
		check(prepared.has_mipmaps(),"worker retains complete mip chain: "+key.get_file())
	packet.clear()
	await publication_case(terrain,false)
	await publication_case(terrain,true)
	await cancellation_case(terrain)
	await cancellation_case(terrain,true)
	one_pixel_case()
	clear_caches();Paint.texture_profile_enabled=false
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	for path:String in files.created:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	files.free()
	print("COMPRESSED_TEXTURE_PUBLICATION passed=",passed," failures=",failed)
	quit(0 if failed==0 else 1)

func one_pixel_case()->void:
	# A complete 1x1 DDS correctly has no mip flag. Its compressed bytes must
	# never enter Image.generate_mipmaps (unsupported for block compression).
	var path:String=files.folder.path_join("one_pixel.png")
	var source:=Image.create(1,1,false,Image.FORMAT_RGBA8);source.fill(Color.WHITE)
	check(source.save_png(path)==OK,"save isolated 1x1 source");files.created.append(path)
	for format:int in [Image.FORMAT_DXT1,Image.FORMAT_DXT5,Image.FORMAT_RGTC_RG]:
		clear_caches()
		var bytes:=PackedByteArray();bytes.resize(8 if format==Image.FORMAT_DXT1 else 16);bytes.fill(1)
		var image:=Image.create_from_data(1,1,false,format,bytes)
		image.set_meta("runtime_source_sha256",path.sha256_text());image.set_meta("runtime_upload_has_alpha",false)
		image.set_meta("runtime_compressed_sidecar_path",path+".dds")
		var field:="normal_path" if format==Image.FORMAT_RGTC_RG else "texture_path"
		Paint.prepare_images({Paint.texture_key(path,false,field=="normal_path"):image})
		var texture:Texture2D=Paint.texture({field:path},field)
		check(texture!=null,"1x1 compressed image publishes without mip generation")
		if texture!=null:
			RenderingServer.force_sync()
			var actual:Image=texture.get_image()
			check(actual.get_format()==format and not actual.has_mipmaps() and actual.get_data()==bytes,"1x1 GPU roundtrip retains every compressed block byte")
