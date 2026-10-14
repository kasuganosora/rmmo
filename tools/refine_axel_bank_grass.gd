extends "res://tools/place_axel_bank_grass.gd"
## Transform-only refinement of the 314 previously published grass instances.
## GPU runs are coordinated by the caller through run_godot_background.py.
const FORMAL = "D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const MICRO_BURY = .012
var source_report := ARTIFACTS.path_join("bank_grass/bank_grass.json")
var original: Dictionary = {}
var proposed: Array = []
var expected_meta: Dictionary = {}
var ids: Dictionary = {}

func persist() -> void:
	report.failures=failed
	var file:=FileAccess.open(output.path_join("refinement.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"\t")); file.close()

func root_center_local(record: Dictionary) -> Vector3:
	var lower:=vec3(record.bounds_position); var extent:=vec3(record.bounds_size)
	return lower+Vector3(extent.x*.5,0,extent.z*.5)

func aligned_basis(normal: Vector3, yaw: float) -> Basis:
	var heading:=Basis(Vector3.UP,deg_to_rad(yaw)).z
	var forward:=(heading-normal*heading.dot(normal)).normalized()
	return Basis(normal.cross(forward).normalized(),normal,forward)

func fitted_plane(center: Vector2, basis: Basis, record: Dictionary, scale_: float) -> Dictionary:
	var hx:=float(record.bounds_size[0])*scale_*.5
	var hz:=float(record.bounds_size[2])*scale_*.5
	var xx:=0.0; var zz:=0.0; var xz:=0.0; var xy:=0.0; var zy:=0.0; var mean:=0.0
	var rows: Array=[]
	for iz in [-1,0,1]:
		for ix in [-1,0,1]:
			var offset:=basis*Vector3(ix*hx,0,iz*hz)
			var height:=height_at(center+Vector2(offset.x,offset.z))
			if not is_finite(height): return {"ok":false,"reason":"missing_terrain"}
			rows.append([offset.x,offset.z,height]); mean+=height
	mean/=9.0
	for row: Array in rows:
		xx+=row[0]*row[0]; zz+=row[1]*row[1]; xz+=row[0]*row[1]
		xy+=row[0]*(row[2]-mean); zy+=row[1]*(row[2]-mean)
	var determinant:=xx*zz-xz*xz
	if determinant<.000001: return {"ok":false,"reason":"degenerate_fit"}
	var a: float=(xy*zz-zy*xz)/determinant
	var b: float=(zy*xx-xy*xz)/determinant
	return {"ok":true,"height":mean,"normal":Vector3(-a,1,-b).normalized(),"slope_x":a,"slope_z":b}

func transformed_footprint(record: Dictionary) -> PackedVector2Array:
	var points:=PackedVector2Array()
	for p: Vector3 in Geometry.corners(record): points.append(Vector2(p.x,p.z))
	var hull:=Geometry2D.convex_hull(points)
	if hull.size()>1 and hull[0].is_equal_approx(hull[-1]): hull.resize(hull.size()-1)
	var offset: Array[PackedVector2Array]=Geometry2D.offset_polygon(hull,WIND_MARGIN)
	return offset[0] if offset.size()==1 else PackedVector2Array()

func clearance(record: Dictionary, area: String) -> String:
	var polygon:=transformed_footprint(record)
	if polygon.size()<3: return "invalid_3d_projected_footprint"
	for zone: Dictionary in excluded:
		if not Geometry2D.intersect_polygons(polygon,zone.polygon).is_empty(): return str(zone.id)
	var probes:=polygon.duplicate()
	for i in polygon.size(): probes.append((polygon[i]+polygon[(i+1)%polygon.size()])*.5)
	for point: Vector2 in probes:
		if point.x<0 or point.x>450 or point.y<0 or point.y>360: return "outside_town"
		if distance_to_path(point,river)<main_half_width+.2: return "main_water"
		if distance_to_path(point,PackedVector2Array([Vector2(337,125.5),Vector2(378,125.5)]))<2.05: return "s12_water"
	var water: float=stream_water_level if area=="S12" else main_water_level
	for point: Vector3 in Geometry.corners(record):
		if point.y<=water+.025: return "root_near_water"
	return ""

func surface_gaps(record: Dictionary, grid: int = 4) -> Dictionary:
	var transform:=Transform3D(Basis.from_euler(vec3(record.rotation)*PI/180.0).scaled(vec3(record.size)),vec3(record.position))
	var lower:=vec3(record.bounds_position); var extent:=vec3(record.bounds_size)
	var gaps: Array[float]=[]
	for iz in grid+1:
		for ix in grid+1:
			var point:=transform*(lower+Vector3(extent.x*ix/float(grid),0,extent.z*iz/float(grid)))
			var height:=height_at(Vector2(point.x,point.z))
			if not is_finite(height): return {"ok":false}
			gaps.append(point.y-height)
	return {"ok":true,"min":gaps.min(),"max":gaps.max(),"samples":gaps}

func fitted_transform(old: Dictionary, entry: Dictionary, scale_: float, yaw: float) -> Dictionary:
	var center:=Vector2(entry.center[0],entry.center[1])
	var basis:=Basis(Vector3.UP,deg_to_rad(yaw)); var fit: Dictionary={}
	for iteration in 3:
		fit=fitted_plane(center,basis,old,scale_)
		if not fit.ok: return fit
		basis=aligned_basis(fit.normal,yaw)
	var tilt:=rad_to_deg(acos(clampf(basis.y.y,-1,1)))
	if tilt>35: return {"ok":false,"reason":"slope_above_35deg"}
	var updated:=old.duplicate(true)
	updated.rotation=arr3(basis.get_euler()*180.0/PI)
	updated.size=[scale_,scale_,scale_]
	updated.position=arr3(Vector3(center.x,fit.height,center.y)-basis*(root_center_local(old)*scale_))
	# Lower only enough to cover the fitted plane's curvature residual. Linear
	# slope no longer buries the uphill half of an otherwise upright clump.
	var fit_gaps:=surface_gaps(updated)
	if not fit_gaps.ok: return {"ok":false,"reason":"missing_root_support"}
	updated.position[1]-=float(fit_gaps.max)+MICRO_BURY
	var gaps:=surface_gaps(updated)
	var buried: float=-float(gaps.min)
	if buried>.12: return {"ok":false,"reason":"curvature_bury_above_12cm","buried":buried}
	var issue:=clearance(updated,entry.area)
	if not issue.is_empty(): return {"ok":false,"reason":issue}
	return {"ok":true,"record":updated,"normal":arr3(basis.y),"tilt_deg":tilt,"max_bury_m":buried,"highest_root_gap_m":gaps.max,"root_gaps":gaps.samples,"scale":scale_}

func prepare_refinement(doc) -> void:
	before_records=doc.records.duplicate(true); before_meta=doc.map_meta.duplicate(true)
	terrain_rows=doc.records.filter(func(r):return r.has("terrain_mesh"))
	for layer: Dictionary in doc.map_meta.get("terrain_rivers",[]):
		if layer.id=="axel_main_river":
			main_half_width=float(layer.request.width)*.5; main_water_level=float(layer.request.water_level)
			var sampled: Dictionary=Spline.sample(layer.request.points,2.0,false,.5 if layer.request.get("curved",true) else 0.0)
			check(sampled.get("ok",false),"sample actual native main river")
			for p: Array in sampled.get("points",[]): river.append(Vector2(p[0],p[1]))
		elif layer.id=="axel_s12_stream":
			stream_water_level=float(layer.request.water_level)
			check(equivalent(layer.request.points,[[337,125.5],[378,125.5]]),"S12 path remains valid for authored path exclusions")
	check(river.size()>2 and is_equal_approx(main_half_width,7),"current main river found with 14 m width")
	for item: Dictionary in original.exclusions:
		if str(item.id) in ["R1","R2","R3","R4","R5"]: continue
		var polygon:=PackedVector2Array()
		for point: Array in item.polygon: polygon.append(Vector2(point[0],point[1]))
		excluded.append({"id":item.id,"polygon":polygon})
	var reserves:=0
	for zone: Dictionary in doc.map_meta.get("editor_layout",{}).get("zones",[]):
		if not str(zone.id) in ["R1","R2","R3","R4","R5"]: continue
		var polygon:=PackedVector2Array()
		for point: Array in zone.polygon: polygon.append(Vector2(point[0],point[1]))
		excluded.append({"id":zone.id,"polygon":polygon}); reserves+=1
	check(reserves==5,"all current reserved zones protected")
	expected_meta=before_meta.duplicate(true)
	var reference: Dictionary=expected_meta.get("town_reference",{}).duplicate(true)
	reference.phase="terrain_and_bank_grass"
	reference.design_note=str(reference.get("design_note","")).replace("建筑、道路、桥梁、城门与植被留待地形后布置。","建筑、道路、桥梁与城门留待后续布置；本轮已铺岸边草堆。")
	expected_meta.town_reference=reference
	report.allowed_metadata_changes={"town_reference.phase":reference.phase,"town_reference.design_note":reference.design_note}
	var old_bury: Array[float]=[]; var new_bury: Array[float]=[]
	var enlarged:=0; var kept_scale:=0
	for entry: Dictionary in original.placements:
		var id:=str(entry.id); var old: Dictionary=doc._find(id)
		check(not old.is_empty() and not ids.has(id),"existing unique grass ID "+id)
		if old.is_empty(): continue
		ids[id]=true
		check(old.get("asset_path")==assets[entry.asset].record.asset_path and old.get("collision")=="none","approved existing A/C clump "+id)
		check(equivalent(old.position,entry.position) and equivalent(old.rotation,entry.rotation) and equivalent(old.size,entry.size),"original placement has not been edited "+id)
		var old_scale:=float(old.size[0]); var yaw:=float(old.rotation[1])
		var unit:=float(absi(id.hash())%1000)/999.0
		var target: float=(1.08+.07*unit) if entry.asset=="arch_A" else (1.0+.07*unit)
		if entry.area=="S12": target=1.0
		target=maxf(target,old_scale)
		var trials: Array=[target,maxf(old_scale,(target+old_scale)*.5),old_scale]
		var selected: Dictionary={}; var rejected: Array=[]
		for factor: float in trials:
			var fit:=fitted_transform(old,entry,factor,yaw)
			if fit.ok: selected=fit; break
			rejected.append({"scale":factor,"reason":fit.get("reason","unknown")})
		if selected.is_empty():
			# The original size is mandatory near narrow paths; a modest yaw change
			# can accommodate the tilted crown without moving its root centre.
			for delta in [-12.0,12.0,-24.0,24.0]:
				var fit:=fitted_transform(old,entry,old_scale,yaw+delta)
				if fit.ok: selected=fit; break
		check(not selected.is_empty(),"safe slope-aligned transform "+id)
		if selected.is_empty(): report.unresolved.append({"id":id,"trials":rejected}); continue
		var previous:=surface_gaps(old)
		old_bury.append(-float(previous.min)); new_bury.append(float(selected.max_bury_m))
		if float(selected.scale)>old_scale+.001: enlarged+=1
		else: kept_scale+=1
		var row: Dictionary=entry.duplicate(true)
		row.before={"position":old.position.duplicate(),"rotation":old.rotation.duplicate(),"size":old.size.duplicate(),"max_bury_m":-float(previous.min)}
		for field in ["position","rotation","size"]: row[field]=selected.record[field].duplicate()
		row.fit={"normal":selected.normal,"tilt_deg":selected.tilt_deg,"max_bury_m":selected.max_bury_m,"highest_root_gap_m":selected.highest_root_gap_m,"samples":selected.root_gaps}
		row.trials_rejected=rejected
		var basis:=Basis.from_euler(vec3(row.rotation)*PI/180.0).scaled(vec3(row.size))
		row.matrix={"basis_x":arr3(basis.x),"basis_y":arr3(basis.y),"basis_z":arr3(basis.z),"origin":row.position}
		proposed.append(row)
	check(ids.size()==314 and proposed.size()==314,"all 314 existing grass instances refined; no additions")
	old_bury.sort(); new_bury.sort()
	report.summary={"count":proposed.size(),"enlarged":enlarged,"original_scale_retained":kept_scale,"before_bury":distribution(old_bury),"after_bury":distribution(new_bury)}
	report.proposed=proposed

func distribution(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted:=values.duplicate(); sorted.sort(); var total:=0.0
	for value in sorted: total+=value
	return {"mean":total/values.size(),"median":sorted[sorted.size()/2],"max":sorted.back(),"min":sorted.front()}

func audit_refinement() -> void:
	var actual_expected: Array=before_records.duplicate(true)
	var lods:=0; var winds:=0
	for entry: Dictionary in proposed:
		var actual: Dictionary=editor._doc._find(entry.id)
		check(not actual.is_empty(),"refined ID preserved "+str(entry.id))
		if actual.is_empty(): continue
		for row: Dictionary in actual_expected:
			if row.uuid==entry.id:
				for field in ["position","rotation","size"]: row[field]=entry[field].duplicate()
		check(clearance(actual,entry.area).is_empty(),"tilted crown and wind clear water and protected paths "+str(entry.id))
		var gaps:=surface_gaps(actual)
		check(gaps.ok and float(gaps.max)<=.002 and float(gaps.min)>=-.1201,"roots supported with bounded curvature embedding "+str(entry.id))
		var holder: Node=editor._view.get_node_or_null(NodePath(str(entry.id)))
		check(holder!=null,"native visual preserved "+str(entry.id))
		if holder==null: continue
		var local_lods:=0; var local_winds:=0
		for mesh: MeshInstance3D in Materials.meshes(holder):
			var extra: Dictionary=mesh.get_meta("extras",{})
			if extra.has("rmmo_visibility_range"):
				local_lods+=1
				check(is_equal_approx(mesh.visibility_range_begin,float(extra.rmmo_visibility_range.begin)) and is_equal_approx(mesh.visibility_range_end,float(extra.rmmo_visibility_range.end)),"authored LOD range active "+str(entry.id))
			if extra.has("rmmo_wind"): local_winds+=1
		check(local_lods==3 and local_winds==2,"three LOD/two wind nodes retained "+str(entry.id))
		lods+=local_lods; winds+=local_winds
	check(equivalent(editor._doc.records,actual_expected),"only the existing 314 transforms changed; assets/terrain/materials/collision identical")
	check(equivalent(editor._doc.map_meta,expected_meta),"metadata changes restricted to declared town_reference phase/design note")
	report.native_metadata={"lod_nodes":lods,"wind_nodes":winds,"clumps":proposed.size(),"collision":"none","multimesh_claimed":false}

func measured_capture(label: String, camera: Dictionary) -> void:
	await call_tool("select_objects",{"ids":[]}); await call_tool("set_editor_camera",camera)
	editor._grid.visible=false; editor._authoring.marker.visible=false
	var viewport: Viewport=editor._camera.get_viewport(); var rid:=viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	for frame in 36: await process_frame
	var cpu: Array[float]=[]; var gpu: Array[float]=[]; var calls: Array[float]=[]; var objects: Array[float]=[]
	for frame in 30:
		await process_frame; await RenderingServer.frame_post_draw
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		calls.append(float(RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)))
		objects.append(float(RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)))
	var image_: Image=viewport.get_texture().get_image()
	var path:=output.path_join(label+".webp")
	check(image_.save_webp(path,true,.94)==OK,"direct clean WebP "+label)
	RenderingServer.viewport_set_measure_render_time(rid,false)
	report.images.append({"path":path,"sha256":FileAccess.get_sha256(path),"camera":camera,"size":[image_.get_width(),image_.get_height()],"character_spawned":false})
	report.fixed_view_metrics.append({"label":label,"scope":"30 stable rendered frames of this editor camera only; not whole-town performance","cpu_ms":distribution(cpu),"gpu_ms":distribution(gpu),"draw_calls":distribution(calls),"objects":distribution(objects),"gpu_timing_available":gpu.max()>0,"cpu_timing_available":cpu.max()>0})

func run() -> void:
	map_path=FORMAL; output=ARTIFACTS.path_join("bank_grass_refined")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="): map_path=arg.trim_prefix("--map=").replace("\\","/")
		elif arg.begins_with("--out="): output=arg.trim_prefix("--out=").replace("\\","/")
		elif arg.begins_with("--source="): source_report=arg.trim_prefix("--source=").replace("\\","/")
	report={"phase":"preflight","map":map_path,"source_report":source_report,"real_http":true,"images":[],"fixed_view_metrics":[],"unresolved":[],"failures":0,"notes":["Only existing grass transforms change; approved models, LODs, wind and ground material are reused unchanged.","Root plane is least-squares fitted to 3x3 native terrain samples; 5x5 root probes determine small curvature-residual embedding.","Tilted full crown projection plus 0.1m wind margin is checked against water, bridge approaches, R1–R5, S12 paths and spawn square.","Appearance remains pending visual review of the final WebP images."]}
	check(Paths.allowed(output) and DirAccess.make_dir_recursive_absolute(output)==OK,"review output available")
	check(Paths.allowed(map_path) and FileAccess.file_exists(map_path),"existing target map available")
	var loaded: Variant=JSON.parse_string(FileAccess.get_file_as_string(source_report))
	check(loaded is Dictionary and loaded.get("placements",[]).size()==314,"published report describes exactly 314 clumps")
	if halt(): return
	original=loaded; report.map_sha256_before=FileAccess.get_sha256(map_path)
	load_assets()
	var doc=Doc.open_file(map_path)
	check(doc!=null,"native map open for read-only fit preflight")
	if halt(): return
	prepare_refinement(doc); persist()
	if halt(): return
	if "--preflight-only" in OS.get_cmdline_user_args():
		report.phase="preflight_complete"; persist(); print("AXEL_GRASS_REFINE_PREFLIGHT ",JSON.stringify(report.summary)); quit(0); return
	check(DisplayServer.get_name()!="headless","GPU execution requires background renderer")
	if halt(): return
	Engine.max_fps=60; root.size=Vector2i(1600,1000); root.content_scale_size=root.size
	rpc_timeout_ms=180000
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=map_path.get_base_dir().path_join("bank_grass_refine_drafts")
	root.add_child(editor); await settle(); await wait_view()
	check(equivalent(editor._doc.records,before_records) and equivalent(editor._doc.map_meta,before_meta) and FileAccess.get_sha256(map_path)==report.map_sha256_before,"editor opened unchanged preflight map")
	if halt(): return
	var probe:=TCPServer.new(); port=31430
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"native 3D HTTP MCP available")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	await call_tool("configure_transform",{"gravity_placement":false})
	if halt(): return
	report.phase="transforming"
	for entry: Dictionary in proposed:
		await call_tool("set_object_transform",{"id":entry.id,"position":entry.position,"rotation":entry.rotation,"size":entry.size})
		if halt(): return
	# Content provenance has no generic MCP setter; use the document's native
	# recovery transaction, then the ordinary editor commit/save operations.
	editor._doc.checkpoint_recovery(); editor._doc.map_meta=expected_meta.duplicate(true); editor._commit_records([])
	await call_tool("select_objects",{"ids":[]}); await wait_view(); audit_refinement()
	if halt(): return
	await call_tool("save_world")
	if halt(): return
	var saved_records: Array=editor._doc.records.duplicate(true); var saved_meta: Dictionary=editor._doc.map_meta.duplicate(true)
	await call_tool("open_world",{"path":map_path}); await wait_view()
	check(equivalent(editor._doc.records,saved_records) and equivalent(editor._doc.map_meta,saved_meta),"native save/reopen identical")
	audit_refinement()
	for asset: Dictionary in assets.values(): check(FileAccess.get_sha256(asset.record.asset_path)==asset.sha256,"approved source GLB unchanged")
	if halt(): return
	report.map_sha256_after=FileAccess.get_sha256(map_path); report.phase="capturing"
	var focus: Dictionary={}
	for entry: Dictionary in proposed:
		if entry.area=="S1" and entry.asset=="arch_A": focus=entry; break
	await measured_capture("s1_grass_root_close",{"projection":"perspective","center":[focus.center[0],height_at(Vector2(focus.center[0],focus.center[1]))+.2,focus.center[1]],"distance":5.5,"yaw":-42,"pitch":-18})
	await measured_capture("main_river_grass_medium",{"projection":"perspective","center":[305.5,4.0,240],"distance":18,"yaw":-42,"pitch":-23})
	check(FileAccess.get_sha256(map_path)==report.map_sha256_after,"capture and timing did not alter the map")
	report.phase="complete" if failed==0 else "failed"; report.visual_review="pending"
	persist(); editor._mcp.stop(); editor.queue_free(); await settle(); quit(1 if failed else 0)
