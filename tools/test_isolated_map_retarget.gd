extends SceneTree
## A tiny two-root fixture for testing material relocation before a real map
## experiment. All generated files live under a new external review directory.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Format=preload("res://scripts/world3d/world_location.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Compressed=preload("res://scripts/world3d/compressed_texture_source.gd")
const Fixture=preload("res://tools/structure_dependency_fixture.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var checks:=0
var failures:Array[String]=[]
var folder:=""

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func put(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:failures.append("cannot write "+path);return
	file.store_buffer(bytes);file.close()

func bc5(width:int,height:int)->PackedByteArray:
	var data:=PackedByteArray();data.resize(128)
	for i:int in 4:data[i]="DDS ".to_ascii_buffer()[i]
	data.encode_u32(4,124);data.encode_u32(8,0x000A1007)
	data.encode_u32(12,height);data.encode_u32(16,width)
	data.encode_u32(76,32);data.encode_u32(80,4);data.encode_u32(108,0x401008)
	for i:int in 4:data[84+i]="ATI2".to_ascii_buffer()[i]
	var levels:=1;var size:=0;var w:=width;var h:=height
	while true:
		size+=maxi(1,(w+3)/4)*maxi(1,(h+3)/4)*16
		if w==1 and h==1:break
		w=maxi(1,w/2);h=maxi(1,h/2);levels+=1
	data.encode_u32(20,maxi(1,(width+3)/4)*maxi(1,(height+3)/4)*16);data.encode_u32(28,levels)
	var start:=data.size();data.resize(start+size)
	for i:int in size:data[start+i]=(i*29+17)%256
	return data

func make_record(path:String)->Dictionary:
	var record:=Fixture.wall("fixture_wall",0)
	var material:Dictionary={"name":"shared","color":[1.,1.,1.,1.],"roughness":.7,"texture_path":path,"normal_path":path,"normal_format":"directx"}
	var data:Dictionary=Prefab.decode(record.house_prefab).duplicate(true)
	data.materials=[{"paint":material.duplicate(true),"cull":0}]
	var bytes:=var_to_bytes(data)
	record.house_prefab={"version":1,"sha256":Store._sha(bytes),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	record.prefab_materials=[material.duplicate(true)]
	# Unrelated strings are deliberately equal: broad recursion must not change them.
	record.provenance_note=path
	return record

func write_map(path:String,root_:String,records:Array)->Dictionary:
	var stored:=Store.write_records(records,path,root_)
	if not stored.ok:return stored
	var extra:Dictionary={"rmmo_format":Format.FORMAT,"rmmo_version":Format.FORMAT_VERSION,"rmmo_storage":Format.STORAGE,"rmmo_unit":"m","rmmo_records":stored.records,"rmmo_resource_dependencies":stored.dependencies,"spawn":[0,1,0]}
	var gltf:Dictionary={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":extra}]}
	put(path,JSON.stringify(gltf).to_utf8_buffer())
	return stored

func read_map(path:String,root_:String)->Dictionary:
	var gltf:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not gltf is Dictionary:return {"ok":false}
	var extra:Dictionary=gltf.nodes[0].extras
	return Store.read_records(extra.rmmo_records,path,root_,extra.rmmo_resource_dependencies,1,false)

func retarget(records:Array,mapping:Dictionary)->Dictionary:
	var edits:=0;var prefabs:=0
	for record:Dictionary in records:
		var changed:=false
		for material:Dictionary in Paint.definitions(record):
			for field:String in Paint.MAP_FIELDS:
				var before:String=str(material.get(field,""))
				if mapping.has(before):material[field]=mapping[before];edits+=1;changed=true
		if changed and record.has("house_prefab"):
			Prefab.retarget_materials(record);prefabs+=1
	return {"edits":edits,"prefabs":prefabs}

func run()->void:
	Policy.verify_packages=true
	var base:="D:/code/rmmo_runtime/review_artifacts/isolated_map_fixture"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):base=arg.trim_prefix("--output=")
	if not Paths.allowed(base,"D:/code/rmmo_runtime/review_artifacts") or DirAccess.dir_exists_absolute(base):
		printerr("New external --output directory required");quit(2);return
	folder=base;var original_root:=folder.path_join("original");var target_root:=folder.path_join("target")
	DirAccess.make_dir_recursive_absolute(original_root.path_join("assets"));DirAccess.make_dir_recursive_absolute(target_root.path_join("assets"))
	var src:=original_root.path_join("assets/shared.png");var dst:=target_root.path_join("assets/shared.png")
	var image:=Image.create(7,11,false,Image.FORMAT_RGBA8);image.fill(Color(.25,.5,.75));check(image.save_png(src)==OK,"temporary PNG created")
	check(DirAccess.copy_absolute(src,dst)==OK and FileAccess.get_sha256(src)==FileAccess.get_sha256(dst),"target PNG is byte-identical temporary copy")
	var record:=make_record(src);var second:Dictionary=record.duplicate(true);second.uuid="fixture_wall_2";second.position=[8.,2.,0.]
	check(Prefab.valid(record),"source frozen prefab is internally valid")
	var source_map:=original_root.path_join("map.gltf");var target_map:=target_root.path_join("map.gltf")
	var written:=write_map(source_map,original_root,[record,second])
	check(written.get("ok",false) and written.dependencies.size()==1,"source map shares immutable rmres across two instances")
	if not written.get("ok",false):printerr(written);quit(1);return
	var source_sha:=FileAccess.get_sha256(source_map);var original:=read_map(source_map,original_root)
	check(original.get("ok",false) and original.records.size()==2,"source compact map reloads with exact dependency closure")
	if not original.get("ok",false):printerr(original);quit(1);return
	var remapped:Array=original.records.duplicate(true)
	var old_prefab_sha:String=remapped[0].house_prefab.sha256
	# Negative contract: visible prefab_materials alone cannot change its packet.
	var invalid:Dictionary=remapped[0].duplicate(true);invalid.prefab_materials[0].normal_path=dst
	check(not Prefab.valid(invalid),"changing only visible material leaves packet invalid")
	var stats:=retarget(remapped,{src:dst})
	check(stats.edits==4 and stats.prefabs==2,"only declared material slots are retargeted for both records")
	check(remapped[0].provenance_note==src and remapped[0].house_prefab.sha256!=old_prefab_sha,"non-material value remains untouched while packet identity changes")
	check(Prefab.valid(remapped[0]) and Prefab.valid(remapped[1]) and remapped[0].house_prefab.sha256==remapped[1].house_prefab.sha256,"retargeted frozen packets remain valid and shared")
	var target_written:=write_map(target_map,target_root,remapped)
	check(target_written.get("ok",false) and target_written.dependencies.size()==1,"target map saves same deduplicated definition")
	if not target_written.get("ok",false):printerr(target_written);quit(1);return
	var restored:=read_map(target_map,target_root)
	check(restored.get("ok",false) and restored.records.size()==2,"target map reopens with regenerated references")
	if not restored.get("ok",false):printerr(restored);quit(1);return
	check(Prefab.valid(restored.records[0]) and restored.records[0].prefab_materials[0].normal_path==dst and restored.records[1].prefab_materials[0].texture_path==dst,"reopened prefab identity and relocated slots agree")
	check(restored.records[0].uuid==original.records[0].uuid and restored.records[1].uuid==original.records[1].uuid and restored.records[0].position==original.records[0].position and restored.records[1].position==original.records[1].position and restored.records[0].collision==original.records[0].collision,"identity, transforms and collision semantics survive")
	check(FileAccess.get_sha256(source_map)==source_sha and read_map(source_map,original_root).records[0].prefab_materials[0].normal_path==src,"source map and source material remain untouched")
	check(Compressed.plan(dst,true,true,target_root).is_empty(),"baseline target has no compressed sidecar")
	var sidecar:=dst+".flip.bc5.dds";var compressed:=bc5(7,11);put(sidecar,compressed)
	var normal:=Compressed.plan(dst,true,true,target_root)
	check(not normal.is_empty() and normal.sidecar==sidecar and normal.format==Image.FORMAT_RGTC_RG,"candidate selects DirectX normal BC5 within target root")
	if not normal.is_empty():
		var decoded:=Compressed.read(normal)
		check(decoded!=null and decoded.get_data()==compressed.slice(128) and decoded.get_meta("runtime_normal_xy",false),"CPU reader preserves full BC5 mip payload and normal semantics")
	check(Compressed.plan(dst,false,false,target_root).is_empty(),"normal candidate cannot masquerade as a color sidecar")
	check(Compressed.plan(dst,true,true,original_root).is_empty(),"target cannot be read through the source resource root")
	check(FileAccess.get_sha256(source_map)==source_sha and not FileAccess.file_exists(src+".flip.bc5.dds"),"candidate touches only target and never source")
	print("ISOLATED_MAP_RETARGET checks=",checks," failures=",failures.size()," output=",folder)
	for failure:String in failures:printerr("FAIL ",failure)
	quit(0 if failures.is_empty() else 1)
