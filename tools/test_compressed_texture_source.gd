extends SceneTree
## CPU-only DDS admission/worker regression. Writes only external temporary fixtures.
const Source=preload("res://scripts/world3d/compressed_texture_source.gd")
const Editor=preload("res://scripts/world_editor/terrain_texture_preparation.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Probe=preload("res://scripts/world3d/runtime_probe_controls.gd")
var checks:=0
var failures:Array[String]=[]
var directory:=""

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)

func _initialize()->void:run.call_deferred()

func put(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()

func dds(width:int,height:int,kind:String,dx10:bool=false)->PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(148 if dx10 else 128)
	for i:int in 4:bytes[i]="DDS ".to_ascii_buffer()[i]
	bytes.encode_u32(4,124);bytes.encode_u32(8,0x000A1007)
	bytes.encode_u32(12,height);bytes.encode_u32(16,width)
	bytes.encode_u32(76,32);bytes.encode_u32(80,4);bytes.encode_u32(108,0x401008)
	var code:="DX10" if dx10 else kind
	for i:int in 4:bytes[84+i]=code.to_ascii_buffer()[i]
	if dx10:
		bytes.encode_u32(128,{"DXT1":71,"DXT5":77,"ATI2":83}[kind])
		bytes.encode_u32(132,3);bytes.encode_u32(140,1)
	var mip_count:=1;var output:=0;var w:=width;var h:=height
	var block_bytes:=8 if kind=="DXT1" else 16
	while true:
		output+=maxi(1,(w+3)/4)*maxi(1,(h+3)/4)*block_bytes
		if w==1 and h==1:break
		w=maxi(1,w/2);h=maxi(1,h/2);mip_count+=1
	bytes.encode_u32(20,maxi(1,(width+3)/4)*maxi(1,(height+3)/4)*block_bytes)
	bytes.encode_u32(28,mip_count)
	var offset:=bytes.size();bytes.resize(offset+output)
	for i:int in output:bytes[offset+i]=(i*29+17)%256
	return bytes

func source_file(name:String)->String:
	var path:=directory.path_join(name+".png")
	var image:=Image.create(16,8,false,Image.FORMAT_RGBA8);image.fill(Color(.3,.6,.9,1.));image.save_png(path)
	return path

func helper_cases()->void:
	for dims:Vector2i in [Vector2i(1,1),Vector2i(7,11),Vector2i(16,8),Vector2i(1254,1254)]:
		for kind:String in ["DXT1","DXT5","ATI2"]:
			for dx10:bool in [false,true]:
				var path:=source_file("case_%d_%d_%s_%s"%[dims.x,dims.y,kind,dx10])
				var suffix:String={"DXT1":".dxt1.dds","DXT5":".dxt5.dds","ATI2":".bc5.dds"}[kind]
				var bytes:=dds(dims.x,dims.y,kind,dx10);put(path+suffix,bytes)
				var row:=Source.plan(path,false,kind=="ATI2",directory)
				check(not row.is_empty(),"admit "+path.get_file())
				if row.is_empty():continue
				var image:=Source.read(row)
				check(image!=null,"CPU read "+path.get_file())
				if image==null:continue
				check(image.get_width()==dims.x and image.get_height()==dims.y,"original dimensions preserved")
				check(image.get_mipmap_count()==row.mip_count-1,"complete mip count preserved")
				check(image.get_data()==bytes.slice(148 if dx10 else 128),"all mip blocks byte identical")
				check(image.get_meta("runtime_upload_has_alpha")==bool(kind=="DXT5"),"alpha metadata by admitted format")
				check(image.get_meta("runtime_normal_xy")==bool(kind=="ATI2"),"BC5 normal metadata only")
				check(image.get_meta("runtime_compressed_sidecar_path")==path+suffix,"sidecar upload ownership metadata")
				check(not image.has_meta("runtime_source_sha256"),"source identity remains caller policy")
	var path:=source_file("shared_roles")
	put(path+".dxt1.dds",dds(16,8,"DXT1"));put(path+".bc5.dds",dds(16,8,"ATI2"))
	var flipped:=dds(16,8,"ATI2");flipped[128]=233;put(path+".flip.bc5.dds",flipped)
	check(Source.plan(path,false,false,directory).sidecar==path+".dxt1.dds","color cannot select BC5 sibling")
	check(Source.plan(path,false,true,directory).sidecar==path+".bc5.dds","normal prefers BC5 sibling")
	var flip_row:=Source.plan(path,true,true,directory)
	check(flip_row.sidecar==path+".flip.bc5.dds" and Source.read(flip_row).get_data()[0]==233,"DirectX selects preconverted blocks without another green flip")
	check(Source.plan(path,true,false,directory).is_empty(),"reject flip without normal role")
	check(Source.plan(path,false,false,directory.path_join("unrelated")).is_empty(),"plan cannot read outside captured root")
	var row:=Source.plan(path,false,true,directory);row.root=directory.path_join("unrelated")
	check(Source.read(row)==null,"read cannot escape captured root")
	Probe.discard_map_textures=true
	check(Source.plan(path,false,true,directory).is_empty() and Source.read(flip_row)==null,"white mode does no DDS preparation")
	Probe.discard_map_textures=false

func malformed_cases()->void:
	var path:=source_file("malformed");var target:=path+".dxt1.dds"
	var valid:=dds(16,8,"DXT1")
	var cases:Array=[]
	var changed:=valid.duplicate();changed[0]=0;cases.append(["signature",changed])
	changed=valid.duplicate();changed.encode_u32(4,125);cases.append(["header size",changed])
	changed=valid.duplicate();changed.encode_u32(76,0);cases.append(["pixel header size",changed])
	changed=valid.duplicate();changed.encode_u32(16,0);cases.append(["zero width",changed])
	changed=valid.duplicate();changed.encode_u32(12,4097);cases.append(["oversize height",changed])
	changed=valid.duplicate();changed.encode_u32(16,0xffffffff);cases.append(["overflow width",changed])
	changed=valid.duplicate();changed.encode_u32(24,2);cases.append(["volume",changed])
	changed=valid.duplicate();changed.encode_u32(112,512);cases.append(["cube",changed])
	changed=valid.duplicate();changed.encode_u32(80,0);cases.append(["non-FourCC",changed])
	changed=valid.duplicate();changed.encode_u32(28,2);cases.append(["partial mips",changed])
	changed=valid.duplicate();changed.encode_u32(28,32);cases.append(["excess mips",changed])
	cases.append(["truncated",valid.slice(0,valid.size()-1)])
	changed=valid.duplicate();changed.append(0);cases.append(["trailing data",changed])
	changed=dds(16,8,"ATI2");cases.append(["BC5 cannot masquerade as color",changed])
	changed=dds(16,8,"DXT1",true);changed.encode_u32(140,2);cases.append(["DX10 array",changed])
	changed=dds(16,8,"DXT1",true);changed.encode_u32(132,4);cases.append(["DX10 volume",changed])
	changed=dds(16,8,"DXT1",true);changed.encode_u32(136,4);cases.append(["DX10 cube",changed])
	changed=dds(16,8,"DXT1",true);changed.encode_u32(128,84);cases.append(["signed BC5 unsupported",changed])
	for item:Array in cases:
		put(target,item[1]);check(Source.plan(path,false,false,directory).is_empty(),"reject "+item[0])
	check(Source._header(valid,Source.MAX_SOURCE_BYTES+1,false).is_empty(),"length bound before allocation")
	for item:Array in cases:
		put(target,valid);var row:=Source.plan(path,false,false,directory)
		put(target,item[1]);check(Source.read(row)==null,"recheck changed "+item[0]+" before Image allocation")
	# Same compressed allocation but different admitted width must also be rejected.
	put(target,valid);var row:=Source.plan(path,false,false,directory)
	changed=valid.duplicate();changed.encode_u32(16,15);put(target,changed)
	check(Source.read(row)==null,"same-size changed dimensions cannot bypass admission")

func editor_cases()->void:
	var path:=source_file("editor_shared")
	var color:=dds(16,8,"DXT1");var normal:=dds(16,8,"ATI2")
	put(path+".dxt1.dds",color);put(path+".bc5.dds",normal)
	var record:={"terrain_material":{"texture_path":path,"normal_path":path}}
	Paint.refresh_sources();Paint._sidecar_cache={"sentinel":"main-owned"}
	var requested:=Editor.requests(record,{})
	check(requested.size()==2,"editor schedules color and normal DDS instead of skipping them")
	var worker:=Thread.new();worker.start(Editor.decode.bind(requested,directory))
	while worker.is_alive():await process_frame
	var prepared:Dictionary=worker.wait_to_finish()
	check(Paint._sidecar_cache=={"sentinel":"main-owned"},"editor scheduling and worker never mutate sidecar cache")
	check(prepared.failed.is_empty() and prepared.images.size()==2,"editor worker prepares both compressed roles")
	for key:String in [path,path+"|normal"]:
		if not prepared.images.has(key):check(false,"prepared image exists "+key);continue
		var image:Image=prepared.images[key]
		check(image.is_compressed() and image.get_data()==(normal if key.ends_with("|normal") else color).slice(128),"editor preserves compressed role bytes")
		check(image.get_meta("runtime_source_sha256","")==path.sha256_text(),"editor uses trusted source identity")
	Editor.TextureCache.Policy.verify_packages=true
	prepared=Editor.decode({path:[path,false,false]},directory)
	check(prepared.images.has(path) and prepared.images[path].get_meta("runtime_source_sha256","")==FileAccess.get_sha256(path),"strict editor retains authored source identity")
	Editor.TextureCache.Policy.verify_packages=false
	# Broken/unsupported derived files retain the original PNG fallback.
	put(path+".dxt1.dds",PackedByteArray([1,2,3]))
	prepared=Editor.decode({path:[path,false,false]},directory)
	check(prepared.images.has(path) and not prepared.images[path].is_compressed(),"broken DDS falls back to existing PNG decoding")
	DirAccess.remove_absolute(path)
	prepared=Editor.decode({path+"|normal":[path,false,true]},directory)
	check(prepared.images.is_empty() and prepared.failed==[path+"|normal"],"missing authored source keeps prior failure behavior despite DDS")
	Paint.refresh_sources()

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):directory=arg.trim_prefix("--output=").replace("\\","/")
	if directory.is_empty() or not directory.is_absolute_path():push_error("--output=<external temporary directory> required");quit(2);return
	DirAccess.make_dir_recursive_absolute(directory)
	helper_cases();malformed_cases();await editor_cases()
	print("COMPRESSED_TEXTURE_SOURCE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
