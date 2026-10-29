extends RefCounted
## Main-thread commit of completed native owners. The real scene/job owns the
## resource; this shared directory keeps only a weak identity, never pixels.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
static func ticket(key:String,row:Dictionary)->Dictionary:
	assert(Thread.is_main_thread())
	# Exact requested key only; no fallback scan through unrelated materials.
	if not row.get("model_product",false) or row.get("extension")!="stex":return {}
	if not preload("res://scripts/world3d/streamed_texture_source.gd").enabled() or not ProjectSettings.get_setting("rendering/textures/streaming/memory_budget_enabled",false):return {}
	var texture:Texture2D=Paint._textures.get(key)
	if texture==null and Paint._texture_refs.has(key):texture=Paint._texture_refs[key].get_ref()
	if texture==null or texture.get_script()!=null or not texture.is_class("StreamedTexture2D"):return {}
	if texture.get_meta("runtime_texture_representation","")!=row.get("representation") or not texture.get_rid().is_valid() or not texture.has_method("is_streaming_active") or not texture.call("is_streaming_active"):return {}
	if str(texture.call("get_load_path"))!=row.get("path"):return {}
	var digest:String=texture.get_meta("runtime_source_sha256","");var prepared:Resource=Paint._prepared_resource(key)
	if digest.length()!=64 or not digest.is_valid_hex_number(false) or (prepared!=null and not Paint._same_prepared_texture(texture,prepared)):return {}
	return {"texture":texture,"source_sha":digest}

static func publish(owners:Dictionary,native_keys:Variant=null,resident:Dictionary={})->int:
	assert(Thread.is_main_thread())
	var keys:Dictionary=owners if native_keys==null else native_keys
	var remembered:=0
	for key:String in keys:
		var texture:Texture2D=owners.get(key)
		if texture==null and resident.has(key):texture=resident[key].get("texture")
		if texture==null or not texture.is_class("StreamedTexture2D"):continue
		if not str(texture.get_meta("runtime_texture_representation","")).begins_with("stex:"):continue
		if str(texture.get_meta("runtime_source_sha256","")).length()!=64:continue
		if Paint._texture_refs.has(key) and Paint._texture_refs[key].get_ref()==texture:continue
		# Do not use the diagnostic strong-cache branch of remember_texture_owner.
		Paint._remember_weak(Paint._texture_refs,key,texture);remembered+=1
	return remembered
