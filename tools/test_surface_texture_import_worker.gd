extends SceneTree
## CPU worker contract. Run with --root=<fresh external content directory>.
const Worker=preload("res://scripts/world_editor/surface_texture_import_worker.gd")
const DDS=preload("res://scripts/world3d/compressed_texture_source.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
var checks:=0
var failures:Array[String]=[]
var source_reads:Array=[]
class ShortJpegReader extends RefCounted:
	func read(offset:int,count:int)->PackedByteArray:
		if offset==0:
			var header:=PackedByteArray();header.resize(count)
			header[0]=255;header[1]=216;header[2]=255;header[3]=255
			return header
		if offset==2:return PackedByteArray([255,255])
		return PackedByteArray() # source truncated between marker reads
class FaultWriter extends RefCounted:
	var suffix:String
	var calls:Array[String]=[]
	func _init(value:String)->void:suffix=value
	func write(path:String,bytes:PackedByteArray)->Error:
		calls.append(path)
		if path.ends_with(suffix):return ERR_FILE_CANT_WRITE
		return Library._write(path,bytes)

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)

func _initialize()->void:run.call_deferred()

func _work(callable:Callable)->Dictionary:
	var thread:=Thread.new()
	if thread.start(callable)!=OK:return {"ok":false,"error":"test thread start failed"}
	while thread.is_alive():await process_frame
	return thread.wait_to_finish()

static func _unavailable(_image:Image,_channels:int)->int:return ERR_UNAVAILABLE
static func _headless_encoder(image:Image,channels:int)->int:
	if DisplayServer.get_name()!="headless":return ERR_UNAVAILABLE
	return image.compress_from_channels(Image.COMPRESS_S3TC,channels)
func _observe_source_read(length:int)->void:source_reads.append(length)

func run()->void:
	var root:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):root=arg.trim_prefix("--root=").replace("\\","/")
	if root.is_empty() or not root.is_absolute_path():push_error("--root=<fresh external content directory> required");quit(1);return
	var folder:=root.path_join("worker_%d"%OS.get_process_id())
	if DirAccess.dir_exists_absolute(folder):push_error("fixture directory already exists");quit(1);return
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"create isolated fixture")
	var library:=folder.path_join("materials")
	var source:=folder.path_join("source.png")
	var image:=Image.create(16,8,false,Image.FORMAT_RGBA8);image.fill(Color(.2,.4,.8,1.0))
	check(image.save_png(source)==OK,"create opaque source")
	var token:=Drainer.CancelToken.new()
	check(not Worker.run(source,library,"main",token,root).ok,"reject main-thread execution")
	var truncated:=ShortJpegReader.new()
	check(Worker._image_dimensions(truncated.read,64,"jpg").is_empty(),"short JPEG marker read fails safely without indexing an empty buffer")
	for extension:String in ["jpg","webp"]:
		var format_path:=folder.path_join("format."+extension)
		var saved:int=image.save_jpg(format_path) if extension=="jpg" else image.save_webp(format_path)
		check(saved==OK,"create "+extension+" input")
		if saved==OK:
			var format_probe:Dictionary=await _work(Worker.probe.bind(format_path,library,token,root))
			check(format_probe.get("ok",false) and format_probe.width==16 and format_probe.height==8,extension+" header yields actual dimensions")
			var format_snapshot:Dictionary=await _work(Worker.prepare.bind(format_path,library,token,root,format_probe))
			check(format_snapshot.get("ok",false),extension+" snapshot decodes after admitted probe")
	var probe:Dictionary=await _work(Worker.probe.bind(source,library,token,root))
	check(probe.ok and probe.width==16 and probe.height==8 and probe.estimated_bytes<16*1024*1024,"header probe admits actual dimensions, not a fixed maximum image")
	var wide_path:=folder.path_join("wide.png")
	var wide:=Image.create(4097,1,false,Image.FORMAT_RGBA8);wide.fill(Color(.1,.7,.3))
	check(wide.save_png(wide_path)==OK,"create actual image beyond former 4096 limit")
	var wide_probe:Dictionary=await _work(Worker.probe.bind(wide_path,library,token,root))
	var wide_prepared:Dictionary=await _work(Worker.prepare.bind(wide_path,library,token,root,wide_probe)) if wide_probe.get("ok",false) else {}
	check(wide_prepared.get("ok",false) and wide_prepared.image.get_width()==4097,"wide source is admitted and decoded without resize")
	var large_path:=folder.path_join("large_source.png")
	var large_file:=FileAccess.open(large_path,FileAccess.WRITE)
	large_file.store_buffer(image.save_png_to_buffer());large_file.resize(16*1024*1024+1);large_file.close()
	var large_probe:Dictionary=await _work(Worker.probe.bind(large_path,library,token,root))
	check(large_probe.get("ok",false) and large_probe.source_bytes==16*1024*1024+1,"probe accepts valid image header with source beyond former 16 MiB limit")
	var large_prepared:Dictionary=await _work(Worker.prepare.bind(large_path,library,token,root,large_probe)) if large_probe.get("ok",false) else {}
	check(large_prepared.get("ok",false),"actual oversized source is read and decoded under its admitted estimate")
	var work8k:=Worker._workspace(8192,8192,16*1024*1024)
	check(not work8k.is_empty() and work8k.mip_bytes==357913940 and work8k.bc3_bytes==89478512 and work8k.estimated_bytes<4*1024*1024*1024,"8K reservation accounts actual mip and BC3 bounds instead of a 4 GiB pixel multiplier")
	check(Worker._workspace(16384,16385,1).is_empty() and Worker._workspace(8192,8192,9223372036854775807).is_empty(),"engine pixel and integer representation bounds reject before allocation")
	if probe.ok:
		var changed:Dictionary=probe.duplicate();changed.width=32
		var mismatch:Dictionary=await _work(Worker.prepare.bind(source,library,token,root,changed))
		check(not mismatch.ok and mismatch.get("retry_probe",false),"changed dimensions cause retry before decode")
		var grown:=folder.path_join("grown.png")
		var grow_file:=FileAccess.open(grown,FileAccess.WRITE)
		grow_file.resize(16*1024*1024);grow_file.close()
		var grown_result:Dictionary=await _work(Worker.prepare.bind(grown,library,token,root,probe,Callable(self,"_observe_source_read")))
		check(not grown_result.ok and grown_result.get("retry_probe",false) and source_reads.is_empty(),"grown source retries before allocating or reading the new 16 MiB buffer")
	var prepared:Dictionary=await _work(Worker.prepare.bind(source,library,token,root))
	check(prepared.ok and not FileAccess.file_exists(prepared.get("texture_path","")),"prepare retains private pixels without publication")
	var first:Dictionary=await _work(Worker.encode_publish.bind(prepared,token,root,Callable(self,"_headless_encoder"))) if prepared.ok else prepared
	check(first.ok,"background preparation succeeds")
	if first.ok:
		check(FileAccess.get_sha256(first.texture_path)==first.content_id,"canonical PNG content address")
		var thumb:=Image.load_from_file(first.texture_path+".thumbnail.png")
		check(thumb!=null and thumb.get_width()<=104 and thumb.get_height()<=64 and thumb.get_width()*8==thumb.get_height()*16,"producer writes one small aspect-preserving thumbnail")
		var thumb_file:=FileAccess.open(first.texture_path+".thumbnail.json",FileAccess.READ)
		var thumb_meta:Variant=JSON.parse_string(thumb_file.get_as_text()) if thumb_file!=null else null
		if thumb_file!=null:thumb_file.close()
		check(thumb_meta is Dictionary and thumb_meta.get("source_sha256","")==first.content_id and int(thumb_meta.get("source_bytes",0))==FileAccess.get_file_as_bytes(first.texture_path).size(),"thumbnail metadata refers to the canonical PNG")
		check(DirAccess.remove_absolute(first.texture_path+".thumbnail.json")==OK,"simulate interrupted thumbnail identity publication")
		var recovered:Dictionary=await _work(Worker.encode_publish.bind(prepared,token,root,Callable(self,"_headless_encoder")))
		check(recovered.get("ok",false) and FileAccess.file_exists(first.texture_path+".thumbnail.json"),"repeat import repairs missing thumbnail identity without rereading its source")
		var retained:Dictionary=await _work(Worker.encode_publish.bind(prepared,token,root,Callable(self,"_headless_encoder"),Callable(),true))
		check(retained.get("ok",false) and retained.get("prepared_image") is Image and retained.prepared_image.get_meta("runtime_source_sha256","")==first.content_id,"producer returns joined image with content identity when requested")
		retained.erase("prepared_image")
		if first.dds_ready:
			var row:=DDS.plan_mutable(first.texture_path,false,false,root,first.content_id)
			check(not row.is_empty() and row.format==Image.FORMAT_DXT1 and DDS.read(row)!=null,"opaque DDS is readable BC1 with matching identity")
			var again:Dictionary=await _work(Worker.encode_publish.bind(prepared,token,root,Callable(self,"_headless_encoder")))
			check(again.ok and again.dds_ready and again.dds_reused,"same content reuses validated sidecar")
		else:
			check(first.dds_reason=="encoder_unavailable_or_failed","unavailable encoder explicitly falls back to PNG")
		var a:Dictionary=await _work(Worker.publish_material.bind(first,"one",token,root))
		var b:Dictionary=await _work(Worker.publish_material.bind(first,"two",token,root))
		check(a.ok and b.ok and a.material_id!=b.material_id and a.material.texture_path==b.material.texture_path,"shared pixels and distinct label identities")
		var cancelled:=Drainer.CancelToken.new();cancelled.cancel()
		var c:Dictionary=await _work(Worker.publish_material.bind(first,"cancelled",cancelled,root))
		var cancelled_id:=(str(first.content_id)+"cancelled").sha256_text()
		check(not c.ok and not FileAccess.file_exists(library.path_join(cancelled_id+".json")),"cancellation before material publish has no material")
	var unavailable_source:=folder.path_join("unavailable.png")
	image.fill(Color(.8,.3,.1));check(image.save_png(unavailable_source)==OK,"create unavailable-encoder input")
	var unavailable_prepared:Dictionary=await _work(Worker.prepare.bind(unavailable_source,library,token,root))
	if not image.has_method("compress_from_channels_cpu"):
		var no_api:Dictionary=await _work(Worker.encode_publish.bind(unavailable_prepared,token,root))
		check(no_api.get("ok",false) and not no_api.get("dds_ready",true) and no_api.get("dds_reason","")=="encoder_unavailable_or_failed","old engine safely keeps PNG without invoking GPU compression")
	var unavailable:Dictionary=await _work(Worker.encode_publish.bind(unavailable_prepared,token,root,Callable(self,"_unavailable")))
	check(unavailable.ok and not unavailable.dds_ready and unavailable.dds_reason=="encoder_unavailable_or_failed","encoder failure preserves PNG fallback")
	if unavailable.ok:
		var png_retained:Dictionary=await _work(Worker.encode_publish.bind(unavailable_prepared,token,root,Callable(self,"_unavailable"),Callable(),true))
		check(png_retained.get("ok",false) and png_retained.get("prepared_image") is Image and not png_retained.prepared_image.is_compressed() and png_retained.prepared_image.has_mipmaps(),"PNG fallback hands off upload-ready CPU pixels without rereading")
		png_retained.erase("prepared_image")
		var png:=Image.load_from_file(unavailable.texture_path)
		check(png!=null and png.get_width()==16 and png.get_height()==8,"fallback retains exact dimensions")
		var stale:String=unavailable.texture_path+".dxt5.dds"
		var file:=FileAccess.open(stale,FileAccess.WRITE);file.store_buffer(PackedByteArray([1,2,3]));file.close()
		var conflict:Dictionary=await _work(Worker.encode_publish.bind(unavailable_prepared,token,root,Callable(self,"_unavailable")))
		check(not conflict.ok and FileAccess.file_exists(stale),"invalid existing sidecar fails explicitly without deleting it")
	var odd_source:=folder.path_join("odd.png")
	var odd:=Image.create(13,7,false,Image.FORMAT_RGBA8);odd.fill(Color(.3,.7,.2))
	check(odd.save_png(odd_source)==OK,"create non-multiple-of-four source")
	var odd_prepared:Dictionary=await _work(Worker.prepare.bind(odd_source,library,token,root))
	var odd_result:Dictionary=await _work(Worker.encode_publish.bind(odd_prepared,token,root))
	check(odd_result.ok and not odd_result.dds_ready and odd_result.dds_reason=="dimensions_not_multiple_of_four","odd dimensions use PNG fallback")
	if odd_result.ok:
		var decoded:=Image.load_from_file(odd_result.texture_path)
		check(decoded!=null and decoded.get_width()==13 and decoded.get_height()==7,"fallback preserves odd dimensions")
	for suffix:String in [".source.json",".dds"]:
		var fault_source:=folder.path_join("fault_"+suffix.replace(".","_")+".png")
		image.fill(Color(.1 if suffix==".dds" else .7,.6,.4));image.save_png(fault_source)
		var fault_prepared:Dictionary=await _work(Worker.prepare.bind(fault_source,library,token,root))
		var fault:=FaultWriter.new(suffix)
		var fallback:Dictionary=await _work(Worker.encode_publish.bind(fault_prepared,token,root,Callable(self,"_headless_encoder"),fault.write))
		check(fallback.get("ok",false) and not fallback.get("dds_ready",true) and fallback.get("dds_reason","") in ["dds_write_failed","dds_identity_write_failed"],"DDS publication failure falls back to PNG "+suffix)
		check(DDS.sidecar_path(fallback.get("texture_path",""),false,false).is_empty(),"failure leaves no selectable DDS "+suffix)
	var alpha_source:=folder.path_join("alpha.png")
	image.fill(Color(.3,.5,.8,.4));check(image.save_png(alpha_source)==OK,"create alpha source")
	var alpha_prepared:Dictionary=await _work(Worker.prepare.bind(alpha_source,library,token,root))
	var alpha:Dictionary=await _work(Worker.encode_publish.bind(alpha_prepared,token,root,Callable(self,"_headless_encoder")))
	check(alpha.ok,"alpha preparation succeeds")
	if alpha.ok and alpha.dds_ready:
		var row:=DDS.plan_mutable(alpha.texture_path,false,false,root,alpha.content_id)
		check(not row.is_empty() and row.format==Image.FORMAT_DXT5 and DDS.read(row)!=null,"alpha DDS is readable BC3")
	print("SURFACE_TEXTURE_IMPORT_WORKER ",JSON.stringify({"checks":checks,"failures":failures,"fixture":folder}))
	quit(0 if failures.is_empty() else 1)
