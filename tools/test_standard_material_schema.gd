extends SceneTree
const Schema=preload("res://scripts/world3d/standard_material_schema.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Merge=preload("res://scripts/world3d/ground_batch_geometry.gd")
class Scripted extends StandardMaterial3D:
	@export var extra_value:=12
	var hide_extra:=false
	func _validate_property(property:Dictionary)->void:
		if property.name==&"extra_value" and hide_extra:property.usage=PROPERTY_USAGE_NONE

var checks:=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func native_names(material:StandardMaterial3D,metadata:bool)->Array:
	var result:Array=[]
	for property:Dictionary in material.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and (metadata or not str(property.name).begins_with("metadata/")):result.append(property.name)
	return result
func compare(material:StandardMaterial3D,label:String)->void:
	for metadata:bool in [false,true]:
		check(var_to_bytes(Schema.storage_names(material,metadata))==var_to_bytes(native_names(material,metadata)),"native property order/type/usage "+label+str(metadata))
	Schema.enabled=false
	var expected_data:=var_to_bytes(Cook.material_data(material));var expected_key:=Merge.material_key(material)
	Schema.enabled=true
	check(expected_data==var_to_bytes(Cook.material_data(material)),"serialized values unchanged "+label)
	check(expected_key==Merge.material_key(material),"batch digest unchanged "+label)
func parallel_names(index:int)->bool:
	var material:=StandardMaterial3D.new();material.shading_mode=index%3
	var expected:=var_to_bytes(native_names(material,false))
	for i:int in 256:
		if var_to_bytes(Schema.storage_names(material))!=expected:return false
	return true
func run()->void:
	check(Schema.supported,"reviewed engine schema is exercised")
	var material:=StandardMaterial3D.new()
	for physical:bool in [false,true]:
		ProjectSettings.set_setting("rendering/lights_and_shadows/use_physical_light_units",physical)
		for transparency:int in BaseMaterial3D.TRANSPARENCY_MAX:
			for aa:int in 3:
				for billboard:int in 4:
					for shading:int in 3:
						for deep:bool in [false,true]:
							for skin:bool in [false,true]:
								# Rotate at the cap so consecutive state changes exercise
								# hot schemas as well as fresh native enumeration.
								if Schema._schemas.size()>=Schema.LIMIT:Schema._schemas.clear()
								material.transparency=transparency;material.alpha_antialiasing_mode=aa
								material.billboard_mode=billboard;material.shading_mode=shading
								material.heightmap_deep_parallax=deep;material.subsurf_scatter_skin_mode=skin
								compare(material,"modes")
	ProjectSettings.set_setting("rendering/lights_and_shadows/use_physical_light_units",false)
	material=StandardMaterial3D.new();Schema._schemas.clear()
	compare(material,"default")
	material.set_meta("semantic",{"a":3});material.set_meta("_private",Color.RED)
	compare(material,"metadata add")
	material.remove_meta("semantic");material.set_meta("_private",Color.BLUE)
	compare(material,"metadata remove/change")
	material.albedo_color=Color.GREEN;material.roughness=.23;material.uv1_scale=Vector3(2,3,4)
	compare(material,"live values")
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	compare(material,"same owner changes schema")
	var scripted:=Scripted.new();compare(scripted,"script property")
	scripted.hide_extra=true;compare(scripted,"script dynamic usage")
	var supported_before:=Schema.supported
	Schema.supported=false;compare(material,"unreviewed engine fallback");Schema.supported=supported_before
	Schema._schemas.clear()
	for transparency:int in BaseMaterial3D.TRANSPARENCY_MAX:
		for aa:int in 3:
			for billboard:int in 4:
				for shading:int in 2:
					material.transparency=transparency;material.alpha_antialiasing_mode=aa;material.billboard_mode=billboard;material.shading_mode=shading
					check(var_to_bytes(Schema.storage_names(material))==var_to_bytes(native_names(material,false)),"bounded schema fallback")
	check(Schema._schemas.size()==Schema.LIMIT,"schema cache retains at most 64 name arrays")
	Schema._schemas.clear()
	var workers:Array[Thread]=[]
	for i:int in 4:
		var worker:=Thread.new()
		check(worker.start(parallel_names.bind(i))==OK,"parallel reader starts");workers.append(worker)
	for worker:Thread in workers:check(worker.wait_to_finish(),"concurrent misses and reuse preserve schema")
	check(Schema.storage_names(StandardMaterial3D.new()).is_read_only(),"shared names cannot be mutated by a consumer")
	var materials:Array[StandardMaterial3D]=[]
	for i:int in 512:
		var sample:=StandardMaterial3D.new();sample.albedo_color=Color(float(i)/512,.2,.7);sample.roughness=float(i%10)/10
		materials.append(sample)
	Schema._schemas.clear();Schema.enumerations=0;Schema.hits=0
	for use_cache:bool in [false,true,true,false]:
		Schema.enabled=use_cache;var began:=Time.get_ticks_usec();var bytes:=0;var keys:=0
		for sample:StandardMaterial3D in materials:
			bytes+=var_to_bytes(Cook.material_data(sample)).size();keys+=Merge.material_key(sample).length()
		print("SCHEMA_PRESSURE enabled=",use_cache," elapsed_us=",Time.get_ticks_usec()-began," bytes=",bytes," key_chars=",keys," enumerations=",Schema.enumerations," hits=",Schema.hits)
	Schema.enabled=true
	check(Schema.enumerations==(0 if "--before-consumers" in OS.get_cmdline_user_args() else 1),"same-mode consumer enumeration contract")
	print("STANDARD_MATERIAL_SCHEMA checks=",checks," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
