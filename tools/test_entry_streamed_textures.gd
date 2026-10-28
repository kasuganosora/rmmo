extends "res://tools/test_background_texture_upload.gd"
## Actual map-entry producer must hand off the same native owners as chunks.
const Native=preload("res://scripts/world3d/streamed_texture_source.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")

func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9)
	if output.is_empty() or DisplayServer.get_name()=="headless":quit(2);return
	create_timer(30).timeout.connect(func():quit(2))
	var logger:=Errors.new();OS.add_logger(logger)
	Pixels.Policy.verify_packages=false;Paint.texture_profile_enabled=true;Pixels.profile_enabled=true
	files=Files.new();files.content_root=Prep.Paths.external_root();files.folder=output.get_base_dir()
	var path:String=files.folder.path_join("entry.png")
	var pixels:=Image.create(256,256,false,Image.FORMAT_RGBA8);pixels.fill(Color(.2,.6,.8,.7))
	check(pixels.save_png(path)==OK,"save private entry texture")
	var digest:=FileAccess.get_sha256(path);pixels.generate_mipmaps()
	var writer:=Thread.new();writer.start(Native.publish.bind(path,pixels,digest,"source",files.content_root))
	while writer.is_alive():await process_frame
	check(writer.wait_to_finish()==OK and Native.enabled(),"entry fixture has native product and renderer")
	var requested:Dictionary={path:[path,false,false]}
	var loader:=Loader.new();loader._content_root=files.content_root;root.add_child(loader)
	Pixels.reset_profile()
	var worker:=Thread.new();worker.start(loader._decode_textures.bind(requested))
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish()
	var owners:Dictionary=packet.get("uploaded_textures",{})
	check(packet.images.is_empty() and owners.size()==1,"entry producer returns a native owner without a full CPU image")
	check(int(Pixels.profile_snapshot().counters.get("texture.image.success",0))==0,"entry producer does not reopen/decode the authored source")
	var previous_images:Dictionary=Paint.prepared_images;var previous_textures:Dictionary=Paint.prepared_textures
	var outside:Texture2D=owners.get(path)
	Paint.prepared_textures={"outside-entry":outside}
	loader._decoded_images=packet.images;loader._decoded_textures=owners;loader._install_texture_handoff()
	check(Paint.prepared_textures.get("outside-entry")==outside,"entry handoff preserves an unrelated outer owner")
	var material:=Paint.make_material({"name":"entry","texture_path":path,"color":[1.,1.,1.,1.],"roughness":.8,"tile_size":[1.,1.]})
	check(material.albedo_texture!=null and material.albedo_texture==owners.get(path),"entry publication binds the actual worker owner")
	check(int(Paint.profile_snapshot().counters.get("paint.texture.upload_bytes",0))==0,"entry publication performs no full ImageTexture upload")
	var plan:=Prep.estimate(requested,files.content_root)
	var tickets:Dictionary=Prefab.texture_tickets(plan.rows)
	check(tickets.size()==1 and tickets[path].texture==owners.get(path),"following chunk borrows the entry native owner instead of loading again")
	loader.cancel()
	worker=Thread.new();worker.start(loader._decode_textures.bind(requested))
	while worker.is_alive():await process_frame
	var cancelled:Dictionary=worker.wait_to_finish()
	check(not cancelled.error.is_empty() and cancelled.images.is_empty() and cancelled.uploaded_textures.is_empty(),"cancelled entry produces no image or native owner")
	loader.free()
	check(not Paint.prepared_textures.has(path) and Paint.prepared_textures.get("outside-entry")==outside,"real loader exit releases its handoff without erasing unrelated owners")
	Paint.prepared_images=previous_images;Paint.prepared_textures=previous_textures
	material=null;tickets.clear();owners.clear();packet.clear();outside=null;clear_render()
	files.free();RenderingServer.force_sync()
	check(FileAccess.get_sha256(path)==digest,"entry test preserves source bytes")
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"checks":passed+failed,"failures":failed,"counters":Paint.profile_snapshot().counters}));file.close()
	quit(1 if failed else 0)
