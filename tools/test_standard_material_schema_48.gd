extends SceneTree
## Standalone native-property contract: needs only StandardMaterialSchema.
const Schema=preload("res://scripts/world3d/standard_material_schema.gd")
const PHYSICAL_LIGHT_UNITS="rendering/lights_and_shadows/use_physical_light_units"
const ALPHA_MODES=BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE+1
const BILLBOARD_MODES=BaseMaterial3D.BILLBOARD_PARTICLES+1
class Scripted extends StandardMaterial3D:
	@export var extra_value:=12
	var hide_extra:=false
	func _validate_property(property:Dictionary)->void:
		if property.name==&"extra_value" and hide_extra:property.usage=PROPERTY_USAGE_NONE

var checks:=0
var failures:Array[String]=[]
var states:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);print("FAIL: ",label)
func native_names(material:StandardMaterial3D,metadata:bool)->Array:
	var result:Array=[]
	for property:Dictionary in material.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and (metadata or not str(property.name).begins_with("metadata/")):
			result.append(property.name)
	return result
func values(material:StandardMaterial3D,names:Array)->Array:
	var result:Array=[]
	for name:Variant in names:result.append([name,material.get(name)])
	return result
func compare(material:StandardMaterial3D,label:String)->void:
	for metadata:bool in [false,true]:
		var expected:=native_names(material,metadata)
		var actual:=Schema.storage_names(material,metadata)
		check(var_to_bytes(actual)==var_to_bytes(expected),"names, types and order "+label+str(metadata))
		check(var_to_bytes(values(material,actual))==var_to_bytes(values(material,expected)),"live stored values "+label+str(metadata))
	states+=1
func parallel_names(index:int)->bool:
	var material:=StandardMaterial3D.new();material.shading_mode=index%3
	var expected:=var_to_bytes(native_names(material,false))
	for iteration:int in 128:
		if var_to_bytes(Schema.storage_names(material))!=expected:return false
	return true
func finish()->void:
	print("STANDARD_MATERIAL_SCHEMA_48 ",JSON.stringify({"engine":Engine.get_version_info(),"checks":checks,"failures":failures,"states":states,"cache":Schema.snapshot(),"scope":"headless native storage names and live values; no GPU/performance claim"}))
	quit(1 if not failures.is_empty() else 0)
func run()->void:
	check(int(Engine.get_version_info().hex)==0x040800,"running reviewed 4.8.0 engine")
	check(Schema.supported,"4.8 native storage schema reuse is enabled")
	var material:=StandardMaterial3D.new()
	Schema._schemas.clear();Schema.enumerations=0;Schema.hits=0
	var first:=Schema.storage_names(material)
	var second:=Schema.storage_names(material)
	check(var_to_bytes(first)==var_to_bytes(native_names(material,false)),"default native storage names")
	check(first==second and Schema.enumerations==1 and Schema.hits==1,"same-mode repeated request enumerates once")
	check(second.is_read_only(),"shared name arrays are immutable")
	if not failures.is_empty():finish();return
	var physical_before:Variant=ProjectSettings.get_setting(PHYSICAL_LIGHT_UNITS,false)
	for physical:bool in [false,true]:
		ProjectSettings.set_setting(PHYSICAL_LIGHT_UNITS,physical)
		for transparency:int in BaseMaterial3D.TRANSPARENCY_MAX:
			for aa:int in ALPHA_MODES:
				for billboard:int in BILLBOARD_MODES:
					for shading:int in BaseMaterial3D.SHADING_MODE_MAX:
						for deep:bool in [false,true]:
							for skin:bool in [false,true]:
								if Schema._schemas.size()>=Schema.LIMIT:Schema._schemas.clear()
								material.transparency=transparency;material.alpha_antialiasing_mode=aa
								material.billboard_mode=billboard;material.shading_mode=shading
								material.heightmap_deep_parallax=deep;material.subsurf_scatter_skin_mode=skin
								compare(material,"mode "+str(states))
	ProjectSettings.set_setting(PHYSICAL_LIGHT_UNITS,physical_before)
	material=StandardMaterial3D.new();Schema._schemas.clear()
	compare(material,"4.8 defaults")
	# Any new feature flag must preserve storage names or enter the cache key.
	for property:Dictionary in material.get_property_list():
		if property.type!=TYPE_BOOL or not (property.usage & PROPERTY_USAGE_STORAGE):continue
		var original:bool=material.get(property.name)
		material.set(property.name,not original)
		compare(material,"boolean "+str(property.name))
		material.set(property.name,original)
	for stencil:int in 4:
		material.stencil_mode=stencil
		compare(material,"stencil "+str(stencil))
	material=StandardMaterial3D.new()
	material.albedo_color=Color.GREEN;material.roughness=.23;material.uv1_scale=Vector3(2,3,4)
	compare(material,"changed values")
	compare(StandardMaterial3D.new(),"new material retains native defaults after shared-schema use")
	material.set_meta("semantic",{"a":3});material.set_meta("_private",Color.RED)
	compare(material,"metadata add")
	material.remove_meta("semantic");material.set_meta("_private",Color.BLUE)
	compare(material,"metadata remove/change")
	var scripted:=Scripted.new();compare(scripted,"scripted fallback")
	scripted.hide_extra=true;compare(scripted,"scripted dynamic usage")
	Schema.supported=false;compare(material,"unreviewed engine fallback");Schema.supported=true
	Schema.enabled=false;compare(material,"disabled cache fallback");Schema.enabled=true
	Schema._schemas.clear()
	for transparency:int in BaseMaterial3D.TRANSPARENCY_MAX:
		for aa:int in ALPHA_MODES:
			for billboard:int in BILLBOARD_MODES:
				for shading:int in 2:
					material.transparency=transparency;material.alpha_antialiasing_mode=aa;material.billboard_mode=billboard;material.shading_mode=shading
					compare(material,"bounded cache "+str(states))
	check(Schema._schemas.size()==Schema.LIMIT,"schema cache stays bounded")
	Schema._schemas.clear()
	var workers:Array[Thread]=[]
	for i:int in 4:
		var worker:=Thread.new()
		check(worker.start(parallel_names.bind(i))==OK,"parallel reader starts")
		workers.append(worker)
	for worker:Thread in workers:check(worker.wait_to_finish(),"concurrent reads preserve native schema")
	finish()
