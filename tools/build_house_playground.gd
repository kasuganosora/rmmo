extends "res://tools/build_medieval_material_demo.gd"
## Current seven medieval presets, authored to a separate playable map.
var DEST="D:/code/rmmo_runtime/maps/medieval_house_showcase/map.gltf"
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
var houses: Array=[]
var only_preset:=""
var resume_checkpoint:=""
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):DEST=arg.trim_prefix("--output=")
		if arg.begins_with("--preset="):only_preset=arg.trim_prefix("--preset=")
		if arg.begins_with("--resume="):resume_checkpoint=arg.trim_prefix("--resume=")
	create_timer(1800).timeout.connect(func():quit(2)); Engine.max_fps=30
	root.size=Vector2i(1920,1200); root.content_scale_size=root.size; review_directory="house_revision"+("_"+only_preset if not only_preset.is_empty() else "")
	if "--html-only" in OS.get_cmdline_user_args():
		houses=JSON.parse_string(FileAccess.get_file_as_string(Review.review_path(review_directory+"/showcase.json"))).houses
		write_gallery_page(); quit(); return
	rpc_timeout_ms=240000
	var capture_only: bool="--capture-only" in OS.get_cmdline_user_args()
	if FileAccess.file_exists(DEST) and not capture_only: push_error("Showcase exists; use --capture-only to inspect it without overwriting"); quit(1); return
	var doc=Doc.open_file(DEST) if capture_only else Doc.new()
	if doc==null: quit(1); return
	var ground: String=""
	if not resume_checkpoint.is_empty():
		var checkpoint:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(resume_checkpoint))
		doc.records=checkpoint.records;doc.map_meta=checkpoint.meta;houses=checkpoint.houses
	if not capture_only and resume_checkpoint.is_empty():
		ground=doc.add_box("ground",Vector3(0,-.25,0),Vector3(190,.5,130)); assignments[ground]="street"
		doc.map_meta.map_name="中世纪基础房屋 · 七款试玩展示"
		doc.map_meta.spawn=[0,.95,-53]
		doc.map_meta.map_ref="showcase/medieval_houses"
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=DEST; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=DEST.get_base_dir().path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"showcase real HTTP MCP")
	var discovery:=await rpc("tools/list"); check(discovery.result.tools.size()==118,"current 3D tools discovered")
	if capture_only:
		if houses.is_empty():
			var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Review.review_path(review_directory+"/showcase.json"))); houses=saved.houses
	else:
		if resume_checkpoint.is_empty():
			var presets: Array=(await call_tool("list_building_templates")).presets
			if not only_preset.is_empty():presets=presets.filter(func(p):return p.id==only_preset)
			var placements: Array=[]
			for i in presets.size():
				var at: Array=[(i%4)*40-60,0,floori(i/4.)*50-25]
				placements.append({"parameters":presets[i].parameters,"position":at})
				houses.append({"preset":presets[i].id,"name":presets[i].name,"parameters":presets[i].parameters,"position":at,"number":i+1})
			var result:=await call_tool("generate_buildings",{"placements":placements})
			if not result.get("ok",false): editor._mcp.stop(); quit(1); return
			for i in houses.size(): houses[i].building_id=result.building_ids[i]
			check(houses.size()==(7 if only_preset.is_empty() else 1),"all seven current medieval base presets generated")
			await call_tool("set_environment",{"preset":"day","sun_rotation":[-43,145,0],"sun_color":[1,.96,.89],"sun_energy":1.15,"ambient_color":[.78,.82,.89],"ambient_energy":.58,"background_color":[.56,.64,.72],"sun_shadows":true,"ambient_occlusion":true,"cloud_altitude":1500,"cloud_thickness":450,"cloud_scale":1800})
			await call_tool("set_playtest_spawn",{"position":[0,0,-53]})
			await paint_gallery()
		if failed: editor._mcp.stop(); quit(1); return
		if not "--preview-only" in OS.get_cmdline_user_args():
			var expected: Array=doc.records.duplicate(true)
			var saved:=await call_tool("save_world",{"background":true})
			while editor.saving(): await create_timer(.25).timeout
			check(editor._save_job.state().result.get("saved",false),"showcase native save completes")
			await call_tool("open_world",{"path":DEST})
			check(equivalent(editor._doc.records,expected),"all textured buildings survive save/reopen")
			check(Paint.missing(editor._doc.records).is_empty(),"all PBR dependencies resolve")
	await render_gallery()
	write_gallery_page()
	var report:={"map_path":DEST,"houses":houses,"objects":editor._doc.records.size(),"spawn":[0,.95,-53],"failures":failed,"sha256":FileAccess.get_sha256(DEST)}
	var file:=FileAccess.open(Review.review_path(review_directory+"/showcase.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	editor._mcp.stop(); editor.queue_free(); await settle()
	print("HOUSE_PLAYGROUND_FINISHED ",JSON.stringify(report)); quit(1 if failed else 0)

func paint_gallery() -> void:
	var rows: Array=(await call_tool("list_surface_materials",{"limit":200})).materials
	for row in rows: definitions[row.material_id]=row.material
	for id in IDS.values(): check(definitions.has(id),"default PBR material present: "+id)
	if failed: return
	# Validate the shared material/HTTP paint path, then compile the new document's
	# remaining face assignments once. Avoid thousands of whole-editor refreshes.
	var id: String=editor._doc.records[0].uuid
	var faces: Dictionary=editor._material_tool.list_faces(id,0,200)
	await call_tool("paint_surface",{"id":id,"target":faces.faces[0].target,"material_id":IDS.street,"mapping":"meters"})
	editor._doc.checkpoint()
	var done:=0
	var validation:Dictionary={}
	for record in editor._doc.records:
		if record.get("building",{}).get("role")=="light_sconce":continue
		var listing: Dictionary=author_faces(record)
		if not listing.ok: check(false,"surface listing: "+str(record.uuid)); return
		var entries: Array=[]
		for face in listing.faces:
			var role:=material_role(record,face)
			var entry: Dictionary=face.target.duplicate(true)
			entry.merge({"mapping":"meters","scale":[1,1],"rotation":0,"offset":[0,0]})
			entry.merge(settings_for(record,face,role)); entry.material=definitions[IDS[role]].duplicate(true); entries.append(entry)
		record.surface_paint=entries
		if not Paint.valid(record,false,"",validation): check(false,"compiled face paint valid: "+str(record.uuid)); return
		done+=1
		if done%100==0: print("HOUSE_PAINT ",done,"/",editor._doc.records.size()); await process_frame
	var checkpoint:=FileAccess.open(Review.review_path(review_directory+"/painted_checkpoint.json"),FileAccess.WRITE)
	checkpoint.store_string(JSON.stringify({"records":editor._doc.records,"meta":editor._doc.map_meta,"houses":houses}));checkpoint.close()
	editor._dirty=true; editor._rebuild(); await settle()
	check(true,"exterior/interior PBR assignments compiled and rebuilt")

func author_faces(record:Dictionary)->Dictionary:
	var node:MeshInstance3D=editor._view.get_node(NodePath(record.uuid))
	var geo:Dictionary=Paint.geometry(node);var rows:Array=[]
	if not geo.ok:return geo
	for slot in geo.surfaces.size():
		var data:Dictionary=geo.surfaces[slot]
		for face in data.faces:
			var normal:Vector3=(node.global_basis.inverse().transposed()*data.faces[face].normal).normalized()
			rows.append({"target":{"mesh":".","surface":slot,"face":face,"geometry":data.signature},"normal":[normal.x,normal.y,normal.z]})
	return {"ok":true,"faces":rows}

func render_gallery() -> void:
	editor._ground_batches.enabled=false;editor._ground_batches.clear()
	editor._grid.hide(); editor._canvas.get_child(0).msaa_3d=Viewport.MSAA_4X
	await capture("overview",Vector3(120,150,-175),Vector3(0,2,0),145)
	for house in houses:
		var own: Array=editor._doc.records.filter(func(r):return r.get("building",{}).get("id")==house.building_id)
		var bounds:=preload("res://scripts/world_editor/selection_geometry.gd").bounds(own)
		var target:=bounds.get_center()
		var others: Array=[]
		for record in editor._doc.records:
			if record.has("building") and record.building.id!=house.building_id:
				var node: Node3D=editor._view.get_node(str(record.uuid)); others.append(node); node.hide()
		await capture(house.preset,target+Vector3(25,18,-30),target,maxf(22,bounds.size.z*1.15))
		for node in others: node.show()
		var hidden: Array=[]
		for record in own:
			if record.building.floor>=1 or record.building.part.contains("/north/") or record.building.part.contains("/east/") or record.building.part.begins_with("porch/"):
				var node: Node3D=editor._view.get_node(str(record.uuid)); hidden.append(node); node.hide()
		await capture(house.preset+"_interior",Blueprint.vec(house.position)+Vector3(18,22,-26),Blueprint.vec(house.position)+Vector3(0,1,0),maxf(22,bounds.size.z*1.15))
		if house.preset=="hall":
			await capture("stair_detail",Blueprint.vec(house.position)+Vector3(-3,8,-4),Blueprint.vec(house.position)+Vector3(3,2.6,1.5),8)
		for node in hidden: node.show()

func write_gallery_page() -> void:
	var html:="<!doctype html><meta charset='utf-8'><title>中世纪基础房屋展示</title><style>body{margin:32px auto;max-width:1500px;padding:0 24px;background:#19212b;color:#eef1f4;font:16px/1.7 system-ui}h1{margin-bottom:0}p{color:#bcc8d4}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(460px,1fr));gap:24px}article{background:#26313e;padding:20px;border-radius:12px}img{width:100%;height:auto;border-radius:8px}a{color:#9cd0ff}summary{cursor:pointer}h2{margin:0 0 12px}</style><h1>中世纪基础房屋 · 七款试玩展示</h1><p>当前生成器预设，4 米层高，默认库 PBR。室内图为临时剖视，试玩地图保留完整墙体和屋顶。门窗保留独立的程序控制组件。</p><a href='overview.png'><img src='overview.png' alt='七款房屋全景'></a><div class='grid'>"
	for house in houses:
		html+="<article><h2>%d · %s</h2><a href='%s.png'><img src='%s.png' alt='%s'></a><details><summary>查看首层剖视</summary><a href='%s_interior.png'><img src='%s_interior.png' alt='室内'></a></details></article>"%[house.number,house.name,house.preset,house.preset,house.name,house.preset,house.preset]
	html+="</div>"
	var file:=FileAccess.open(Review.review_path(review_directory+"/index.html"),FileAccess.WRITE); file.store_string(html); file.close()
