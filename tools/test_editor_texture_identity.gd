extends SceneTree
## Mutable editor sources must not inherit mounted game-package path identity.
const Job=preload("res://scripts/world_editor/load_job.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Prepare=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var failures:=0
var checks:=0

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func pixels(path:String,color:Color)->void:
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8)
	image.fill(color);check(image.save_png(path)==OK,"write external texture fixture")
func red(image:Image)->bool:return image!=null and image.get_pixel(0,0).r>.95 and image.get_pixel(0,0).b<.05
func blue(image:Image)->bool:return image!=null and image.get_pixel(0,0).b>.95 and image.get_pixel(0,0).r<.05
func sha(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func put(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func dds(width:int)->PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(128)
	for i:int in 4:bytes[i]="DDS ".to_ascii_buffer()[i];bytes[84+i]="DXT1".to_ascii_buffer()[i]
	bytes.encode_u32(4,124);bytes.encode_u32(8,0x000A1007);bytes.encode_u32(12,width);bytes.encode_u32(16,width)
	bytes.encode_u32(76,32);bytes.encode_u32(80,4);bytes.encode_u32(108,0x401008)
	var levels:=1;var w:=width;var size:=0
	while true:
		size+=maxi(1,(w+3)/4)*maxi(1,(w+3)/4)*8
		if w==1:break
		w=maxi(1,w/2);levels+=1
	bytes.encode_u32(28,levels);bytes.resize(128+size)
	for offset:int in range(128,bytes.size(),8):bytes.encode_u16(offset,0xf800);bytes.encode_u16(offset+2,0xf800)
	return bytes
func publish_dds(path:String,bytes:PackedByteArray)->void:
	var source:=FileAccess.get_file_as_bytes(path)
	put(path+".dxt1.dds",bytes)
	put(path+".dxt1.dds.source.json",JSON.stringify({"version":1,"encoder_version":1,"source_sha256":sha(source),"source_bytes":source.size(),"dds_sha256":sha(bytes),"dds_bytes":bytes.size(),"normal":false,"flip":false}).to_utf8_buffer())
func decode_mutable(path:String,directory:String)->Dictionary:
	var request:Dictionary={path:[path,false,false]}
	return Job._decode_textures(request,directory,Prepare.estimate(request,directory,true))
func snapshot_cases(directory:String)->void:
	var path:=directory.path_join("snapshot_variants.png")
	pixels(path,Color(.2,.25,1.,1.))
	var color_key:=Paint.texture_key(path,false,false)
	var normal_key:=Paint.texture_key(path,false,true)
	var flipped_key:=Paint.texture_key(path,true,true)
	# This second valid path sorts between the first path and its |normal keys.
	var interposed:=path+"0.png";pixels(interposed,Color(.1,.4,.2,1.))
	var request:Dictionary={color_key:[path,false,false],normal_key:[path,false,true],flipped_key:[path,true,true],interposed:[interposed,false,false]}
	var plan:=Prepare.estimate(request,directory,true)
	var packet:=Prepare.prepare(request,plan,directory,null,true,{},false,true)
	check(packet.error.is_empty() and packet.images.size()==4,"all mutable color and normal variants publish together")
	if not packet.error.is_empty():return
	var profile:Dictionary=packet.profile
	check(profile.source_sha_reads==2 and profile.source_sha_bytes==FileAccess.get_file_as_bytes(path).size()+FileAccess.get_file_as_bytes(interposed).size(),"three variants share one snapshot despite an interposed path")
	check(profile.persist_sha_reads==0 and profile.final_sha_reads==0,"mutable cache publication and handoff do not reopen source for SHA")
	var color:Image=packet.images[color_key];var normal:Image=packet.images[normal_key];var flipped:Image=packet.images[flipped_key]
	check(absf(color.get_pixel(0,0).g-.25)<.02 and absf(normal.get_pixel(0,0).g-.25)<.02 and absf(flipped.get_pixel(0,0).g-.75)<.02,"same snapshot retains independent color, OpenGL and DirectX normal semantics")
	var captured:=str(packet.sources[path])
	pixels(path,Color(.4,.5,.6,1.))
	check(Prepare.verify(packet,directory,null,{},false,true) and str(packet.sources[path])==captured,"changed pathname does not invalidate already captured editor snapshot")
	check(absf(color.get_pixel(0,0).g-.25)<.02 and absf(flipped.get_pixel(0,0).g-.75)<.02,"captured variants remain unchanged after source replacement")
	var next:=Prepare.prepare(request,Prepare.estimate(request,directory,true),directory,null,true,{},false,true)
	check(next.error.is_empty() and next.sources[path]!=captured and absf(next.images[normal_key].get_pixel(0,0).g-.5)<.02,"next operation captures replacement source generation")
func dds_cases(directory:String)->void:
	var path:=directory.path_join("dds_editable.png")
	pixels(path,Color.RED)
	var blocks:=dds(8);publish_dds(path,blocks)
	var first:=decode_mutable(path,directory)
	var image:Image=first.images.get(path)
	check(first.failed.is_empty() and image!=null and image.is_compressed() and image.get_data()==blocks.slice(128),"editor consumes exact matching DDS blocks under full fallback budget")
	pixels(path,Color.BLUE)
	var second:=decode_mutable(path,directory)
	check(second.failed.is_empty() and blue(second.images.get(path)) and not second.images[path].is_compressed(),"stale DDS falls back to current source pixels")
	check(image.is_compressed() and image.get_data()==blocks.slice(128),"DDS fallback leaves previous image owner unchanged")
	publish_dds(path,blocks)
	var broken:=blocks.duplicate();broken[128]^=1;put(path+".dxt1.dds",broken)
	var mismatch:=decode_mutable(path,directory)
	check(mismatch.failed.is_empty() and blue(mismatch.images.get(path)),"interrupted DDS and metadata publication falls back without rejecting editable texture")
	publish_dds(path,dds(4))
	var resized:=decode_mutable(path,directory)
	check(resized.failed.is_empty() and blue(resized.images.get(path)) and resized.images[path].get_width()==8,"wrong DDS dimensions cannot replace admitted source")
	var tiny:=directory.path_join("tiny.png")
	var one:=Image.create(1,1,false,Image.FORMAT_RGBA8);one.fill(Color.BLUE);one.save_png(tiny)
	publish_dds(tiny,dds(1))
	var too_large:=decode_mutable(tiny,directory)
	check(too_large.failed.is_empty() and blue(too_large.images.get(tiny)) and not too_large.images[tiny].is_compressed(),"compressed block larger than admitted RGBA output retains bounded PNG fallback")

func run()->void:
	check(Pixels.Policy.trusted(),"default trusted package policy remains enabled")
	var directory:=Paths.cache_directory("editor_texture_identity_%d"%Time.get_ticks_usec())
	check(DirAccess.make_dir_recursive_absolute(directory)==OK,"create external fixture directory")
	for bounded:bool in [true,false]:
		var path:=directory.path_join("bounded.png" if bounded else "fallback.png")
		var request:Dictionary={path:[path,false,false]}
		pixels(path,Color.RED)
		# A prior game load may already own a path-identity disk product.
		check(red(Pixels.image(path,false)),"seed mounted game cache with red pixels")
		var first:Dictionary=Job._decode_textures(request,directory,Prepare.estimate(request,directory) if bounded else {})
		check(first.failed.is_empty() and red(first.images.get(path)),"editor initially obtains red pixels")
		var old:Image=first.images.get(path)
		pixels(path,Color.BLUE)
		var second:Dictionary=Job._decode_textures(request,directory,Prepare.estimate(request,directory) if bounded else {})
		check(second.failed.is_empty() and blue(second.images.get(path)),"same-path editor replacement refreshes pixels: bounded="+str(bounded))
		if second.images.has(path):
			check(second.images[path].get_meta("runtime_source_sha256","")==FileAccess.get_sha256(path),"editor image identifies its actual source snapshot")
		check(red(old),"refresh does not mutate previously owned image")
		check(red(Pixels.image(path,false)),"editor preparation does not overwrite mounted game's separate cache namespace")
	dds_cases(directory)
	snapshot_cases(directory)
	check(Pixels.Policy.trusted(),"editor work never flips global game trust policy")
	print("EDITOR_TEXTURE_IDENTITY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
