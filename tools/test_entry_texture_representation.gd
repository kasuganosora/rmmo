extends "res://tools/test_prefab_texture_preparation.gd"
## Both engine versions must use the declared immutable DDS representation at
## entry, with the same identity later chunks use; editor provenance is irrelevant.
const Loader=preload("res://scripts/world3d/map_loader.gd")
const DdsFixture=preload("res://tools/test_compressed_texture_source.gd")
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9)
	if output.is_empty():quit(2);return
	create_timer(30).timeout.connect(func():quit(2))
	var logger:=Errors.new();OS.add_logger(logger)
	Pixels.Policy.verify_packages=false
	files=Files.new();files.content_root=Prep.Paths.external_root();files.folder=output.get_base_dir()
	var path:String=files.folder.path_join("entry.png")
	var source:=Image.create(8,8,false,Image.FORMAT_RGBA8);source.fill(Color.RED)
	check(source.save_png(path)==OK,"save immutable source fixture")
	var sha:=FileAccess.get_sha256(path)
	var helper:=DdsFixture.new();var bytes:PackedByteArray=helper.dds(8,8,"DXT1");helper.free()
	var f:=FileAccess.open(path+".dxt1.dds",FileAccess.WRITE);f.store_buffer(bytes);f.close()
	var loader:=Loader.new();loader._content_root=files.content_root
	var requested:Dictionary={path:[path,false,false]}
	var worker:=Thread.new();worker.start(loader._decode_textures.bind(requested))
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish();var image:Image=packet.images.get(path)
	check(packet.get("error","").is_empty() and image!=null,"real entry worker completes")
	check(image!=null and image.get_format()==Image.FORMAT_DXT1 and image.get_data()==bytes.slice(128),"entry preserves the published DDS blocks without editor provenance or recompression")
	check(image!=null and image.get_meta("runtime_source_sha256","")==path.sha256_text(),"entry identity matches the immutable chunk path identity")
	check(FileAccess.get_sha256(path)==sha,"entry preserves source file")
	loader.free();packet.clear();image=null;files.free()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	f=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify({"checks":passed+failed,"failures":failed}));f.close()
	quit(1 if failed else 0)
