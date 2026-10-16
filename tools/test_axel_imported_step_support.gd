extends "res://tools/review_axel_functional_building_exteriors.gd"
## Regress real source meshes and captured headless query/environment pairs.
func run()->void:
	started_ms=Time.get_ticks_msec();report={"checks":[],"scope":"CPU source geometry and real headless collision-pair predicate regression; final-map movement remains separately required"}
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FB_OUT+"/final_candidate_records.json"))
	var build:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FB_OUT+"/functional_buildings_apply.json"))
	var probe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FB_OUT+"/imported_step_contact_probe.json"))
	var source_rows:Array=[]
	for key:String in KEYS:
		var placement:Dictionary=build.placements.filter(func(p):return p.key==key)[0]
		var record:Dictionary=data.records.filter(func(r):return r.uuid==placement.uuid)[0]
		var access:Dictionary=build.outdoor_access.filter(func(r):return r.key==key)[0]
		var source:=source_geometry(record);check(source.ok,"source decodes "+key)
		prepare_imported_treads(record,source,access)
		if key!="watermill":
			var row:Dictionary=probe.rows.filter(func(r):return r.key==key)[0]
			var pairs:=PackedVector3Array()
			for pair:Dictionary in row.pairs:pairs.append(vector(pair.a));pairs.append(vector(pair.b))
			var result:=step_contact_points(vector(row.feet),row.id,pairs)
			check(result.passed,"actual capsule/environment pair endpoints classified correctly "+key,result)
			var high:=pairs.duplicate();high[1]+=Vector3.UP*.5
			check(not step_contact_points(vector(row.feet),row.id,high).passed,"high obstacle retains rejection "+key)
			var foreign:=pairs.duplicate();foreign[1]+=Vector3.RIGHT*8.
			check(not step_contact_points(vector(row.feet),row.id,foreign).passed,"foreign wall/point outside exact tread retains rejection "+key)
			check(not step_contact_points(vector(row.feet),row.id+"_door",pairs).passed,"door collider has no tread exemption "+key)
			source_rows.append({"key":key,"actual_pairs":result})
		else:
			var id:=str(record.uuid)+"__watermill_porch_walk"
			var part:Dictionary=source.parts.filter(func(p):return p.id==id)[0]
			check(part.semantic.role=="body" and part.collision=="walk" and not part.triangles.is_empty(),"body-role porch uses explicit authored walk collision")
			for offset:float in [.85,1.2,1.8]:
				var point:=active_threshold+active_outward*offset
				point.y=3.91 if offset==1.8 else 4.
				check(authored_step(point,id),"watermill exact exterior porch top accepted "+str(offset),{"point":xyz(point)})
			var original:=Vector3(301.572875976563,4.,205.337158203125)
			check(authored_step(original,id),"failed runtime watermill standing contact is an actual porch top")
			check(not authored_step(original-Vector3.UP*.1,id),"porch underside not accepted as walkable top")
			check(not authored_step(original+Vector3.UP*.5,id),"point above porch rejected")
			check(not authored_step(active_threshold-active_outward,id),"indoor floor is outside exterior review band")
			check(not authored_step(original,str(record.uuid)+"__watermill_porch_block"),"solid porch block does not inherit walkable part identity")
			source_rows.append({"key":key,"porch_triangles":part.triangles.size(),"accepted_top_triangles":tread_triangles.get(id,[]).size()})
		for part:Dictionary in source.parts:
			if not tread_triangles.has(part.id):continue
			check(tread_triangles[part.id].all(func(t):return (t[1]-t[0]).cross(t[2]-t[0]).normalized().y>=.99),"only upward source faces accepted "+key+" "+part.source_id)
	report.failures=failures;report.passed=failures==0;report.source_rows=source_rows
	report.final_candidate_sha256=data.map_sha256
	report.predicate_source_sha256=FileAccess.get_sha256("res://tools/review_axel_functional_building_exteriors.gd")
	report.collision_probe_sha256=FileAccess.get_sha256(FB_OUT+"/imported_step_contact_probe.json")
	var file:=FileAccess.open(FB_OUT+"/imported_step_support_precheck.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("IMPORTED_STEP_SUPPORT_PRECHECK failures=",failures," checks=",report.checks.size());quit(0 if failures==0 else 1)
