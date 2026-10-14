extends "res://tools/test_world3d_mcp.gd"
## Content placement only: reuse approved native A/C prefabs without rebaking,
## stripping LOD/wind, or claiming that these animated assets use MultiMesh.
const Terrain = preload("res://scripts/world3d/terrain_surface.gd")
const Prefabs = preload("res://scripts/world_editor/prefab_library.gd")
const Materials = preload("res://scripts/world3d/surface_materials.gd")
const Spline = preload("res://scripts/world3d/spline_route.gd")
const ARTIFACTS = "D:/code/rmmo_runtime/review_artifacts/axel_town_terrain_20261014"
const PUBLISHED = "D:/code/rmmo_runtime/review_artifacts/reference_grass_clumps/published.json"
const DEFAULT_MAP = "D:/code/rmmo_runtime/cache/world3d/axel_town_terrain_20261014/map.gltf"
const WIND_MARGIN = .10
const MAIN_COUNT = 260
const S1_COUNT = 30
const S12_COUNT = 24
var map_path := DEFAULT_MAP
var output := ARTIFACTS.path_join("bank_grass")
var recipe: Dictionary
var assets: Dictionary = {}
var terrain_rows: Array = []
var excluded: Array = []
var river: PackedVector2Array = []
var cumulative: Array[float] = [0.0]
var planned: Array = []
var rng := RandomNumberGenerator.new()
var report: Dictionary = {"phase":"preflight", "real_http":true, "images":[], "placements":[], "rejected":{}, "failures":0, "multimesh_claimed":false}
var before_records: Array = []
var before_meta: Dictionary = {}
var main_half_width := 7.0
var main_water_level := 3.0
var stream_water_level := 7.45

func persist() -> void:
	report.failures = failed
	var file := FileAccess.open(output.path_join("bank_grass.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t")); file.close()

func halt() -> bool:
	if failed == 0: return false
	persist()
	if is_instance_valid(editor) and editor._mcp != null: editor._mcp.stop()
	quit(1)
	return true

func vec3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func arr3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func rectangle(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0,z0), Vector2(x1,z0), Vector2(x1,z1), Vector2(x0,z1)])

func strip(a: Vector2, b: Vector2, half_width: float) -> PackedVector2Array:
	var normal := Vector2(-(b-a).y, (b-a).x).normalized()*half_width
	return PackedVector2Array([a+normal, b+normal, b-normal, a-normal])

func height_at(p: Vector2) -> float:
	for row: Dictionary in terrain_rows:
		var local := Vector3(p.x-float(row.position[0]),0,p.y-float(row.position[2]))
		if absf(local.x) <= float(row.size[0])*.5+.00001 and absf(local.z) <= float(row.size[2])*.5+.00001:
			# Terrain.sample already incorporates record.size.y.
			return Terrain.sample(row,local)+float(row.position[1])
	return NAN

func distance_to_path(p: Vector2, path: PackedVector2Array) -> float:
	var best := INF
	for i in range(1,path.size()):
		best = minf(best,p.distance_to(Geometry2D.get_closest_point_to_segment(p,path[i-1],path[i])))
	return best

func along(distance: float) -> Dictionary:
	var d := clampf(distance,0,cumulative.back()-.001)
	for i in range(1,river.size()):
		if cumulative[i] < d: continue
		var direction := (river[i]-river[i-1]).normalized()
		return {"point":river[i-1]+direction*(d-cumulative[i-1]), "normal":Vector2(-direction.y,direction.x)}
	return {}

func nearest_arc(p: Vector2) -> float:
	var best := INF; var result := 0.0
	for i in range(1,river.size()):
		var q := Geometry2D.get_closest_point_to_segment(p,river[i-1],river[i])
		if p.distance_squared_to(q) < best:
			best = p.distance_squared_to(q); result = cumulative[i-1]+river[i-1].distance_to(q)
	return result

func reject(reason: String) -> Dictionary:
	report.rejected[reason] = int(report.rejected.get(reason,0))+1
	return {}

func footprint(center: Vector2, asset: Dictionary, angle: float, scale_: float, margin: float) -> PackedVector2Array:
	var half_x := float(asset.record.bounds_size[0])*scale_*.5+margin
	var half_z := float(asset.record.bounds_size[2])*scale_*.5+margin
	var basis := Basis(Vector3.UP,deg_to_rad(angle))
	var result := PackedVector2Array()
	for offset: Vector2 in rectangle(-half_x,-half_z,half_x,half_z):
		var rotated := basis*Vector3(offset.x,0,offset.y)
		result.append(center+Vector2(rotated.x,rotated.z))
	return result

func candidate(center: Vector2, key: String, angle: float, scale_: float, area: String, group: String, check_spacing: bool = true) -> Dictionary:
	var asset: Dictionary = assets[key]
	var quad := footprint(center,asset,angle,scale_,0)
	var wind_quad := footprint(center,asset,angle,scale_,WIND_MARGIN)
	var water_probes := wind_quad.duplicate()
	water_probes.append(center)
	for i in 4: water_probes.append((wind_quad[i]+wind_quad[(i+1)%4])*.5)
	for p: Vector2 in water_probes:
		if p.x < 0 or p.x > 450 or p.y < 0 or p.y > 360: return reject("outside_town")
		if distance_to_path(p,river) < main_half_width+.2: return reject("main_water")
		if distance_to_path(p,PackedVector2Array([Vector2(337,125.5),Vector2(378,125.5)])) < 2.05: return reject("s12_water_and_round_caps")
	for zone: Dictionary in excluded:
		if not Geometry2D.intersect_polygons(wind_quad,zone.polygon).is_empty(): return reject(str(zone.id))
	if check_spacing:
		for old: Dictionary in planned:
			if center.distance_to(Vector2(old.center[0],old.center[1])) < .83: return reject("clump_spacing")
	var samples: Array[float] = []
	for p: Vector2 in quad: samples.append(height_at(p))
	samples.append(height_at(center))
	for y in samples:
		if not is_finite(y): return reject("no_terrain")
	var low: float = samples.min(); var high: float = samples.max()
	if high-low > .3: return reject("slope_above_0_3m")
	if low <= ((stream_water_level if area == "S12" else main_water_level)+.06): return reject("root_below_dry_bank")
	var basis := Basis(Vector3.UP,deg_to_rad(angle))
	var bounds_center := vec3(asset.record.bounds_position)+vec3(asset.record.bounds_size)*.5
	var horizontal_offset := basis*Vector3(bounds_center.x,0,bounds_center.z)*scale_
	var position := Vector3(center.x-horizontal_offset.x,low-.02-float(asset.record.bounds_position[1])*scale_,center.y-horizontal_offset.z)
	return {"area":area,"group":group,"asset":key,"center":[center.x,center.y],"position":arr3(position),"rotation":[0,angle,0],"size":[scale_,scale_,scale_],"ground_samples":samples,"ground_range":high-low,"root_bury":.02,"wind_margin":WIND_MARGIN}

func append_candidate(center: Vector2, key: String, angle: float, scale_: float, area: String, group: String) -> bool:
	var item := candidate(center,key,angle,scale_,area,group)
	if item.is_empty(): return false
	planned.append(item)
	return true

func glb_metadata(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length()<20: return {}
	if file.get_32()!=0x46546c67 or file.get_32()!=2: file.close(); return {}
	file.get_32()
	var length := file.get_32(); var kind := file.get_32()
	if kind!=0x4e4f534a: file.close(); return {}
	var value: Variant = JSON.parse_string(file.get_buffer(length).get_string_from_utf8()); file.close()
	if not value is Dictionary: return {}
	var rows: Array = []
	for node: Dictionary in value.get("nodes",[]):
		var extra: Dictionary = node.get("extras",{})
		if not extra.has("rmmo_visibility_range"): continue
		rows.append({"name":node.get("name",""),"range":extra.rmmo_visibility_range,"wind":extra.get("rmmo_wind",{}),"collision":extra.get("rmmo_collision",""),"grass":extra.get("rmmo_grass",false)})
	return {"lod_nodes":rows,"lod_count":rows.size(),"wind_node_count":rows.filter(func(r):return not r.wind.is_empty()).size()}

func load_assets() -> void:
	var published: Variant = JSON.parse_string(FileAccess.get_file_as_string(PUBLISHED))
	check(published is Dictionary,"approved grass publication manifest available")
	if not published is Dictionary: return
	for entry: Dictionary in published.entries:
		if not entry.id in ["arch_A","arch_C"]: continue
		var loaded: Dictionary = Prefabs.read(entry.entry)
		check(loaded.get("ok",false) and loaded.get("records",[]).size()==1,"native single-clump prefab "+entry.id)
		if not loaded.get("ok",false) or loaded.records.size()!=1: continue
		var record: Dictionary = loaded.records[0]
		var sha := FileAccess.get_sha256(record.asset_path)
		var metadata := glb_metadata(record.asset_path)
		check(sha==entry.library_model_sha256,"approved GLB SHA "+entry.id)
		check(record.get("collision") == "none","no collision "+entry.id)
		check(metadata.get("lod_count")==3 and metadata.get("wind_node_count")==2,"three authored LODs and two wind-responsive LODs "+entry.id)
		if metadata.get("lod_count")==3:
			check(metadata.lod_nodes.all(func(r):return r.collision=="none" and r.grass),"all LODs retain grass/no-collision semantics "+entry.id)
		assets[entry.id] = {"asset_id":entry.entry.prefab_path,"record":record,"sha256":sha,"metadata":metadata}
	check(assets.size()==2,"A and C assets resolved")
	report.assets=assets.duplicate(true)

func prepare_document(doc) -> void:
	before_records=doc.records.duplicate(true); before_meta=doc.map_meta.duplicate(true)
	terrain_rows=doc.records.filter(func(r):return r.has("terrain_mesh"))
	check(not terrain_rows.is_empty(),"native terrain records present")
	for row: Dictionary in terrain_rows:
		check(vec3(row.rotation).is_zero_approx(),"axis-aligned terrain "+str(row.uuid))
	var main: Dictionary = {}; var shallow: Dictionary = {}
	for layer: Dictionary in doc.map_meta.get("terrain_rivers",[]):
		if layer.id == "axel_main_river": main=layer.request
		if layer.id == "axel_s12_stream": shallow=layer.request
	check(not main.is_empty(),"native main river metadata available")
	check(equivalent(main.get("points",[]),recipe.main_river.points) and is_equal_approx(float(main.get("width",0)),14) and is_equal_approx(float(main.get("water_level",0)),3),"latest recipe matches native main path, width 14 m and water +3 m")
	check(equivalent(shallow.get("points",[]),[[337,125.5],[378,125.5]]) and is_equal_approx(float(shallow.get("width",0)),3.6),"S12 geometry still matches its two reserved paths and round-cap finish")
	if main.is_empty() or shallow.is_empty(): return
	main_half_width=float(main.width)*.5; main_water_level=float(main.water_level); stream_water_level=float(shallow.water_level)
	# Use the same sampler and current native request as the river tool. Recipe
	# samples are never silently reused after a native river reroute.
	var sampled: Dictionary=Spline.sample(main.points,2.0,false,.5 if main.get("curved",true) else 0.0)
	check(sampled.get("ok",false),"current native river sampled by shared spline business code")
	if not sampled.get("ok",false): return
	for p: Array in sampled.points: river.append(Vector2(p[0],p[1]))
	report.rivers={"main":main.duplicate(true),"s12":shallow.duplicate(true),"main_sample_count":river.size()}
	for i in range(1,river.size()): cumulative.append(cumulative.back()+river[i-1].distance_to(river[i]))
	var reserve_count := 0
	for zone: Dictionary in doc.map_meta.get("editor_layout",{}).get("zones",[]):
		if not str(zone.id) in ["R1","R2","R3","R4","R5"]: continue
		var poly := PackedVector2Array()
		for p: Array in zone.polygon: poly.append(Vector2(p[0],p[1]))
		excluded.append({"id":zone.id,"polygon":poly}); reserve_count+=1
	check(reserve_count==5,"all five reserved zones explicitly excluded")
	for i in recipe.report.bridges.size():
		var ends: Array = recipe.report.bridges[i].ends
		var a := Vector2(ends[0][0],ends[0][1]); var b := Vector2(ends[1][0],ends[1][1])
		var direction := (b-a).normalized()
		excluded.append({"id":"bridge_%d_8m_approaches"%(i+1),"polygon":strip(a-direction*8,b+direction*8,2.75)})
	excluded.append({"id":"S12_north_2m_path","polygon":rectangle(329,120.5,379,122.5)})
	excluded.append({"id":"S12_south_2m_path","polygon":rectangle(329,128.5,379,130.5)})
	excluded.append({"id":"spawn_guild_plaza","polygon":rectangle(142,198,180,237)})
	for item: Dictionary in doc.records:
		for asset: Dictionary in assets.values():
			if str(item.get("asset_path",""))==str(asset.record.asset_path): check(false,"refuse duplicate placement: approved A/C already present")
	report.exclusions=[]
	for zone: Dictionary in excluded:
		var points: Array=[]
		for p: Vector2 in zone.polygon: points.append([p.x,p.y])
		report.exclusions.append({"id":zone.id,"polygon":points})

func plan_grass() -> void:
	rng.seed=20261014031
	var s1_arc := nearest_arc(Vector2(285,245.5))
	var count := 0
	for attempt in 10000:
		if count==S1_COUNT: break
		var side := -1 if attempt%2==0 else 1
		var band := along(s1_arc+rng.randf_range(-19,19))
		var center: Vector2 = band.point+band.normal*float(side)*rng.randf_range(9.8,12)
		if append_candidate(center,"arch_A" if rng.randf()<.65 else "arch_C",rng.randf_range(-180,180),rng.randf_range(.75,1.05),"S1","bridge3_%d"%side): count+=1
	check(count==S1_COUNT,"precompute 30 S1 focus clumps")
	count=0
	for attempt in 10000:
		if count==S12_COUNT: break
		var group := attempt%3
		var center := Vector2([344.0,355.5,373.0][group]+rng.randf_range(-3,3),[123.03,127.97,119.30,131.70][attempt%4]+rng.randf_range(-.045,.045))
		# Keep the known future south-east S12 cottage footprint free too.
		if center.x>364 and center.y>130.5: continue
		if append_candidate(center,"arch_C",rng.randf_range(-8,8),rng.randf_range(.75,.82),"S12","s12_%d"%group): count+=1
	check(count==S12_COUNT,"precompute 24 low C clumps around S12 without touching its paths")
	var groups: Array=[]
	for side in [-1,1]:
		var d := 43.0+rng.randf_range(0,6)
		while d<cumulative.back()-43:
			var band := along(d)
			if band.point.y>8 and band.point.y<352:
				groups.append({"arc":d,"side":side,"rank":rng.randf(),"count":rng.randi_range(6,9)})
			d+=rng.randf_range(18,23)
	groups.sort_custom(func(a,b):return a.rank<b.rank)
	count=0
	for index in groups.size():
		if count>=MAIN_COUNT: break
		var group: Dictionary = groups[index]; var accepted := 0
		for attempt in 100:
			if count>=MAIN_COUNT or accepted>=int(group.count): break
			var band := along(float(group.arc)+rng.randf_range(-4.8,4.8))
			var center: Vector2 = band.point+band.normal*float(group.side)*rng.randf_range(9.8,12)
			if append_candidate(center,"arch_A" if rng.randf()<.48 else "arch_C",rng.randf_range(-180,180),rng.randf_range(.75,1.05),"main","bank_group_%02d"%index): count+=1; accepted+=1
	check(count>=240 and count<=280,"precompute 240–280 grouped main-bank clumps: "+str(count))
	check(planned.size()<=340,"total native clump count <= 340: "+str(planned.size()))
	report.seed=20261014031
	report.counts={"main":count,"S1":planned.filter(func(p):return p.area=="S1").size(),"S12":planned.filter(func(p):return p.area=="S12").size(),"total":planned.size()}
	report.precomputed=planned.duplicate(true)
	report.notes=["Existing approved A/C GLBs remain untouched; no new models or model export.","Each clump uses native place_asset and set_object_transform transactions over real HTTP.","No MultiMesh claim: authored three-level visibility and wind metadata remain on imported models.","Four footprint corners plus centre sampled on actual native terrain; root base is minimum minus 0.02 m.","This placement audit does not rerun interiors or whole-town performance, and screenshots require separate visual review."]

func wait_view() -> void:
	var deadline := Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if editor._load_job!=null and editor._load_job.active: continue
		if editor._ground_batches.stats().get("pending_groups",0)>0: continue
		await settle(); return
	check(false,"native editor geometry ready")

func audit_scene() -> void:
	var ids: Dictionary={}; var lods := 0; var winds := 0; var maximum := 0.0
	for placement: Dictionary in report.placements:
		ids[placement.id]=true
		var record: Dictionary=editor._doc._find(placement.id)
		check(not record.is_empty(),"saved clump exists "+str(placement.id))
		if record.is_empty(): continue
		var asset: Dictionary=assets[placement.asset]
		check(record.get("collision")=="none" and record.get("asset_path")==asset.record.asset_path,"unchanged asset and collision "+str(placement.id))
		check(equivalent(record.position,placement.position) and equivalent(record.rotation,placement.rotation) and equivalent(record.size,placement.size),"saved native matrix "+str(placement.id))
		var valid:=candidate(Vector2(placement.center[0],placement.center[1]),placement.asset,float(record.rotation[1]),float(record.size[0]),placement.area,placement.group,false)
		check(not valid.is_empty(),"ground, water and passage clearance "+str(placement.id))
		if not valid.is_empty(): maximum=maxf(maximum,float(valid.ground_range))
		var holder: Node=editor._view.get_node_or_null(NodePath(str(placement.id)))
		check(holder!=null,"native visual exists "+str(placement.id))
		if holder==null: continue
		var local_lods := 0; var local_winds := 0
		for mesh: MeshInstance3D in Materials.meshes(holder):
			var extra: Dictionary=mesh.get_meta("extras",{})
			if extra.has("rmmo_visibility_range"):
				local_lods+=1
				check(is_equal_approx(mesh.visibility_range_begin,float(extra.rmmo_visibility_range.begin)) and is_equal_approx(mesh.visibility_range_end,float(extra.rmmo_visibility_range.end)),"native LOD range applied "+str(placement.id))
			if extra.has("rmmo_wind"): local_winds+=1
		check(local_lods==3 and local_winds==2,"imported three LOD/two wind metadata "+str(placement.id))
		lods+=local_lods; winds+=local_winds
	var retained: Array=editor._doc.records.filter(func(r):return not ids.has(str(r.uuid)))
	check(equivalent(retained,before_records),"all pre-existing terrain/water records unchanged")
	check(equivalent(editor._doc.map_meta,before_meta),"map metadata, reserves and river ownership unchanged")
	report.native_metadata={"clumps":ids.size(),"lod_nodes":lods,"wind_nodes":winds,"max_ground_range_m":maximum,"collision":"none","shared_static_batches":editor._ground_batches.stats()}

func capture(label: String, camera: Dictionary) -> void:
	await call_tool("select_objects",{"ids":[]})
	await call_tool("set_editor_camera",camera)
	editor._grid.visible=false
	editor._authoring.marker.visible=false
	# Editor-only scene: no player is spawned or deleted; collision is untouched.
	# The camera's SubViewport excludes editor panels and planning overlay UI.
	await settle()
	for i in 18: await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image=editor._camera.get_viewport().get_texture().get_image()
	var path:=output.path_join(label+".webp")
	check(picture.save_webp(path,true,.94)==OK,"clean WebP capture "+label)
	report.images.append({"path":path,"sha256":FileAccess.get_sha256(path),"size":[picture.get_width(),picture.get_height()],"camera":camera,"character_spawned":false})

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="): map_path=arg.trim_prefix("--map=").replace("\\","/")
		elif arg.begins_with("--out="): output=arg.trim_prefix("--out=").replace("\\","/")
	check(DirAccess.make_dir_recursive_absolute(output)==OK,"report directory available")
	report.map=map_path; report.started_utc=Time.get_datetime_string_from_system(true)
	report.map_sha256_before=FileAccess.get_sha256(map_path)
	check(not str(report.map_sha256_before).is_empty(),"target map exists")
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(ARTIFACTS.path_join("recipe.json")))
	check(value is Dictionary,"terrain recipe readable")
	if halt(): return
	recipe=value
	load_assets()
	if halt(): return
	var doc=Doc.open_file(map_path)
	check(doc!=null,"native map opened for placement preflight")
	if halt(): return
	prepare_document(doc)
	if halt(): return
	plan_grass(); persist()
	if halt(): return
	if "--preflight-only" in OS.get_cmdline_user_args():
		report.phase="preflight_complete";persist()
		print("AXEL_BANK_GRASS_PREFLIGHT ",JSON.stringify(report.counts))
		quit(0)
		return
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false
	editor._draft_directory=map_path.get_base_dir().path_join("bank_grass_drafts")
	root.add_child(editor); await settle(); await wait_view()
	check(equivalent(editor._doc.records,before_records) and equivalent(editor._doc.map_meta,before_meta),"editor opened identical preflight content")
	check(FileAccess.get_sha256(map_path)==report.map_sha256_before,"map did not change during preflight")
	if halt(): return
	var probe:=TCPServer.new(); port=31370
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"3D HTTP MCP on loopback")
	rpc_timeout_ms=180000
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var discovery:=await rpc("tools/list")
	var names: Array=discovery.get("result",{}).get("tools",[]).map(func(t):return t.name)
	check(names.has("place_asset") and names.has("set_object_transform") and names.has("save_world") and names.has("open_world"),"required native business tools discovered")
	var library:=await call_tool("list_assets",{"query":"宽弧桥头草堆"})
	var available: Array=library.get("assets",[]).map(func(a):return a.asset_id)
	for asset: Dictionary in assets.values(): check(available.has(asset.asset_id),"approved prefab discoverable "+str(asset.asset_id))
	await call_tool("configure_transform",{"gravity_placement":false})
	if halt(): return
	report.phase="placing"
	for item: Dictionary in planned:
		var result:=await call_tool("place_asset",{"asset_id":assets[item.asset].asset_id,"position":item.position})
		check(result.get("ids",[]).size()==1,"one editable clump per prefab placement")
		if halt(): return
		var id:=str(result.ids[0])
		await call_tool("set_object_transform",{"id":id,"position":item.position,"rotation":item.rotation,"size":item.size})
		if halt(): return
		var row: Dictionary=item.duplicate(true); row.id=id
		var basis:=Basis.from_euler(vec3(row.rotation)*PI/180.0).scaled(vec3(row.size))
		row.matrix={"basis_x":arr3(basis.x),"basis_y":arr3(basis.y),"basis_z":arr3(basis.z),"origin":row.position}
		report.placements.append(row)
		if report.placements.size()%24==0: persist()
	await call_tool("select_objects",{"ids":[]}); await wait_view()
	audit_scene()
	if halt(): return
	report.phase="saving"
	await call_tool("save_world")
	if halt(): return
	var saved_records: Array=editor._doc.records.duplicate(true)
	var saved_meta: Dictionary=editor._doc.map_meta.duplicate(true)
	report.map_sha256_saved=FileAccess.get_sha256(map_path)
	await call_tool("open_world",{"path":map_path}); await wait_view()
	check(equivalent(editor._doc.records,saved_records) and equivalent(editor._doc.map_meta,saved_meta),"native save/reopen content identical (excluding disk bookkeeping)")
	audit_scene()
	for asset: Dictionary in assets.values(): check(FileAccess.get_sha256(asset.record.asset_path)==asset.sha256,"approved GLB unchanged after save/reopen")
	if halt(): return
	report.phase="capturing"
	var focus: Dictionary=planned.filter(func(p):return p.area=="S1")[0]
	await capture("s1_bank_grass_close",{"projection":"perspective","center":[focus.center[0],float(focus.position[1])+.2,focus.center[1]],"distance":11,"yaw":-42,"pitch":-23})
	await capture("s12_bank_grass_close",{"projection":"perspective","center":[354.5,7.7,125.5],"distance":13,"yaw":-72,"pitch":-24})
	report.map_sha256_after=FileAccess.get_sha256(map_path)
	check(report.map_sha256_saved==report.map_sha256_after,"screenshots do not change saved map")
	report.phase="complete" if failed==0 else "failed"
	report.visual_review="pending: inspect the two WebP images before declaring appearance accepted"
	persist()
	editor._mcp.stop(); editor.queue_free(); await settle()
	quit(1 if failed else 0)
