extends RefCounted
## Disposable native runtime metadata, never the editable source of truth.
## Deduplicate repeated face-paint arrays before binary serialization. Every read
## still runs MapLoader's full schema, ownership and external dependency checks.
const VERSION:=1
const DIRECTORY:="user://world3d_metadata"
const MAGIC:="RMMOMETA1"

static func checksum(bytes:PackedByteArray)->PackedByteArray:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	return hash.finish()

static func cache_path(path:String)->String:
	return DIRECTORY.path_join(path.replace("\\","/").simplify_path().sha256_text()+".bin")

static func read(path:String, digest:String,context:Dictionary={})->Dictionary:
	var file:=FileAccess.open(cache_path(path),FileAccess.READ)
	if file==null:return {}
	if file.get_length()<49 or file.get_buffer(9).get_string_from_ascii()!=MAGIC:return {}
	var length:=file.get_64()
	if length<=0 or length>268435456 or file.get_length()!=49+length:return {}
	var expected:=file.get_buffer(32)
	var bytes:=file.get_buffer(length)
	if checksum(bytes)!=expected:return {}
	var value:Variant=bytes_to_var(bytes) # Objects/scripts are never deserialized.
	if not value is Dictionary or value.get("version")!=VERSION or value.get("sha256")!=digest:return {}
	if not value.get("extras") is Dictionary or not value.get("paints") is Array or not value.get("paint_ids") is Array:return {}
	var extra:Dictionary=value.extras
	if not extra.get("rmmo_records") is Array or extra.rmmo_records.size()!=value.paint_ids.size():return {}
	for i in extra.rmmo_records.size():
		var id:Variant=value.paint_ids[i]
		if not id is int or id < -1 or id>=value.paints.size() or not extra.rmmo_records[i] is Dictionary:return {}
		if id==-1 and extra.rmmo_records[i].has("surface_paint"):return {}
		if id>=0:extra.rmmo_records[i].surface_paint=value.paints[id]
	context["textures"]=value.get("textures",[])
	# These ids are trusted only for this restored, immutable record snapshot.
	context["paint_ids"]=value.paint_ids
	return extra

static func write(path:String,digest:String,extras:Dictionary,textures:Array=[])->void:
	var compact:=extras.duplicate()
	var records:Array=[];var paints:Array=[];var ids:Array=[];var known:Dictionary={}
	for record:Dictionary in extras.rmmo_records:
		var copy:=record.duplicate()
		var id:=-1
		if record.has("surface_paint"):
			var paint:Variant=record.surface_paint
			if not known.has(paint):known[paint]=paints.size();paints.append(paint)
			id=known[paint];copy.erase("surface_paint")
		records.append(copy);ids.append(id)
	compact.rmmo_records=records
	if DirAccess.make_dir_recursive_absolute(DIRECTORY)!=OK:return
	var target:=cache_path(path)
	var temporary:=target+".%d.tmp"%Time.get_ticks_usec()
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return
	var bytes:=var_to_bytes({"version":VERSION,"sha256":digest,"extras":compact,"paints":paints,"paint_ids":ids,"textures":textures})
	file.store_buffer(MAGIC.to_ascii_buffer());file.store_64(bytes.size());file.store_buffer(checksum(bytes));file.store_buffer(bytes)
	file.close()
	if DirAccess.rename_absolute(temporary,target)!=OK:DirAccess.remove_absolute(temporary)
