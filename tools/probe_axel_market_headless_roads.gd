extends SceneTree
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
func _initialize():call_deferred("run")
func run():
	var doc=Doc.open_file(MAP);var rows:Array=[];var bad:Array=[]
	for record:Dictionary in doc.records:
		if not record.has("road_mesh"):continue
		var mesh:Mesh=Surface.mesh(record,null);var captured:Mesh=Cpu.capture(mesh);var vertices:=0;var invalid:=false
		for arrays:Array in captured.surfaces:
			if arrays.size()!=Mesh.ARRAY_MAX or arrays[Mesh.ARRAY_VERTEX]==null:invalid=true;continue
			vertices+=arrays[Mesh.ARRAY_VERTEX].size()
		var row:={"uuid":record.uuid,"road_source":record.get("road_source",""),"vertices":vertices,"invalid":invalid}
		rows.append(row)
		if invalid or vertices==0:bad.append(row)
	var report:={"source_map_sha256":FileAccess.get_sha256(MAP),"headless":DisplayServer.get_name()=="headless","serial_native_road_mesh_records":rows,"invalid_records":bad,"scope":"Serial native road meshing and CPU capture only; no full scene/asset load, no source mutation, no GPU proof","observed_full_load_trigger":"road_surface.gd:66 ArrayMesh.add_surface_from_arrays after native Dummy RID initialization errors; subsequent size(Nil) is downstream","precise_original_record_uuid":"not recorded in the historical async error log; do not invent asset attribution","comparison":"Earlier full headless pass had no Dummy RID errors; a repeated full headless load did. No current GPU reproduction performed."}
	FileAccess.open(OUT+"/market_headless_road_diagnostic.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SERIAL_NATIVE_ROADS records=",rows.size()," invalid=",bad.size());quit(0 if bad.is_empty() else 1)
