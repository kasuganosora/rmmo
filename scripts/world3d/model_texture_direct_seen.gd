extends RefCounted
## Candidate for detached, trusted direct-safe native scene only.
## The immutable authored identity must remain stable throughout this call.
const Cache=preload("res://scripts/world3d/model_texture_cache.gd")
static func apply(root:Node)->void:
	if not Cache.enabled or OS.get_thread_caller_id()!=OS.get_main_thread_id():return
	if root==null or root.has_meta(&"rmmo_model_texture_table_v1"):return
	var seen:Dictionary={};var changed:=false
	for material:StandardMaterial3D in Cache._materials(root):
		for info:Dictionary in material.get_property_list():
			if not (int(info.usage)&PROPERTY_USAGE_STORAGE):continue
			# TYPE_NIL can denote a Variant property, so keep it on the read path.
			if int(info.type)!=TYPE_OBJECT and int(info.type)!=TYPE_NIL:continue
			var value:Variant=material.get(info.name)
			if not value is Texture2D:continue
			var id:int=value.get_instance_id()
			if not seen.has(id):
				if not Cache._plain_texture(value):continue
				var key:Variant=value.get_meta(Cache.PIXEL_KEY,"")
				if not Cache._valid_key(key):continue
				var shared:=Cache._remember(key,value)
				seen[id]={"original":value,"shared":shared}
			var shared:Texture2D=seen[id].shared
			if shared!=value:changed=true;material.set(info.name,shared)
	if changed:preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	seen.clear()
