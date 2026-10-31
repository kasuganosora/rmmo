extends RefCounted
## Runtime sharing without repeatedly exporting every scalar material property.
## Kept outside the import generator: pixel stamping/build semantics are unchanged.
const Cache=preload("res://scripts/world3d/model_texture_cache.gd")
static var _native_properties:Dictionary={}

static func _properties(material:StandardMaterial3D)->Array[StringName]:
	var names:Array[StringName]=[]
	# Scripted/extension properties can have custom getters and validation. Keep
	# their original storage-property snapshot, including non-object getters.
	if material.get_script()!=null or material.get_class()!=&"StandardMaterial3D":
		for info:Dictionary in material.get_property_list():
			if int(info.usage)&PROPERTY_USAGE_STORAGE:names.append(info.name)
		return names
	# Godot 4.8 BaseMaterial3D::_validate_property changes texture storage usage
	# with shading_mode and the skin flag. Other toggles only hide texture fields
	# in the inspector, or change scalar properties. Metadata is instance-local.
	var policy:int=int(material.shading_mode)*2+int(material.get_flag(BaseMaterial3D.FLAG_SUBSURFACE_MODE_SKIN))
	if not _native_properties.has(policy):
		var native_names:Array[StringName]=[]
		for info:Dictionary in material.get_property_list():
			if not (int(info.usage)&PROPERTY_USAGE_STORAGE):continue
			if int(info.type)!=TYPE_OBJECT and int(info.type)!=TYPE_NIL:continue
			if not str(info.name).begins_with("metadata/"):native_names.append(info.name)
		_native_properties[policy]=native_names
	names.assign(_native_properties[policy])
	for key:StringName in material.get_meta_list():names.append(StringName("metadata/"+str(key)))
	return names

static func apply(root:Node)->void:
	if root==null or not Cache.enabled or OS.get_thread_caller_id()!=OS.get_main_thread_id():return
	if root.has_meta(&"rmmo_model_texture_table_v1"):return
	var seen:Dictionary={}
	var changed:=false
	for material:StandardMaterial3D in Cache._materials(root):
		for name:StringName in _properties(material):
			var value:Variant=material.get(name)
			if not value is Texture2D or not Cache._plain_texture(value):continue
			var key:Variant=value.get_meta(Cache.PIXEL_KEY,"")
			if not Cache._valid_key(key):continue
			var id:int=value.get_instance_id()
			if not seen.has(id):seen[id]={"original":value,"shared":Cache._remember(key,value)}
			var shared:Texture2D=seen[id].shared
			if shared!=value:
				changed=true
				material.set(name,shared)
	# seen retains each original across setters and renderer synchronization.
	if changed:preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	seen.clear()
