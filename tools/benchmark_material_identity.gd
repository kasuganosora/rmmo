extends SceneTree
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var totals:={"properties":0,"values":0,"text":0,"binary":0};var allowed:Array=[]
	var reference:=StandardMaterial3D.new()
	for property in reference.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and not str(property.name).begins_with("resource_") and property.name!="script":allowed.append(property.name)
	var exact:=true;var old_groups:={};var new_groups:={}
	for i in 2000:
		var material:=StandardMaterial3D.new();material.albedo_color=Color(float(i%12)/12.,.3,.4);material.roughness=float(i%9)/9.
		material.normal_enabled=i%2==0;material.emission_enabled=i%3==0;material.clearcoat_enabled=i%5==0
		var start:=Time.get_ticks_usec();var properties:=material.get_property_list();totals.properties+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
		var values:Array=[];var names:Array=[]
		for property in properties:
			if property.usage & PROPERTY_USAGE_STORAGE and not str(property.name).begins_with("resource_") and property.name!="script":
				names.append(property.name);values.append([property.name,material.get(property.name)])
		totals["values"]+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
		var old:=var_to_str(values).sha256_text();totals.text+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
		var next:=Cook.Envelope.checksum(var_to_bytes(values)).hex_encode();totals.binary+=Time.get_ticks_usec()-start
		exact=exact and names==allowed
		if old_groups.has(old):exact=exact and old_groups[old]==next
		if new_groups.has(next):exact=exact and new_groups[next]==old
		old_groups[old]=next;new_groups[next]=old
	print("MATERIAL_IDENTITY_BENCHMARK ",JSON.stringify({"us":totals,"schema_and_partition_equal":exact,"properties":allowed.size(),"groups":old_groups.size()}));quit(0 if exact else 1)
