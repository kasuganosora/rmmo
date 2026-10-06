extends RefCounted
## Disposable native runtime metadata, never the editable source of truth.
## Deduplicate repeated face-paint arrays and prefab payloads before serialization. Every read
## still runs MapLoader's full schema, ownership and external dependency checks.
const VERSION:=2
const DIRECTORY:="user://world3d_metadata"
const MAGIC:="RMMOMETA1"

static func checksum(bytes:PackedByteArray)->PackedByteArray:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	return hash.finish()

static func cache_path(path:String)->String:
	return DIRECTORY.path_join(path.replace("\\","/").simplify_path().sha256_text()+".bin")

static func read(path:String, digest:String,context:Dictionary={})->Dictionary:
	var candidate:=read_candidate(path)
	if candidate.get("source_digest")!=digest:return {}
	context.merge(candidate.context,true)
	return candidate.extras

## Verifies the envelope and table structure only. Callers MUST compare the
## returned source_digest with the current source file before using extras.
static func read_candidate(path:String)->Dictionary:
	var file:=FileAccess.open(cache_path(path),FileAccess.READ)
	if file==null:return {}
	if file.get_length()<49 or file.get_buffer(9).get_string_from_ascii()!=MAGIC:return {}
	var length:=file.get_64()
	if length<=0 or length>268435456 or file.get_length()!=49+length:return {}
	var expected:=file.get_buffer(32)
	var bytes:=file.get_buffer(length)
	if checksum(bytes)!=expected:return {}
	var value:Variant=bytes_to_var(bytes) # Objects/scripts are never deserialized.
	if not value is Dictionary or value.get("version") not in [1,VERSION] or not value.get("sha256") is String:return {}
	if not value.get("extras") is Dictionary or not value.get("paints") is Array or not value.get("paint_ids") is Array:return {}
	var extra:Dictionary=value.extras
	if not extra.get("rmmo_records") is Array or extra.rmmo_records.size()!=value.paint_ids.size():return {}
	var pooled:bool=value.version==VERSION
	if pooled and (not value.get("prefabs") is Array or not value.get("prefab_ids") is Array or value.prefab_ids.size()!=extra.rmmo_records.size()):return {}
	for i in extra.rmmo_records.size():
		var id:Variant=value.paint_ids[i]
		if not id is int or id < -1 or id>=value.paints.size() or not extra.rmmo_records[i] is Dictionary:return {}
		if id==-1 and extra.rmmo_records[i].has("surface_paint"):return {}
		if id>=0:extra.rmmo_records[i].surface_paint=value.paints[id]
		if pooled:
			var prefab_id:Variant=value.prefab_ids[i]
			if not prefab_id is int or prefab_id < -1 or prefab_id>=value.prefabs.size() or extra.rmmo_records[i].has("house_prefab"):return {}
			if prefab_id>=0:
				if not value.prefabs[prefab_id] is Dictionary:return {}
				extra.rmmo_records[i].house_prefab=value.prefabs[prefab_id]
	var context:={"upgrade":not pooled}
	context["textures"]=value.get("textures",[])
	# These ids are trusted only for this restored, immutable record snapshot.
	context["paint_ids"]=value.paint_ids
	return {"source_digest":value.sha256,"extras":extra,"context":context}

static func write(path:String,digest:String,extras:Dictionary,textures:Array=[])->void:
	var compact:=extras.duplicate()
	var records:Array=[];var paints:Array=[];var ids:Array=[];var known:Dictionary={}
	var prefabs:Array=[];var prefab_ids:Array=[];var known_prefabs:Dictionary={}
	for record:Dictionary in extras.rmmo_records:
		var copy:=record.duplicate()
		var id:=-1
		if record.has("surface_paint"):
			var paint:Variant=record.surface_paint
			if not known.has(paint):known[paint]=paints.size();paints.append(paint)
			id=known[paint];copy.erase("surface_paint")
		var prefab_id:=-1
		if record.has("house_prefab"):
			# Compare the entire payload, never trust a supplied digest alone.
			var prefab:Dictionary=record.house_prefab
			if not known_prefabs.has(prefab):known_prefabs[prefab]=prefabs.size();prefabs.append(prefab)
			prefab_id=known_prefabs[prefab];copy.erase("house_prefab")
		records.append(copy);ids.append(id);prefab_ids.append(prefab_id)
	compact.rmmo_records=records
	if DirAccess.make_dir_recursive_absolute(DIRECTORY)!=OK:return
	var target:=cache_path(path)
	var temporary:=target+".%d.tmp"%Time.get_ticks_usec()
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return
	var bytes:=var_to_bytes({"version":VERSION,"sha256":digest,"extras":compact,"paints":paints,"paint_ids":ids,"textures":textures,"prefabs":prefabs,"prefab_ids":prefab_ids})
	file.store_buffer(MAGIC.to_ascii_buffer());file.store_64(bytes.size());file.store_buffer(checksum(bytes));file.store_buffer(bytes)
	file.close()
	if DirAccess.rename_absolute(temporary,target)!=OK:DirAccess.remove_absolute(temporary)
