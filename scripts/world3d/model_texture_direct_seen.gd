extends RefCounted
## Candidate for detached, trusted direct-safe native scene only.
## The immutable authored identity must remain stable throughout this call.
const Cache=preload("res://scripts/world3d/model_texture_cache.gd")
static func apply(root:Node)->void:
	if not Cache.enabled or OS.get_thread_caller_id()!=OS.get_main_thread_id():return
	var seen:Dictionary={};var retired:Array[Texture2D]=[]
	for material:StandardMaterial3D in Cache._materials(root):
		for info:Dictionary in material.get_property_list():
			if not (int(info.usage)&PROPERTY_USAGE_STORAGE):continue
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
			if shared!=value:retired.append(value);material.set(info.name,shared)
	if not retired.is_empty():preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	seen.clear();retired.clear()
