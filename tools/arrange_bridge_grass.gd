extends "res://tools/arrange_town_reference_styles.gd"
const GRASS_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_grass_20261006"
const GRASS_MAP="D:/code/rmmo_runtime/cache/world3d/bridge_grass_20261006/map.gltf"
const Bank=preload("res://scripts/world3d/rock_bank_mesh.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
var rng:=RandomNumberGenerator.new()
var entries:Dictionary={}
var obstacles:Array=[]
var supports:Array=[]
var placements:Array=[]
var reference_keys:Array=[]
var cap_triangles:Array=[]
var zone_obstacles:Array=[]
func _initialize()->void:
	OUT=GRASS_OUT;TARGET=GRASS_MAP;run.call_deferred()
func clear_of_paths(at:Vector3,radius:float,bank_id:String)->bool:
	var point:=Vector2(at.x,at.z)
	var polygons:Array=obstacles.duplicate()
	for zone:Dictionary in zone_obstacles:
		# The old navigable-water projection extends over the subsequently
		# approved native banks. Non-colliding grass on those dry caps cannot
		# obstruct boats; keep all other reservations and the water itself clear.
		if str(zone.id).begins_with("river_corridor") and bank_id.begins_with("bridge_reference_"):continue
		polygons.append(zone.polygon)
	for poly:PackedVector2Array in polygons:
		if Geometry2D.is_point_in_polygon(point,poly):return false
		for i in poly.size():
			if Geometry2D.get_closest_point_to_segment(point,poly[i],poly[(i+1)%poly.size()]).distance_to(point)<radius:return false
	return true
func surface_height(doc,at:Vector3)->float:
	var height:float=ground(doc,at)
	for triangle:Array in cap_triangles:
		var hit:Variant=Geometry3D.ray_intersects_triangle(at+Vector3.UP*20,Vector3.DOWN,triangle[0],triangle[1],triangle[2])
		if hit!=null:height=maxf(height,hit.y)
	return height
func add_clump(stage,at:Vector3,key:String,scale_:float,bank_id:String)->void:
	var bounds:Array=entries[key].bounds_size
	var radius:float=Vector2(bounds[0],bounds[2]).length()*.5*scale_+.08
	if not at.is_finite() or at.y<-.25 or not clear_of_paths(at,radius,bank_id):return
	for item:Dictionary in placements:
		if B.vec(item.position).distance_to(at)<.29:return
	var placed:=Library.place(stage,entries[key],at)
	if not placed.ok:check(false,str(placed));return
	var record:Dictionary=stage._find(placed.ids[0])
	record.uuid="bridge_grass_%04d"%placements.size();record.position=B.arr(at+Vector3.DOWN*.018)
	record.rotation=[0,rng.randf_range(-180,180),0];record.size=[scale_,scale_,scale_]
	record.label=entries[key].label;record.editor_group_name="东南桥 · 岸边混生草";record.collision="none"
	placements.append({"id":record.uuid,"source":key,"position":record.position,"bank":bank_id})
	stage._undo.clear()
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT);DirAccess.make_dir_recursive_absolute(TARGET.get_base_dir())
	if "--publish" in OS.get_cmdline_user_args():
		var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/result.json"))
		var review:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/runtime_result.json"))
		check(report.failures==0 and review.failures==0 and review.candidate_sha256==FileAccess.get_sha256(TARGET),"reviewed grass candidate")
		check(FileAccess.get_sha256(FORMAL)==report.formal_sha256,"formal baseline unchanged")
		for path:String in report.source_assets:check(FileAccess.get_sha256(path)==report.source_assets[path],"reviewed grass asset unchanged")
		if failures:quit(1);return
		var doc=Doc.open_file(FORMAL);var candidate=Doc.open_file(TARGET)
		doc.records=candidate.records;doc.map_meta=candidate.map_meta;doc._next=candidate._next
		check(doc.save(FORMAL)==OK,"native atomic grass publication")
		var reopened=Doc.open_file(FORMAL)
		check(reopened!=null and equivalent(reopened.records,doc.records) and equivalent(reopened.map_meta,doc.map_meta),"formal grass save reopen")
		write_report("published.json",{"failures":failures,"formal_sha256":FileAccess.get_sha256(FORMAL),"count":report.placements.size()});quit(failures);return
	var baseline:=FileAccess.get_sha256(FORMAL)
	var extras:Dictionary=Doc.authoritative_extras(FORMAL).extras
	var doc:=Doc.new();doc.records=extras.rmmo_records;doc.map_meta=extras.duplicate();doc.map_meta.erase("rmmo_records")
	check(not doc.records.any(func(r):return str(r.uuid).begins_with("bridge_grass_")),"no prior grass placement overwritten")
	if failures:quit(1);return
	var publication:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/town_grass/published.json"))
	for item:Dictionary in publication.entries:entries[item.id]=item.entry
	check(entries.size()==11,"eleven published grass prefabs")
	var clump_manifest:String="D:/code/rmmo_runtime/review_artifacts/reference_grass_clumps/published.json"
	if FileAccess.file_exists(clump_manifest):
		var clumps:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(clump_manifest))
		for item:Dictionary in clumps.entries:
			entries[item.id]=item.entry;reference_keys.append(item.id)
	var hashes:Dictionary={}
	for key:String in entries:
		var loaded:=Library.read(entries[key]);check(loaded.ok,"published prefab "+key)
		if loaded.ok:hashes[loaded.records[0].asset_path]=FileAccess.get_sha256(loaded.records[0].asset_path)
	for record:Dictionary in doc.records:
		if record.has("road_mesh") or record.has("building") or record.has("bridge_mesh"):
			for shape:Dictionary in Foot.record_shapes(record):obstacles.append(shape.polygon)
		if record.has("rock_bank") and str(record.uuid).begins_with("bridge_reference_"):supports.append(record)
	for zone:Dictionary in doc.map_meta.get("editor_layout",{}).get("zones",[]):
		if zone.purpose!="no_build" or str(zone.id).begins_with("user_"):
			zone_obstacles.append({"id":zone.id,"polygon":preload("res://scripts/world3d/planning_zones.gd").polygon(zone)})
	check(supports.size()==4,"four published banks")
	var stage:=Doc.new();rng.seed=2026100617
	for bank:Dictionary in supports:
		var rows:=Bank.sections(bank);var origin:=B.vec(bank.position)
		for i in rows.size()-1:
			cap_triangles.append([origin+rows[i].outer,origin+rows[i].inner,origin+rows[i+1].inner])
			cap_triangles.append([origin+rows[i].outer,origin+rows[i+1].inner,origin+rows[i+1].outer])
		for index in range(1,rows.size()-1,3 if not reference_keys.is_empty() else 2):
			var row:Dictionary=rows[index];var distance:float=row.station
			var mass:float=.5+.5*sin(distance*.69+bank.rock_bank.seed)
			for lane in (5 if not reference_keys.is_empty() else 6):
				if rng.randf()>(.97 if lane<3 else .35+.6*mass):continue
				var near:Dictionary=rows[mini(index+1,rows.size()-1)]
				var t:=rng.randf();var outer:Vector3=row.outer.lerp(near.outer,t);var inner:Vector3=row.inner.lerp(near.inner,t)
				var offset:float=[.43,.98,1.6,2.4,3.7,4.9][lane]+rng.randf_range(-.1,.2)
				var fraction:float=offset/maxf(.01,Vector2(inner.x-outer.x,inner.z-outer.z).length())
				if fraction>.9:continue
				var at:Vector3=origin+outer.lerp(inner,fraction)
				var wild:bool=lane==0 or rng.randf()<.48
				var choice:String=("wild_A" if rng.randf()<.76 else "wild_D") if wild else ["short_A","short_B","short_C"][rng.randi_range(0,2)]
				if rng.randf()<.16:choice="wild_"+["B","C","E","F","G","H"][rng.randi_range(0,5)]
				if not reference_keys.is_empty() and (lane<3 or rng.randf()<.75):
					choice=reference_keys[rng.randi_range(0,reference_keys.size()-1)]
					add_clump(stage,at,choice,rng.randf_range(.88,1.28),bank.uuid)
				else:add_clump(stage,at,choice,rng.randf_range(1.35,1.85) if wild else rng.randf_range(1.15,1.55),bank.uuid)
				if reference_keys.is_empty() and wild and lane<4:
					var base_fraction:float=fraction+.34/maxf(.01,Vector2(inner.x-outer.x,inner.z-outer.z).length())
					if base_fraction<.94:add_clump(stage,origin+outer.lerp(inner,base_fraction),["short_B","short_C"][rng.randi_range(0,1)],rng.randf_range(1.25,1.65),bank.uuid)
		# Small landward groups break up the narrow riverside band near each bridgehead.
		for i in 45:
			var row:Dictionary=rows[rng.randi_range(1,mini(50,rows.size()-2))]
			var fraction:=rng.randf_range(.35,.88)
			var key:String=reference_keys[rng.randi_range(0,reference_keys.size()-1)] if not reference_keys.is_empty() and rng.randf()<.72 else ["short_B","short_C"][rng.randi_range(0,1)]
			add_clump(stage,origin+row.outer.lerp(row.inner,fraction),key,rng.randf_range(.85,1.2),bank.uuid)
	# Continue the planting around the landward bridgehead, outside paved paths.
	var bridge:Dictionary=doc._find("stone_e_0be972769041dbc9")
	var bridge_pose:=Transform3D(Basis(Vector3.UP,deg_to_rad(bridge.rotation[1])),B.vec(bridge.position))
	for end in [-1,1]:
		for side in [-1,1]:
			for i in 24:
				var at:Vector3=bridge_pose*Vector3(end*(28.8+i*.48),0,side*(6.3+rng.randf_range(0,1.3)))
				at.y=surface_height(doc,at)
				var key:String=reference_keys[rng.randi_range(0,reference_keys.size()-1)] if not reference_keys.is_empty() and i<15 else ["short_A","short_B","short_C"][rng.randi_range(0,2)]
				add_clump(stage,at,key,rng.randf_range(.9,1.2),"bridgehead_path")
	check(placements.size()>300,"substantial irregular bank planting")
	check(stage.records.all(func(r):return r.collision=="none"),"grass has no gameplay collision")
	var source_records:Array=doc.records.duplicate(true);var source_meta:Dictionary=doc.map_meta.duplicate(true)
	doc.checkpoint();doc.records.append_array(stage.records)
	var after:Array=doc.records.duplicate(true)
	check(doc.undo() and equivalent(doc.records,source_records),"whole planting undo")
	check(doc.redo() and equivalent(doc.records,after),"whole planting redo")
	check(equivalent(doc.records.slice(0,source_records.size()),source_records) and equivalent(doc.map_meta,source_meta),"all existing terrain buildings bridge and metadata unchanged")
	write_report("plan.json",{"failures":failures,"placements":placements,"records":stage.records,"source_assets":hashes,"formal_sha256":baseline})
	if failures or "--plan-only" in OS.get_cmdline_user_args():quit(failures);return
	# Open the real document for native dependency/path and atomic-save semantics.
	var native=Doc.open_file(FORMAL)
	check(native!=null and FileAccess.get_sha256(FORMAL)==baseline,"source unchanged before candidate save")
	if failures:quit(1);return
	native.checkpoint();native.records.append_array(stage.records)
	check(native.save(TARGET)==OK,"native grass candidate saved")
	var reopened=Doc.open_file(TARGET)
	check(reopened!=null and equivalent(reopened.records,native.records),"grass candidate reopen")
	write_report("result.json",{"failures":failures,"placements":placements,"source_assets":hashes,"formal_sha256":baseline,"candidate_sha256":FileAccess.get_sha256(TARGET)})
	print("BRIDGE_GRASS_COUNT ",placements.size());quit(failures)
