extends "res://tools/build_medieval_material_demo.gd"
const RoofPlan=preload("res://scripts/world3d/roof_plan.gd")
const RoofMesh=preload("res://scripts/world3d/roof_mesh.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")

func paint_world() -> Array:
	# Offline fixture authoring: validate each generated paint record and mesh,
	# then replace the fixture in one recovery transaction. Calling UI refresh
	# for each of 6,000 components needlessly rebuilds the object list each time.
	# The actual HTTP paint/undo/protection path is exercised separately below.
	var doc=editor._doc; var before: Array=doc.records.duplicate(true); var next: Array=before.duplicate(true); var count:=0
	for record in next:
		# Texture the structural surfaces under review. Tiny articulated joinery
		# retains its generated finish; this is a roof fixture, not a full art bake.
		if record.has("building") and record.building.role not in ["roof","roof_tiles","wall","floor","foundation"]: continue
		var listing: Dictionary=editor._material_tool.list_faces(record.uuid,0,200)
		if not listing.ok: check(false,"gallery surface enumeration"); continue
		var entries: Array=[]
		for face in listing.faces:
			var role:=material_role(record,face); var options:=settings_for(record,face,role); var entry: Dictionary=face.target.duplicate(true)
			entry.merge({"material":definitions[IDS[role]].duplicate(true),"mapping":options.mapping,"scale":options.get("scale",[1,1]),"rotation":options.get("rotation",0),"offset":options.get("offset",[0,0])})
			entries.append(entry)
		record.surface_paint=entries
		if not Paint.valid(record): check(false,"gallery material validation"); return before
		var mesh: Dictionary=Paint.painted_mesh(editor._view.get_node(NodePath(record.uuid)),entries)
		if not mesh.ok: check(false,"gallery compiled face validation"); return before
		count+=1
		if count%100==0: print("GALLERY_PAINT_VALIDATED ",count); await process_frame
	doc.checkpoint_recovery(); doc.records=next; editor._dirty=true; editor._rebuild(); await settle()
	check(Paint.missing(doc.records).is_empty(),"gallery uses classified default pack materials and normal maps")
	return before

func run() -> void:
	Engine.max_fps=60
	root.size=Vector2i(1680,1050); root.content_scale_size=root.size; review_directory="roof_v7"
	var directory:=Paths.cache_directory("roof_v7_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]); var path:=directory.path_join("map.gltf")
	var doc:=Doc.new(); var ground: String=doc.add_box("ground",Vector3(22,-.14,15),Vector3(155,.28,135)); assignments[ground]="street"
	check(doc.save(path)==OK,"create isolated roof fixture")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start actual loopback HTTP roof MCP")
	var discovery:=await rpc("tools/list"); check(discovery.result.tools.size()==113,"current 3D discovery, no legacy 2D tools")
	var templates:=await call_tool("list_building_templates")
	check(templates.roof_presets.size()==5 and templates.parameters_schema.properties.has("annex_floors") and "hip" in templates.parameters_schema.properties.roof.enum,"discover unified roofs, shapes and storey controls")
	var lots: Array=[]; var recipes: Array=[]
	for i in 5:
		var p: Dictionary=templates.roof_presets[i].parameters
		lots.append({"position":[(i%3)*38,0,floori(i/3.0)*38],"parameters":p}); recipes.append(p)
	lots.append({"position":[76,0,38],"parameters":Blueprint.medieval_presets()[2].parameters}); recipes.append(lots.back().parameters)
	var before:=doc.recovery_snapshot(); var history: int=doc._undo.size()
	var preview:=await call_tool("preview_buildings",{"placements":lots})
	check(preview.get("buildings",[]).size()==6 and doc.recovery_snapshot()==before and doc._undo.size()==history,"roof preview is read-only")
	if not preview.ok: quit(1); return
	check(preview.buildings[2].roof_plan.edges.any(func(e):return e.type=="valley"),"HTTP returns final valley topology")
	for bad in [{"roof":"hip","dormers":1},{"annex_floors":3,"floors":2},{"roof_solver":"invalid"},{"compound":"left_wing","annex_floors":2,"width":6,"depth":16,"annex_depth":10,"roof_axis":"depth","chimney":false}]:
		await call_tool("generate_buildings",{"parameters":{"layout":"townhouse"}.merged(bad,true),"placements":[{"position":[-35,0,0]}]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid roof/attachment failures have zero side effects")
	var made:=await call_tool("generate_buildings",{"placements":lots})
	if not made.ok: quit(1); return
	check(doc._undo.size()==history+1,"six generated buildings share one undo transaction")
	await call_tool("undo"); check(doc.recovery_snapshot().records==before.records,"undo removes all roof and building parts")
	await call_tool("redo")
	var id: String=made.building_ids[2]; var instance: Dictionary=editor._buildings.instances()[id]
	var roof_records: Array=doc.records.filter(func(r):return r.get("building",{}).get("id")==id and r.get("building_shape")=="roof_prism" and r.roof_mesh.semantic=="roof_top")
	var target: String=roof_records[0].uuid
	await call_tool("set_object_properties",{"ids":[target],"locked":true})
	before=doc.recovery_snapshot(); history=doc._undo.size()
	await call_tool("update_building",{"id":id,"parameters":{"roof_pitch":40}},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"locked roof blocks regeneration atomically")
	await call_tool("set_object_properties",{"ids":[target],"locked":false})
	var catalog:=await call_tool("list_surface_materials",{"limit":200}); var snapshot:=CatalogSnapshot.new(); snapshot.rows=catalog.materials; editor._material_tool.library=snapshot
	for row in catalog.materials: definitions[row.material_id]=row.material
	var listing:=await call_tool("list_object_surfaces",{"id":target})
	var tops: Array=listing.faces.filter(func(f):return int(f.target.surface)==0)
	check(tops.size()==1,"one paintable final roof plane, separate underside/edge")
	await call_tool("paint_surface",{"id":target,"target":tops[0].target,"material_id":IDS.roof,"mapping":"meters"})
	var painted: MeshInstance3D=editor._view.get_node(NodePath(target)); var normal_bound:=false
	for slot in painted.mesh.get_surface_count():
		var material=painted.get_active_material(slot)
		if material is StandardMaterial3D and material.normal_enabled: normal_bound=material.normal_texture!=null and painted.mesh.surface_get_arrays(slot)[Mesh.ARRAY_TANGENT]!=null
	check(normal_bound,"real default-pack roof PBR normal map and tangents attached")
	before=doc.recovery_snapshot(); history=doc._undo.size()
	await call_tool("update_building",{"id":id,"parameters":{"roof_pitch":44}},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"geometry change preserves painted roof by rejecting incompatible regeneration")
	await call_tool("update_building",{"id":id,"parameters":{"seed":8}})
	check(doc._find(target).has("surface_paint") and editor._buildings.conflicts(id).is_empty(),"compatible regeneration preserves paint and ownership")
	await call_tool("select_objects",{"ids":[target]})
	check(editor._selection_tools.ids.size()==instance.parts.size(),"clicking one roof fragment selects the whole house")
	before=doc.recovery_snapshot()
	await call_tool("transform_selection",{"translation":[-4,0,-27],"rotation":[0,27,0]})
	check(editor._buildings.conflicts(id).is_empty(),"whole-building movement preserves final roof geometry signatures")
	await call_tool("undo"); check(equivalent(doc.records,before.records),"undo movement restores all roof parts")
	await call_tool("redo"); await call_tool("undo")
	before=doc.recovery_snapshot(); history=doc._undo.size()
	await call_tool("generate_buildings",{"parameters":recipes[0],"placements":[{"position":[.2,0,0]}]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"existing geometry blocks overlapping roof/building generation")
	# Model a prop inside the U courtyard. Neither the roof envelope nor occupancy
	# may replace the empty courtyard with a convex hull over the whole house.
	var occupancy: Dictionary=editor._buildings.prepare({"placements":[{"parameters":recipes[2],"position":[-40,0,0]}]})
	check(occupancy.ok,"courtyard placement away from existing objects")
	if occupancy.ok:
		var obstacle:={"kind":"box","position":[-40,9,10],"rotation":[0,0,0],"size":[1,1,1]}
		check(not preload("res://scripts/world_editor/building_footprint.gd").batches_overlap(occupancy.plans[0].occupancy,[preload("res://scripts/world_editor/building_footprint.gd").record_shape(obstacle)]),"courtyard air remains available for other objects")
	if DisplayServer.get_name()!="headless":
		await call_tool("set_environment",{"preset":"day","sun_rotation":[-43,145,0],"sun_energy":1.3,"ambient_energy":.55,"sun_shadows":true,"ambient_occlusion":true})
		await paint_world()
	await call_tool("save_world")
	var saved: Array=doc.records.duplicate(true)
	await call_tool("open_world",{"path":path}); doc=editor._doc
	check(equivalent(saved,doc.records) and editor._buildings.instances().keys().all(func(key):return editor._buildings.conflicts(key).is_empty()),"save/reopen preserves roof geometry, PBR, IDs and clean ownership")
	editor._building_panel.refresh_list(id); editor._building_panel.preview(); await settle()
	check(is_instance_valid(editor._building_panel.ghost),"UI preview uses the same final roof planner")
	editor._building_panel.clear_preview()
	if DisplayServer.get_name()!="headless":
		editor._grid.hide(); editor._canvas.get_child(0).msaa_3d=Viewport.MSAA_4X
		await capture("gallery",Vector3(142,111,-101),Vector3(36,3,20),114)
		for i in lots.size():
			var at:=Blueprint.vec(lots[i].position)
			await capture("roof_%d"%i,at+Vector3(-25,27,31),at+Vector3(0,6,3),31)
		var report:=FileAccess.open(Review.review_path("roof_v7/gallery.json"),FileAccess.WRITE)
		report.store_string(JSON.stringify({"map_path":path,"placements":lots,"building_ids":made.building_ids,"failures":failed},"\t")); report.close()
	editor._mcp.stop(); editor.free(); session.world3d_editor_doc=null; session.world3d_editor_path=""; await settle()
	# Query real triangle collision built from the saved final roof, not AABBs.
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"runtime loads roof prisms from native glTF records")
	if loaded[0]!=null:
		var host:=Node3D.new(); root.add_child(host); host.add_child(loaded[0]); Stream.sync(loaded[0],host,Vector3(40,0,20)); await physics_frame; await physics_frame
		var space:=host.get_world_3d().direct_space_state
		var prism_ids: Dictionary={}
		for record in doc.records:
			if record.get("building_shape")=="roof_prism": prism_ids[record.uuid]=true
		var exclude: Array[RID]=[]; var bodies: Dictionary=loaded[0].get_meta("stream_bodies",{})
		for uuid in bodies:
			if not prism_ids.has(uuid): exclude.append(bodies[uuid].get_rid())
		for i in lots.size():
			var at:=Blueprint.vec(lots[i].position); var plan:=Blueprint.generate(recipes[i]); var hits:=0
			for face in plan.roof_plan.faces:
				var center:=Vector3.ZERO
				for p in face.boundary: center+=Blueprint.vec(p)
				center/=face.boundary.size(); center+=at
				var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(center+Vector3(0,.02,0),center-Vector3(0,.2,0)))
				if not hit.is_empty() and hit.position.distance_to(center)<.04: hits+=1
			check(hits==plan.roof_plan.faces.size(),"saved roof face collision case %d"%i)
			for cut in plan.roof_plan.openings:
				var module: Dictionary=plan.roof_plan.modules.filter(func(m):return m.id==cut.module)[0]
				var center:=Vector2((cut.rect[0]+cut.rect[2])/2,(cut.rect[1]+cut.rect[3])/2); var y:=INF
				for plane in RoofPlan.planes(module): y=minf(y,RoofPlan.height(plane,center))
				var top:=Vector3(center.x,y+.03,center.y)+at; var query:=PhysicsRayQueryParameters3D.create(top,top-Vector3(0,.2,0)); query.exclude=exclude
				check(space.intersect_ray(query).is_empty(),"actual roof triangle collider leaves "+cut.id+" open")
		# The existing main stair must reach each newly occupied upper wing.
		var nav:=preload("res://scripts/world3d/world_navigation.gd").new(); nav.agent_height=2.1; host.add_child(nav)
		var specs: Array=loaded[0].get_meta("stream_library")
		var nav_ids: Array=[]
		for building_id in made.building_ids.slice(0,3): nav_ids.append_array(doc.map_meta.building_instances[building_id].parts.values())
		nav.build(specs.filter(func(spec):return spec.uuid in nav_ids))
		var deadline:=Time.get_ticks_msec()+50000
		while not nav.fully_ready and Time.get_ticks_msec()<deadline: await process_frame
		check(nav.fully_ready,"2.1m agent navmesh for L/T/U upper wings")
		if nav.fully_ready:
			for i in 3:
				var plan:=Blueprint.generate(recipes[i]); var at:=Blueprint.vec(lots[i].position)
				var start: Vector3=Blueprint.vec(plan.rooms.filter(func(room):return room.id=="f0/rear")[0].center)+at
				for room in plan.rooms:
					if room.floor!=1 or not room.id.begins_with("wing"): continue
					check(nav.find_path(start,Blueprint.vec(room.center)+at).ok,"stair and shared door reach "+str(i)+" "+room.id)
		var cutaway:=preload("res://scripts/world3d/building_cutaway.gd").new(); cutaway.bind(loaded[0])
		check(not cutaway.locate(Vector3(0,4,11)+Blueprint.vec(lots[1].position)).is_empty(),"upper attached wing participates in third-person interior detection")
		host.free()
	print("ROOF_HTTP_FINISHED failures=",failed," fixture=",path); quit(1 if failed else 0)
