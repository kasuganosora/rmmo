extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var rows:Array=[]
func _init()->void:call_deferred("run")
func run()->void:
	var path:=Paths.external_root().path_join("maps/medieval_river_town/map.gltf")
	var signature:=FileAccess.get_sha256(path)
	var doc=Doc.open_file(path)
	if doc==null:quit(1);return
	var definitions:Array=[
		["tree","parametric_tree"],["events","event_templates"],["building","building_blueprint"],
		["auto_tile","auto_tile_rules"],["road","road_surface"],["terrain","terrain_surface"],
		["channel","channel_surface"],["fortification","fortification_data"],["materials","surface_materials"],["wind","wind_response"]]
	for iteration in 2:
		var report:Dictionary={"iteration":iteration,"records":doc.records.size(),"validators":{}}
		var began:=Time.get_ticks_usec();var err:Error=doc.validate_save_meta()
		report.meta_ms=(Time.get_ticks_usec()-began)/1000.;report.meta_error=err
		for item:Array in definitions:
			var script=load("res://scripts/world3d/%s.gd"%item[1]);var cache:Dictionary={}
			var elapsed:=0;var maximum:=0;var slowest:="";var invalid:=0
			for record:Dictionary in doc.records:
				began=Time.get_ticks_usec()
				var valid:bool
				if item[0]=="materials":valid=script.valid(record,false,"",cache)
				elif item[0] in ["events","building","fortification"]:valid=script.valid_record(record)
				else:valid=script.valid(record)
				var sample:=Time.get_ticks_usec()-began;elapsed+=sample
				if sample>maximum:maximum=sample;slowest=record.uuid
				if not valid:invalid+=1
			report.validators[item[0]]={"ms":elapsed/1000.,"max_ms":maximum/1000.,"slowest":slowest,"invalid":invalid}
		began=Time.get_ticks_usec()
		for record:Dictionary in doc.records:
			if record.get("kind")=="asset":Paths.allowed(str(record.get("asset_path","")))
		report.asset_paths_ms=(Time.get_ticks_usec()-began)/1000.
		rows.append(report);print("SAVE_VALIDATION_PROFILE ",JSON.stringify(report))
	var output:=Paths.external_root().path_join("review_artifacts/reference_save_validation_20261008.json")
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"rows":rows,"source":path,"source_unchanged":FileAccess.get_sha256(path)==signature},"\t"));file.close()
	print("SAVE_VALIDATION_FINISHED ",output);quit(0)
