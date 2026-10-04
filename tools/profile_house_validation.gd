extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var path:="D:/code/rmmo_runtime/maps/medieval_house_showcase_v8/map.gltf"
	var meta:Dictionary=preload("res://scripts/world3d/map_metadata_cache.gd").read(path,FileAccess.get_sha256(path))
	var records:Array=meta.rmmo_records
	var validators:={"fixture":preload("res://scripts/world3d/building_fixtures.gd").valid,"building":preload("res://scripts/world3d/building_blueprint.gd").valid_record,"wind":preload("res://scripts/world3d/wind_response.gd").valid,"terrain":preload("res://scripts/world3d/terrain_surface.gd").valid,"river":preload("res://scripts/world3d/river_material_data.gd").valid,"auto_tile":preload("res://scripts/world3d/auto_tile_rules.gd").valid,"events":preload("res://scripts/world3d/event_templates.gd").valid_record}
	for name_:String in validators:
		var start:=Time.get_ticks_usec()
		for record:Dictionary in records:validators[name_].call(record)
		print("VALIDATION_COMPONENT ",name_," ms=",(Time.get_ticks_usec()-start)/1000.)
	var validation:Dictionary={};var content_root:=preload("res://scripts/world3d/map_paths.gd").external_root()
	var start:=Time.get_ticks_usec()
	for record:Dictionary in records:preload("res://scripts/world3d/surface_materials.gd").valid(record,false,content_root,validation)
	print("VALIDATION_COMPONENT paint ms=",(Time.get_ticks_usec()-start)/1000.)
	start=Time.get_ticks_usec();var definitions:Dictionary={}
	for record:Dictionary in records:
		for value in preload("res://scripts/world3d/surface_materials.gd").definitions(record):definitions[value]=true
	print("VALIDATION_COMPONENT definitions ms=",(Time.get_ticks_usec()-start)/1000.)
	quit()
