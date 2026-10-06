extends "res://tools/arrange_town_reference_styles.gd"
const Banks=preload("res://scripts/world_editor/rock_bank_tools.gd")
const Bank=preload("res://scripts/world3d/rock_bank_mesh.gd")
const OUT_BANK="D:/code/rmmo_runtime/review_artifacts/bridge_terrain_finish_20261006"
const MAP_BANK="D:/code/rmmo_runtime/cache/world3d/bridge_terrain_finish_20261006/map.gltf"
func _initialize()->void:
	OUT=OUT_BANK;TARGET=MAP_BANK;run.call_deferred()
func contour(terrain_doc,pose:Transform3D,lateral:float,height:float)->float:
	var low:=0.;var high:=55.
	for i in 24:
		var middle:float=(low+high)*.5
		if ground(terrain_doc,pose*Vector3(middle,0,lateral))<height:low=middle
		else:high=middle
	return (low+high)*.5
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if "--publish" in OS.get_cmdline_user_args():
		var result:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/result.json"));var runtime:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/runtime_result.json"))
		check(result.failures==0 and runtime.failures==0 and result.candidate_sha256==runtime.candidate_sha256,"tested terrain candidate")
		check(FileAccess.get_sha256(TARGET)==result.candidate_sha256 and FileAccess.get_sha256(FORMAL)==result.formal_sha256,"source and tested candidate unchanged")
		if failures:quit(1);return
		var destination=Doc.open_file(FORMAL);var candidate=Doc.open_file(TARGET)
		check(destination!=null and candidate!=null and FileAccess.get_sha256(FORMAL)==result.formal_sha256,"validated publication documents")
		if failures:quit(1);return
		destination.records=candidate.records;destination.map_meta=candidate.map_meta;destination._next=candidate._next
		check(destination.save(FORMAL)==OK,"native atomic terrain publication")
		var reopened=Doc.open_file(FORMAL);check(reopened!=null and equivalent(reopened.records,candidate.records) and equivalent(reopened.map_meta,candidate.map_meta),"formal reopen matches")
		write_report("published.json",{"failures":failures,"formal_sha256":FileAccess.get_sha256(FORMAL),"candidate_sha256":result.candidate_sha256,"bank_ids":result.bank_ids,"houses_changed":false});quit(1 if failures else 0);return
	var doc
	if "--plan-only" in OS.get_cmdline_user_args():
		var extras:Dictionary=Doc.authoritative_extras(FORMAL).extras;doc=Doc.new();doc.records=extras.rmmo_records;doc.map_meta=extras.duplicate();doc.map_meta.erase("rmmo_records")
	else:doc=Doc.open_file(FORMAL)
	check(doc!=null,"formal source readable")
	if doc==null:quit(1);return
	var original:Array=doc.records.duplicate(true);var meta:Dictionary=doc.map_meta.duplicate(true);var baseline:=FileAccess.get_sha256(FORMAL)
	var bridge:Dictionary=doc._find("stone_e_0be972769041dbc9");var pose:=Transform3D(Basis(Vector3.UP,deg_to_rad(bridge.rotation[1])),Vector3(bridge.position[0],0,bridge.position[2]))
	var recipe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/art_sources/bridge_reference_scene_20261006/bank_recipe.json"))
	var materials=preload("res://scripts/world_editor/surface_material_library.gd").new()
	var ids:Array=[]
	var terrain_doc:=Doc.new();terrain_doc.records=doc.records.filter(func(r):return r.has("terrain_mesh"))
	var roads:Array=[]
	for r:Dictionary in doc.records:
		if r.has("road_mesh"):roads.append_array(preload("res://scripts/world_editor/building_footprint.gd").record_shapes(r))
	var layouts:Array=[]
	for end in [1,-1]:
		for source:Dictionary in recipe.banks:
			var bank:Dictionary=source.duplicate(true);bank.end=end;layouts.append(bank)
	var bridge_pose:=pose
	for bank:Dictionary in layouts:
		pose=bridge_pose*Transform3D(Basis(Vector3.UP,PI if bank.end<0 else 0.),Vector3.ZERO)
		# Land meets the end abutment, then turns out along the river. Do not
		# fill the last arch or the cutwater envelope with a raised bank.
		bank.cross_sections[0][0]=5.55*bank.side
		for row:Array in bank.cross_sections:
			# Sample the real water contour across the complete half-channel;
			# the earlier art study's 19 m search bound missed the bending right bank.
			row[1]=contour(terrain_doc,pose,row[0],lerpf(-1.6,-2.25,smoothstep(6.,14.,absf(row[0]))))
			row[2]=contour(terrain_doc,pose,row[0],-.005)+.4
			row[3]=lerpf(-2.25,.13+.13*sin(row[0]*.47)+.05*sin(row[0]*1.1),row[4])
		var points:Array=[];var heights:Array=[];var widths:Array=[]
		for i in bank.cross_sections.size():
			var row:Array=bank.cross_sections[i];var at:Vector3=pose*Vector3(row[1],row[3],row[0]);points.append(Bank.arr(at))
			var before:Array=bank.cross_sections[maxi(0,i-1)];var after_:Array=bank.cross_sections[mini(bank.cross_sections.size()-1,i+1)]
			var normal:Vector3=pose.basis.x
			var width:float=(row[2]-row[1])/maxf(.5,normal.dot(pose.basis.x));var a:=Vector2(at.x,at.z);var b:=a+Vector2(normal.x,normal.z)*width
			for road:Dictionary in roads:
				var poly:PackedVector2Array=road.polygon
				for j in poly.size()-1:
					var hit:Variant=Geometry2D.segment_intersects_segment(a,b,poly[j],poly[j+1])
					if hit!=null:width=minf(width,a.distance_to(hit)-.65)
			width=maxf(.5,width)
			widths.append(width);heights.append(ground(doc,at+normal*width))
		var args:={"id":("bridge_reference_bank_" if bank.end>0 else "bridge_reference_west_bank_")+str(int(bank.side)+1),"name":"东南桥 · "+("东" if bank.end>0 else "西")+"岸 "+str(bank.side),"points":points,"inner_heights":heights,"inner_widths":widths,"height":3.1,"cap_width":8.,"cap_angle":rad_to_deg(atan2(pose.basis.x.z,pose.basis.x.x)),"side":"right" if bank.side<0 else "left","roughness":.37,"seed":20261006+int(bank.side),"water_level":-1.5}
		args.direction_mode="fixed"
		args.rock_material_id="pack:default:terrain/beach_cliff/material";args.roughness=.4
		var plan:=Banks.plan(doc,args,materials,func(r):return preload("res://scripts/world_editor/selection_geometry.gd").editable(r))
		print("BANK_PLAN ",plan if not plan.ok else {"id":plan.record.uuid,"triangles":plan.triangles,"bounds":plan.bounds})
		check(plan.ok,"native bank plan")
		if not plan.ok:quit(1);return
		Banks.commit(doc,plan);ids.append(plan.record.uuid)
	check(equivalent(original.filter(func(r):return not r.uuid in ids),doc.records.filter(func(r):return not r.uuid in ids)) and equivalent(meta,doc.map_meta),"existing terrain roads houses reservations unchanged")
	var after:Array=doc.records.duplicate(true)
	for i in ids.size():check(doc.undo(),"undo bank")
	check(equivalent(original,doc.records),"undo restores source")
	for i in ids.size():check(doc.redo(),"redo bank")
	check(equivalent(after,doc.records),"redo restores banks")
	if "--plan-only" in OS.get_cmdline_user_args():
		write_report("plan.json",{"failures":failures,"banks":doc.records.filter(func(r):return r.uuid in ids),"formal_sha256":baseline});quit(failures);return
	check(doc.save(TARGET)==OK,"native candidate save")
	var reopened=Doc.open_file(TARGET);check(reopened!=null and equivalent(reopened.records,doc.records),"candidate reopen")
	write_report("result.json",{"failures":failures,"bank_ids":ids,"formal_sha256":baseline,"candidate_sha256":FileAccess.get_sha256(TARGET),"bridge_id":bridge.uuid,"houses_changed":false})
	quit(1 if failures else 0)
