extends SceneTree
## Compare every saved Resource/node property; only the new geometry-key field
## and serializer-local resource IDs may differ. No authored file is changed.
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var identities:=0
var meshes:=0
var errors:Array=[]
func _initialize()->void:run.call_deferred()
func canonical(value:Variant,seen:Dictionary,verify:bool)->Variant:
	if value is Resource:
		var id:int=value.get_instance_id()
		if seen.has(id):return ["reference",seen[id]]
		var serial:int=seen.size();seen[id]=serial
		var properties:Dictionary={}
		if value is ArrayMesh:
			meshes+=1
			if verify:
				var data:Dictionary=value.get_meta(Native.META,{})
				if data.get("geometry_key","")!=Cpu.geometry_signature(data.get("surfaces",[]),data.get("lods",[])):errors.append("geometry identity mismatch")
				else:identities+=1
		for property:Dictionary in value.get_property_list():
			var name_:String=property.name
			if (int(property.usage)&PROPERTY_USAGE_STORAGE)==0 or name_ in ["resource_path","resource_scene_unique_id"]:continue
			var item:Variant=value.get(name_)
			if value is PackedScene and name_=="_bundled":
				# Godot pack() generates random unique_scene_id values for imported
				# nodes. Authored UUIDs, names, ownership and paths remain compared.
				# These static products must have no UID-relative reference paths.
				if not item.get("id_paths",[]).is_empty():errors.append("UID-relative paths require an explicit identity mapping")
				item=item.duplicate();item.erase("node_ids")
			if name_=="metadata/"+str(Native.META):
				item=item.duplicate();item.erase("geometry_key")
			properties[name_]=canonical(item,seen,verify)
		return ["resource",serial,value.get_class(),properties]
	if value is Array:
		var result:Array=[]
		for item:Variant in value:result.append(canonical(item,seen,verify))
		return result
	if value is Dictionary:
		var result:Dictionary={}
		for key:Variant in value:result[key]=canonical(value[key],seen,verify)
		return result
	return value
func digest(value:Variant)->String:
	var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(var_to_bytes(value))
	return hashing.finish().hex_encode()
func first_difference(a:Variant,b:Variant,path:String="root")->String:
	if typeof(a)!=typeof(b):return path+": types differ"
	if a is Array:
		if a.size()!=b.size():return path+": lengths "+str(a.size())+" / "+str(b.size())
		for i:int in a.size():
			var difference:=first_difference(a[i],b[i],path+"["+str(i)+"]")
			if not difference.is_empty():return difference
	elif a is Dictionary:
		if a.size()!=b.size():return path+": keys "+str(a.keys())+" / "+str(b.keys())
		for key:Variant in a:
			if not b.has(key):return path+": missing key "+str(key)
			var difference:=first_difference(a[key],b[key],path+"."+str(key))
			if not difference.is_empty():return difference
	elif a!=b:return path+": "+str(a).left(120)+" / "+str(b).left(120)
	return ""
func audit(old:Dictionary)->Dictionary:
	var current:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(old.index))
	var path:=Native.directory("D:/code/rmmo_runtime").path_join(current.payload_sha+".scn")
	var row:={"source":old.source,"source_sha":current.source_sha,"old_product":old.product,"old_sha":old.manifest.payload_sha,"new_product":path,"new_sha":current.payload_sha,"old_bytes":old.manifest.bytes,"new_bytes":current.bytes}
	errors=[];meshes=0;identities=0
	if FileAccess.get_sha256(old.source)!=current.source_sha or current.source_sha!=old.manifest.source_sha:errors.append("source changed")
	if FileAccess.get_sha256(old.product)!=row.old_sha or FileAccess.get_sha256(path)!=row.new_sha:errors.append("product identity changed")
	if not ResourceLoader.get_dependencies(path).is_empty():errors.append("external dependency added")
	var before:Resource=ResourceLoader.load(old.product,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var after:Resource=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not before is PackedScene or not after is PackedScene:errors.append("native reopen failed")
	else:
		var old_properties:Variant=canonical(before,{},false)
		row.old_properties_sha=digest(old_properties);row.old_meshes=meshes;meshes=0
		var new_properties:Variant=canonical(after,{},true)
		row.new_properties_sha=digest(new_properties);row.new_meshes=meshes;row.precomputed_identities=identities
		if meshes<=0 or identities!=meshes:errors.append("incomplete native geometry identity coverage")
		if row.old_properties_sha!=row.new_properties_sha:errors.append("stored node/render/geometry/LOD/collision properties changed: "+first_difference(old_properties,new_properties))
	row.errors=errors;row.metadata_only=errors.is_empty()
	return row
func run()->void:
	var previous:="";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--previous="):previous=arg.trim_prefix("--previous=")
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if previous.is_empty() or output.is_empty():quit(2);return
	var rows:Array=[];var failures:=0
	for old:Dictionary in JSON.parse_string(FileAccess.get_file_as_string(previous)).models:
		var row:=audit(old);rows.append(row);failures+=int(not row.metadata_only)
		print("NATIVE_IDENTITY_AUDIT ",JSON.stringify(row));await process_frame
		if "--first" in OS.get_cmdline_user_args():break
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"models":rows,"failures":failures,"scope":"Saved metadata-only identity addition; exact native node/Resource/geometry/LOD/collision fields unchanged, excluding serializer-local resource IDs. White-stage pipeline audit, no new texture or art direction acceptance."},"\t"))
	quit(1 if failures else 0)
