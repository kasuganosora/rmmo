extends SceneTree
## Real-renderer regression: lossless mips, alpha, normal orientation, source
## replacement and worker-to-main upload. All source files are temporary.
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var failures:=0
var checks:=0
var retained:Array=[]
var files:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func canonical(image:Image)->PackedByteArray:
	var copy:=Image.create_from_data(image.get_width(),image.get_height(),image.has_mipmaps(),image.get_format(),image.get_data())
	if copy.get_format()==Image.FORMAT_RGB8:copy.convert(Image.FORMAT_RGBA8)
	return copy.get_data()
func load_worker(path:String,flip:bool)->Image:
	var worker:=Thread.new()
	if worker.start(Pixels.image.bind(path,flip))!=OK:
		check(false,"worker starts");return null
	while worker.is_alive():await process_frame
	return worker.wait_to_finish()
func run()->void:
	if DisplayServer.get_name()=="headless":push_error("real renderer required");quit(1);return
	var folder:=Paths.cache_directory("upload_pixels_test_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var rgb:=Image.create(19,13,false,Image.FORMAT_RGB8)
	for y in rgb.get_height():
		for x in rgb.get_width():rgb.set_pixel(x,y,Color(float(x%7)/6.,float(y%5)/4.,float((x+y)%9)/8.))
	var rgba:=Image.create(19,13,false,Image.FORMAT_RGBA8)
	for y in rgba.get_height():
		for x in rgba.get_width():rgba.set_pixel(x,y,Color(.2,.7,.4,float((x+y)%3)/2.))
	var mono:=Image.create(19,13,false,Image.FORMAT_L8);mono.fill(Color(.3,.3,.3))
	for source:Image in [rgb,rgba,mono]:
		var path:=folder.path_join("image_%d.png"%source.get_format());files.append(path)
		check(source.save_png(path)==OK,"save temporary source")
		for flip:bool in [false,true]:
			Pixels.upload_preparation_enabled=false
			var legacy:=await load_worker(path,flip);files.append(Pixels.cache_path(path,flip))
			Pixels.upload_preparation_enabled=true
			var fresh:=await load_worker(path,flip);files.append(Pixels.cache_path(path,flip))
			var cached:=await load_worker(path,flip)
			if legacy==null or fresh==null or cached==null:check(false,"worker images");continue
			check(canonical(legacy)==canonical(fresh) and canonical(fresh)==canonical(cached),"every pixel/mip channel agrees across legacy, prepared and cached")
			check(fresh.get_format()!=Image.FORMAT_RGB8 and fresh.get_mipmap_count()==legacy.get_mipmap_count(),"upload format prepared without changing mip count")
			check(fresh.get_meta("runtime_upload_has_alpha")== (legacy.detect_alpha()!=Image.ALPHA_NONE) and cached.get_meta("runtime_upload_has_alpha")==fresh.get_meta("runtime_upload_has_alpha"),"alpha classification survives disk cache")
			check(fresh.get_meta("runtime_source_sha256")==FileAccess.get_sha256(path),"prepared image retains source identity")
			var encoded:=FileAccess.open(Pixels.cache_path(path,flip),FileAccess.READ)
			encoded.seek(32)
			var stored:Dictionary=bytes_to_var(encoded.get_buffer(encoded.get_length()-32));encoded.close()
			check(stored.format==legacy.get_format() and stored.size==legacy.get_data().size(),"disk cache keeps compact original channels while worker result is upload ready")
			var texture:=ImageTexture.create_from_image(fresh);retained.append(texture)
			RenderingServer.force_sync()
			var readback:=texture.get_image()
			check(readback!=null and canonical(readback)==canonical(legacy),"GPU pixels and every mip preserve original channels")
			var file:=FileAccess.open(Pixels.cache_path(path,flip),FileAccess.WRITE);file.store_string("corrupt");file.close()
			var repaired:=await load_worker(path,flip)
			check(repaired!=null and canonical(repaired)==canonical(legacy),"corrupt prepared cache rebuilds from original")
	var changed_path:=files[0]
	var definition:={"name":"upload alpha","texture_path":changed_path,"color":[1,1,1,1],"roughness":.8}
	var old_image:=await load_worker(changed_path,false)
	Paint.prepare_images({changed_path:old_image})
	var old_material:=Paint.make_material(definition)
	var old_texture:Texture2D=old_material.albedo_texture
	check(old_material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"old opaque material and GPU texture are resident before source replacement")
	rgba.save_png(changed_path)
	var replacement:=await load_worker(changed_path,false)
	check(replacement.get_meta("runtime_upload_has_alpha") and replacement.get_meta("runtime_source_sha256")==FileAccess.get_sha256(changed_path),"same path replacement updates alpha and identity")
	Paint.prepare_images({changed_path:replacement})
	var material:=Paint.make_material(definition)
	check(material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"prepared alpha reaches real material")
	check(material!=old_material and material.albedo_texture!=old_texture and material.albedo_texture.get_meta("runtime_source_sha256")==FileAccess.get_sha256(changed_path),"same-path replacement invalidates resident material and GPU texture")
	RenderingServer.force_sync()
	check(canonical(material.albedo_texture.get_image())==canonical(replacement) and canonical(old_texture.get_image())==canonical(old_image),"replacement GPU mip pixels update without mutating the old shared texture")
	var arbitrary:=Image.create(4,4,false,Image.FORMAT_RGBA8);arbitrary.fill(Color(1,0,0,.4))
	Paint._textures.clear();Paint._materials.clear();Paint.prepared_images={changed_path:arbitrary}
	material=Paint.make_material(definition)
	check(material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"caller image without preparation metadata still scans alpha")
	material=null;old_material=null;old_texture=null;Paint._textures.clear();Paint._materials.clear();Paint.prepared_images.clear()
	RenderingServer.force_sync();retained.clear();RenderingServer.force_sync()
	for path:String in files:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	print("TEXTURE_UPLOAD_PREPARATION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
