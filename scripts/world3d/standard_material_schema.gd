extends RefCounted
## Reuse native storage-property NAMES, never material values or resource owners.
## Godot 4.7.2 BaseMaterial3D::_validate_property controls storage with these
## modes. Other engine versions and scripted materials retain native enumeration.
static var enabled:=true
static var supported:=int(Engine.get_version_info().get("hex",0))==0x040702
const LIMIT:=64
static var _schemas:Dictionary={}
static var _mutex:=Mutex.new()
static var enumerations:=0
static var hits:=0

static func snapshot()->Dictionary:
	_mutex.lock()
	var result:={"enabled":enabled,"supported":supported,"entries":_schemas.size(),"enumerations":enumerations,"hits":hits}
	_mutex.unlock()
	return result

static func _names(material:StandardMaterial3D,metadata:bool)->Array:
	var result:Array=[]
	for property:Dictionary in material.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and (metadata or not str(property.name).begins_with("metadata/")):
			result.append(property.name)
	return result

static func storage_names(material:StandardMaterial3D,metadata:bool=false)->Array:
	if not enabled or not supported or material.get_script()!=null or material.get_class()!=&"StandardMaterial3D":
		return _names(material,metadata)
	# Inspector-only usage changes retain STORAGE. These modes can remove it.
	var key:int=material.transparency | (material.alpha_antialiasing_mode<<3) | (material.billboard_mode<<5) | (int(material.heightmap_deep_parallax)<<7) | (int(material.subsurf_scatter_skin_mode)<<8) | (material.shading_mode<<9) | (int(ProjectSettings.get_setting("rendering/lights_and_shadows/use_physical_light_units",false))<<11)
	_mutex.lock()
	var names:Array=_schemas.get(key,[])
	if names.is_empty():
		names=_names(material,false);enumerations+=1
		names.make_read_only()
		if _schemas.size()<LIMIT:_schemas[key]=names
	else:hits+=1
	_mutex.unlock()
	if not metadata:return names
	# Object appends metadata after native/script properties, in get_meta_list
	# order. Rebuild this small suffix so additions/removals remain observable.
	var keys:=material.get_meta_list()
	if keys.is_empty():return names
	var result:=names.duplicate()
	for name:StringName in keys:result.append("metadata/"+String(name))
	return result
