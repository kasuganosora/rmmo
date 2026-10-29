extends RefCounted
## Main-thread commit of completed native owners. The real scene/job owns the
## resource; this shared directory keeps only a weak identity, never pixels.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
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
