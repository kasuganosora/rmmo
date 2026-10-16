extends "res://tools/review_axel_functional_building_exteriors.gd"
## CPU-only compatibility check of the actual published source accessors.
## No GPU, native editor, map write, or interior traversal.
func run()->void:
	started_ms=Time.get_ticks_msec();output=FB_OUT+"/functional_exterior_source_contract";DirAccess.make_dir_recursive_absolute(output)
	report={"checks":[],"sources":[],"screenshots":[],"phase":"source_contract_only","scope":"Helper reads exact published source geometry; this is not current map/GPU acceptance"}
	handoff=JSON.parse_string(FileAccess.get_file_as_string(FB_OUT+"/blender_building_handoff.json"))
	for key:String in KEYS:
		var publication:Dictionary=handoff.formal_publications[key];var path:String=publication.asset_id
		check(FileAccess.get_sha256(path)==publication.source.sha256,"actual published source SHA "+key)
		var record:={"uuid":"source_contract_"+key,"asset_path":path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
		var data:=source_geometry(record);check(data.get("ok",false),"real GLB accessors decoded "+key)
		if not data.get("ok",false):continue
		var floors:=0;var triangle_count:=0;var river_modules:Dictionary={}
		for part:Dictionary in data.parts:
			triangle_count+=part.triangles.size()
			if part.semantic.get("floor",-1)==0 and part.semantic.get("role","")=="floor" and part.world_box.position.y<=.005 and not part.triangles.is_empty():floors+=1
			if str(part.semantic.get("part","")).begins_with("river_foundation_"):river_modules[part.semantic.part]=part.triangles.size()
		check(floors>0 and triangle_count>0,"actual low bearing/source tread geometry "+key)
		if key=="watermill":
			check(river_modules.size()==7 and river_modules.values().all(func(n):return n>0),"all seven real mill foundation modules have triangles")
			var wheels:Array=data.parts.filter(func(p):return p.semantic.get("part","")=="waterwheel")
			check(wheels.size()==1 and absf(wheels[0].world_box.position.y+1.2)<.001 and wheels[0].transform.origin.distance_to(Vector3(6.85,1.1,0))<.001,"actual source wheel bottom and pivot use expected local frame")
		report.sources.append({"key":key,"asset":path,"sha256":publication.source.sha256,"components":data.parts.size(),"decoded_bearing_tread_triangles":triangle_count,"low_floor_components":floors,"river_foundation_modules":river_modules})
	report.helper_sha256=FileAccess.get_sha256("res://tools/review_axel_functional_building_exteriors.gd");finish()
