extends SceneTree
## Read-only dependency inventory, no GPU/GLB/native rebuild or cache writes.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var errors:Array[String]=[]

func _initialize()->void:run.call_deferred()

func run()->void:
	var map_path:="";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not Paths.allowed(map_path) or not Paths.allowed(output) or FileAccess.file_exists(output):
		push_error("Allowed external --map and new --output paths required");quit(1);return
	var before:=FileAccess.get_sha256(map_path)
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var records:Array=document.nodes[0].extras.rmmo_records
	var definitions:Dictionary={};var sources:Dictionary={}
	for record:Dictionary in records:
		var ref:Dictionary=record.rmmo_ref
		if definitions.has(ref.uri):continue
		var location:String=map_path.get_base_dir().path_join(ref.uri).simplify_path()
		if not location.begins_with(map_path+".resources/"):
			errors.append("Unexpected definition path: "+location);continue
		var decoded:=Store._read(location,ref.sha256,int(ref.length),true,true)
		if not decoded.ok:errors.append("Cannot decode "+location);continue
		definitions[ref.uri]=true
		for material:Dictionary in Paint.definitions(decoded.definition):
			for field:String in Paint.MAP_FIELDS:
				var path:String=material.get(field,"")
				if path.is_empty():continue
				if not Paths.allowed(path):errors.append("Unresolved material path: "+path);continue
				var flip:bool=field=="normal_path" and material.get("normal_format","opengl")=="directx"
				var key:=Paint.texture_key(path,flip,field=="normal_path")
				if not sources.has(key):sources[key]={"source":path,"normal_role":field=="normal_path","flip_normal_green":flip,"fields":[],"definition_references":0}
				var source:Dictionary=sources[key];source.definition_references+=1
				if not field in source.fields:source.fields.append(field)
	var inventory:Array=[]
	for key:String in sources:
		var source:Dictionary=sources[key]
		var suffixes:Array=([".flip.dxt5.dds",".flip.dxt1.dds"] if source.flip_normal_green else [".dxt5.dds",".dxt1.dds"])
		if source.normal_role:suffixes.push_front(".flip.bc5.dds" if source.flip_normal_green else ".bc5.dds")
		var selected:=""
		for suffix:String in suffixes:
			if FileAccess.file_exists(source.source+suffix):selected=source.source+suffix;break
		source.selected_sidecar=selected
		if not selected.is_empty():
			var file:=FileAccess.open(selected,FileAccess.READ)
			var header:=file.get_buffer(128)
			if header.size()!=128 or header.slice(0,4).get_string_from_ascii()!="DDS ":errors.append("Invalid DDS header: "+selected);continue
			source.dds_bytes=file.get_length();source.width=header.decode_u32(16);source.height=header.decode_u32(12)
			source.declared_mip_levels=header.decode_u32(28);source.fourcc=header.slice(84,88).get_string_from_ascii()
			source.missing_mip_chain=int(source.declared_mip_levels)<=1 and maxi(source.width,source.height)>1
			source.legacy_flip_needs_pixel_comparison=source.flip_normal_green and source.missing_mip_chain
		inventory.append(source)
	var report:={"map":map_path,"map_sha256":before,"map_unchanged":FileAccess.get_sha256(map_path)==before,
		"records":records.size(),"unique_definitions":definitions.size(),"texture_variants":inventory,
		"scope":"Declared map/prefab paint dependency closure; not a claim that every source is submitted by one traversal. Imported-model native materials are not traversed.",
		"sidecar_files_written":0,"source_files_written":0,"errors":errors}
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("DDS_MAP_AUDIT ",JSON.stringify({"definitions":definitions.size(),"texture_variants":inventory.size(),"errors":errors}))
	quit(0 if errors.is_empty() and report.map_unchanged else 1)
