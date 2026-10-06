extends "res://tools/test_world3d_mcp.gd"
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const Settings = preload("res://scripts/world3d/environment_settings.gd")
const Review = preload("res://scripts/asset/art_paths.gd")
const IDS = {
	"plaster":"pack:default:walls/earthen_plaster/material",
	"interior":"pack:default:walls/interior_limewash/material",
	"timber":"pack:default:wood/solid_timber/material",
	"wood":"pack:default:wood/worn_planks/material",
	"shutter":"pack:default:wood/structural_oak/material",
	"roof":"pack:default:roofs/terracotta_plain/material",
	"stone":"pack:default:walls/castle_rubble/material",
	"street":"pack:default:paving/historic_cobble/material",
	"steps":"pack:default:paving/sandstone_floor/material",
	"hardware":"pack:default:details/forged_iron/material",
	"cloth":"pack:default:details/linen_curtain/material",
	"glass":"pack:default:details/window_glass/material"
}
var assignments: Dictionary={}
var work: Array=[]
var definitions: Dictionary={}
var review_directory := "material_house"

class CatalogSnapshot extends "res://scripts/world_editor/surface_material_library.gd":
	var rows: Array=[]
	func entries(_content_root: String="") -> Array: return rows

func material_role(record: Dictionary, face: Dictionary) -> String:
	if assignments.has(record.uuid): return assignments[record.uuid]
	var building: Dictionary=record.get("building",{})
	var role:=str(building.get("role","")); var part:=str(building.get("part",""))
	var normal:=Vector3(face.normal[0],face.normal[1],face.normal[2])
	if record.get("building_shape")=="roof_prism" and role=="roof":
		if record.roof_mesh.semantic=="gable": return "plaster" if int(face.target.surface)==0 else "interior"
		return "roof" if int(face.target.surface)==0 else "wood"
	if role=="hardware": return "hardware"
	if role=="curtain": return "cloth"
	if role=="entry_step": return "steps"
	if role=="foundation": return "stone"
	if part=="yard/floor": return "steps"
	if part=="porch/canopy": return "wood"
	if role=="door": return "shutter"
	if role=="stone_trim": return "steps"
	if role=="roof_tiles": return "roof"
	if role=="wall" or record.get("building_shape","")=="gable":
		var recipe: Dictionary=editor._buildings.instances().get(building.get("id",""),{})
		var outward:=Vector3.ZERO
		for side in {"/north/":Vector3.FORWARD,"/south/":Vector3.BACK,"/west/":Vector3.LEFT,"/east/":Vector3.RIGHT}:
			if part.contains(side) or part.ends_with(side.trim_suffix("/")):outward={"/north/":Vector3.FORWARD,"/south/":Vector3.BACK,"/west/":Vector3.LEFT,"/east/":Vector3.RIGHT}[side]
		if part.contains("/gable"):
			if part.contains("dormer"): outward=Vector3.RIGHT if recipe.get("parameters",{}).get("roof_axis")=="width" else Vector3.LEFT
			else: outward=Vector3.FORWARD if part.ends_with("-1") else Vector3.BACK
		if part.ends_with("/back") or part.ends_with("/back_gable"): outward=Vector3.LEFT if recipe.get("parameters",{}).get("roof_axis")=="width" else Vector3.RIGHT
		if part.contains("/cheek"): outward=Vector3.FORWARD if part.contains("/cheek-1") else Vector3.BACK
		if part.begins_with("roof/") and recipe.get("parameters",{}).get("roof_axis")=="width":outward=Basis(Vector3.UP,PI/2)*outward
		outward=Basis(Vector3.UP,deg_to_rad(float(recipe.get("yaw",0))))*outward
		# Exposed ends of exterior side walls are exterior plaster, not limewash.
		if role=="wall" and not outward.is_zero_approx() and absf(normal.y)<.9 and normal.dot(outward)>-.1:return "plaster"
		return "plaster" if normal.dot(outward)>.9 else "interior"
	if part.contains("/slope"): return "roof" if normal.y>0 else "wood"
	if role=="floor":
		if normal.y<-.9:return "interior"
		return "wood" if normal.y>.9 else "timber"
	if role=="stairs": return "shutter"
	if role=="window": return "glass"
	if role=="shutter": return "shutter"
	return "timber"

func settings_for(record: Dictionary, face: Dictionary, role: String) -> Dictionary:
	if role in ["hardware","cloth"]:return {"mapping":"uv","scale":[1,1],"offset":[0,0],"rotation":0}
	var settings: Dictionary={"mapping":"meters"}
	var node: MeshInstance3D=editor._view.get_node(NodePath(record.uuid))
	var data: Dictionary=Paint.geometry(node).surfaces[int(face.target.surface)]
	var plane: Dictionary=data.faces[int(face.target.face)]
	var n: Vector3=plane.normal
	var u: Vector3=(Vector3.RIGHT-n*n.x).normalized() if absf(n.x)<.9 else (Vector3.BACK-n*n.z).normalized()
	var v: Vector3=n.cross(u).normalized()
	var low:=Vector2(INF,INF)
	for triangle in plane.triangles:
		for corner in 3:
			var vertex: Vector3=data.arrays[Mesh.ARRAY_VERTEX][data.indices[triangle*3+corner]]
			low=low.min(Vector2(vertex.dot(u),vertex.dot(v)))
	var material: Dictionary=definitions[IDS[role]]
	var tile: Array=material.get("tile_size",[1,1])
	var origin:=Vector2(node.global_position.dot(node.global_basis*u),node.global_position.dot(node.global_basis*v))
	# The same projection origin keeps neighboring wall pieces on one masonry grid.
	settings.offset=[(low.x+origin.x)/float(tile[0]),(low.y+origin.y)/float(tile[1])]
	if role in ["timber","wood","shutter"]:
		var size:=Vector3(record.size[0],record.size[1],record.size[2])
		var tangent_size:=size
		for axis in 3:
			if absf(n[axis])>.9:tangent_size[axis]=0
		var grain:=Vector3.ZERO; grain[tangent_size.max_axis_index()]=1.0
		if absf(grain.dot(n))<.9:
			settings.rotation=rad_to_deg(atan2(grain.dot(u),grain.dot(v)))
			if absf(sin(deg_to_rad(settings.rotation)))>.9: settings.scale=[float(tile[1])/float(tile[0]),float(tile[0])/float(tile[1])]
		settings.offset=[.083,.137]
	if role=="roof":
		var world_normal: Vector3=node.global_basis*n
		var downslope: Vector3=Vector3.DOWN-world_normal*Vector3.DOWN.dot(world_normal)
		if downslope.length()>.01:
			var direction: Vector3=node.global_basis.inverse()*downslope.normalized()
			settings.rotation=rad_to_deg(atan2(direction.dot(u),direction.dot(v)))
			if absf(sin(deg_to_rad(settings.rotation)))>.9:settings.scale=[float(tile[1])/float(tile[0]),float(tile[0])/float(tile[1])]
		settings.offset=[0,0]
		if record.get("building_shape")=="roof_prism" and int(face.target.surface)==0:
			# Final roof patches share a building-local metre UV origin. Retain it
			# so clipping a chimney/valley does not restart tile rows at every patch.
			settings.mapping="uv"; settings.scale=[1.0/float(tile[0]),1.0/float(tile[1])]
	return settings

func capture(label: String, at: Vector3, target: Vector3, size: float) -> void:
	editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL; editor._camera.size=size
	editor._camera.position=at; editor._camera.look_at(target)
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	editor._canvas.get_child(0).get_texture().get_image().save_png(Review.review_path(review_directory+"/"+label+".png"))

func run() -> void:
	if OS.get_cmdline_user_args().has("--timber"): review_directory="material_house_timber"
	if OS.get_cmdline_user_args().has("--refresh-preview"):
		await refresh_preview();return
	create_timer(900).timeout.connect(func():push_error("Material house build timeout");quit(2))
	root.size=Vector2i(1920,1200); root.content_scale_size=root.size
	var directory:=Paths.cache_directory("material_house_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	var street: String=doc.add_box("ground",Vector3(0,-.14,0),Vector3(42,.28,38))
	assignments[street]="street"
	check(doc.save(path)==OK,"create independent material showcase map")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start current HTTP MCP")
	var discovery:=await rpc("tools/list")
	var env_tool: Dictionary=discovery.result.tools.filter(func(t):return t.name=="set_environment")[0]
	check(discovery.result.tools.size()==69 and env_tool.inputSchema.properties.has("sun_shadows") and env_tool.inputSchema.properties.has("ambient_occlusion"),"MCP discovers both lighting controls")
	var catalog:=await call_tool("list_surface_materials",{"limit":200})
	for id in IDS.values(): check(catalog.materials.any(func(row):return row.material_id==id),"shared material present: "+id)
	# This offline authoring pass uses the validated catalog returned by HTTP as
	# a snapshot. Per-face painting still checks the files through the shared tool.
	var snapshot_library:=CatalogSnapshot.new();snapshot_library.rows=catalog.materials
	editor._material_tool.library=snapshot_library
	for row in catalog.materials:definitions[row.material_id]=row.material
	var parameters: Dictionary=Blueprint.medieval_presets()[0].parameters.duplicate(true)
	parameters.eaves=.45
	if OS.get_cmdline_user_args().has("--timber"): parameters.style="timber"; parameters.jetty=.28
	await call_tool("generate_buildings",{"parameters":parameters,"placements":[{"position":[0,0,0]}]})
	editor._rebuild(); await settle()
	var before:=doc.recovery_snapshot(); var history: int=doc._undo.size()
	await call_tool("set_environment",{"sun_shadows":"yes"},false)
	await call_tool("set_environment",{"ambient_occlusion":1},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid lighting controls fail atomically")
	await call_tool("set_environment",{"sun_shadows":false,"ambient_occlusion":false})
	check(not editor._sun.shadow_enabled and not editor._camera.environment.ssao_enabled,"HTTP can disable both effects")
	await call_tool("undo")
	check(editor._sun.shadow_enabled and editor._camera.environment.ssao_enabled,"lighting undo restores both effects")
	await call_tool("redo"); check(not editor._sun.shadow_enabled,"lighting redo retained")
	await call_tool("set_environment",{"preset":"day","sun_rotation":[-43,145,0],"sun_color":[1,.96,.89],"sun_energy":1.35,"ambient_color":[.78,.82,.89],"ambient_energy":.48,"background_color":[.56,.61,.65],"sun_shadows":true,"ambient_occlusion":true})
	check(editor._environment_panel.form.fields.sun_shadows.button_pressed and editor._environment_panel.form.fields.ambient_occlusion.button_pressed,"UI displays shared lighting controls")
	var initial_records: Array=await paint_world()
	var finished_records: Array=doc.records.duplicate(true)
	var checkpoint:=FileAccess.open(Review.review_path(review_directory+"/authoring_checkpoint.json"),FileAccess.WRITE)
	checkpoint.store_string(JSON.stringify(doc.recovery_snapshot()));checkpoint.close()
	editor._grid.visible=false
	await capture("front",Vector3(19,13,-24),Vector3(0,3.9,-.2),18.8)
	await call_tool("undo");check(doc.records==initial_records,"bulk surface transaction undo restores prior records")
	await call_tool("redo");check(doc.records==finished_records,"bulk surface transaction redo restores all textures")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	var exported: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(exported.get("materials",[]).size()<=IDS.size()+2 and exported.get("images",[]).size()<=IDS.size()*4,"glTF shares materials and packed textures across thousands of faces")
	check(equivalent(editor._doc.records,finished_records) and Paint.missing(editor._doc.records).is_empty(),"complete materials and dependencies survive save/reopen")
	check(editor._sun.shadow_enabled and editor._camera.environment.ssao_enabled,"saved lighting restores in editor")
	check(is_equal_approx(editor._sun.shadow_bias,.4),"thin-wall shadow bias applies after reopen")
	var runtime_sun:=DirectionalLight3D.new();var runtime_environment:=Environment.new()
	Settings.apply(Settings.resolve(editor._doc.map_meta),runtime_sun,runtime_environment)
	check(runtime_sun.shadow_enabled and runtime_environment.ssao_enabled and is_equal_approx(runtime_sun.shadow_bias,.4),"runtime uses the same saved lighting settings");runtime_sun.free()
	editor._grid.visible=false
	editor._canvas.get_child(0).msaa_3d=Viewport.MSAA_4X
	await capture("front",Vector3(19,13,-24),Vector3(0,3.9,-.2),18.8)
	await capture("rear",Vector3(-18,14,23),Vector3(0,4,0),19.5)
	await capture("detail",Vector3(12,7,-16),Vector3(-.2,3.5,-5.7),8.5)
	await capture_interior()
	var report: Dictionary={"map_path":path,"painted_faces":work.size()+IDS.size(),"objects":editor._doc.records.size(),"failures":failed,"materials":IDS,"sun_shadows":true,"ambient_occlusion":true}
	var file:=FileAccess.open(Review.review_path(review_directory+"/demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MATERIAL_HOUSE_FINISHED ",JSON.stringify(report))
	editor._mcp.stop();editor.queue_free();await settle();quit(1 if failed else 0)

func capture_interior() -> void:
	editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE;editor._camera.fov=70
	editor._camera.position=Vector3(-2.1,1.95,-5.7);editor._camera.look_at(Vector3(.6,1.85,-.2))
	for i in 12:await process_frame
	await RenderingServer.frame_post_draw
	editor._canvas.get_child(0).get_texture().get_image().save_png(Review.review_path(review_directory+"/interior.png"))
	# Temporary cutaway is a viewport inspection only; saved visibility stays intact.
	var hidden: Array=[]
	for record in editor._doc.records:
		var b: Dictionary=record.get("building",{})
		var part:=str(b.get("part",""))
		if int(b.get("floor",-1))>=1 or part.contains("/north/") or part.contains("/east/"):
			var node: Node3D=editor._view.get_node(NodePath(record.uuid));hidden.append([node,node.visible]);node.visible=false
	await capture("cutaway",Vector3(16,18,-21),Vector3(0,1.3,0),17)
	for pair in hidden:pair[0].visible=pair[1]

func refresh_preview() -> void:
	# Re-light the last completed sample without regenerating its geometry or paint.
	root.size=Vector2i(1920,1200);root.content_scale_size=root.size
	var report_path:=Review.review_path(review_directory+"/demo.json")
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report_path))
	var path: String=report.map_path
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._draft_directory=path.get_base_dir().path_join("drafts")
	root.add_child(editor);await settle();editor._safety.enabled=false
	check(not editor._load_failed,"reopen completed demo for lighting review")
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start preview HTTP MCP")
	await call_tool("set_environment",{"sun_rotation":[-43,145,0],"sun_color":[1,.96,.89],"sun_energy":1.35,"ambient_color":[.78,.82,.89],"ambient_energy":.48})
	editor._grid.visible=false;editor._canvas.get_child(0).msaa_3d=Viewport.MSAA_4X
	if OS.get_cmdline_user_args().has("--diagnose"):
		print("SHADOW_SETTINGS ",editor._sun.shadow_bias," ",editor._sun.shadow_normal_bias)
		editor._sun.shadow_enabled=false
		await capture("detail_no_shadows",Vector3(12,7,-16),Vector3(-.2,3.5,-5.7),8.5)
		editor._camera.environment.ssao_enabled=false
		await capture("detail_no_occlusion",Vector3(12,7,-16),Vector3(-.2,3.5,-5.7),8.5)
		editor._sun.shadow_enabled=true;editor._camera.environment.ssao_enabled=true
		for bias in [4.0,8.0]:
			editor._sun.shadow_normal_bias=bias
			await capture("detail_normal_bias%d"%bias,Vector3(12,7,-16),Vector3(-.2,3.5,-5.7),8.5)
		editor._sun.shadow_normal_bias=2;editor._sun.shadow_bias=.4
		await capture("detail_depth_bias",Vector3(12,7,-16),Vector3(-.2,3.5,-5.7),8.5)
		editor._mcp.stop();editor.queue_free();await settle();quit(0);return
	await capture("front",Vector3(19,13,-24),Vector3(0,3.9,-.2),18.8)
	await capture("rear",Vector3(-18,14,23),Vector3(0,4,0),19.5)
	await capture("detail",Vector3(12,7,-16),Vector3(-.2,3.5,-5.7),8.5)
	await call_tool("save_world")
	report.failures+=failed
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MATERIAL_PREVIEW_FINISHED failures=",failed)
	editor._mcp.stop();editor.queue_free();await settle();quit(1 if failed else 0)

func paint_world() -> Array:
	var doc=editor._doc
	# Every material is first exercised through HTTP; remaining faces use the same
	# paint business operation inside one UI brush transaction, without mouse automation.
	var http_roles: Dictionary={}
	for record in doc.records.duplicate(true):
		var listing: Dictionary=editor._material_tool.list_faces(record.uuid,0,200)
		if not listing.ok:check(false,"list faces for "+record.uuid);continue
		for face in listing.faces:
			var role:=material_role(record,face)
			var settings:=settings_for(record,face,role)
			var arguments: Dictionary={"id":record.uuid,"target":face.target,"material_id":IDS[role]}
			arguments.merge(settings)
			if not http_roles.has(role):
				await call_tool("paint_surface",arguments);http_roles[role]=true
			else:work.append(arguments)
	check(http_roles.size()>=9,"all exterior and interior material roles painted through real HTTP")
	var initial_records: Array=doc.records.duplicate(true)
	editor._material_tool.action="paint"
	editor._material_tool.start_stroke()
	var by_object: Dictionary={}
	for operation in work:
		if not by_object.has(operation.id):by_object[operation.id]=[]
		by_object[operation.id].append(operation)
	var done:=0;var paint_started:=Time.get_ticks_msec()
	for id in by_object:
		var next: Dictionary=doc._find(id).duplicate(true)
		var entries: Array=next.get("surface_paint",[])
		for operation in by_object[id]:
			var entry: Dictionary=operation.target.duplicate(true)
			entry.merge({"material":definitions[operation.material_id].duplicate(true),"mapping":operation.mapping,"scale":operation.get("scale",[1,1]),"rotation":operation.get("rotation",0),"offset":operation.get("offset",[0,0])})
			entries=entries.filter(func(old):return Paint.face_key(old)!=Paint.face_key(entry))
			entries.append(entry)
		next.surface_paint=entries
		if not Paint.valid(next):check(false,"invalid compiled material record");break
		var preview: Dictionary=Paint.painted_mesh(editor._view.get_node(NodePath(id)),entries)
		if not preview.ok:check(false,str(preview));break
		# This fixture compiles each object's faces once, then uses the brush's
		# shared commit/refresh/undo path. Interactive painting remains unchanged.
		var result: Dictionary=editor._material_tool._commit(id,next)
		if not result.ok:check(false,str(result));break
		done+=by_object[id].size()
		if done%100<6:print("TEXTURING ",done,"/",work.size()," seconds=",(Time.get_ticks_msec()-paint_started)/1000.0);await process_frame
	editor._material_tool.finish()
	check(done==work.size(),"complete exterior and interior use actual material definitions")
	check(doc.records.any(func(r):
		var names: Array=r.get("surface_paint",[]).map(func(e):return e.material.name)
		return names.has(definitions[IDS.plaster].name) and names.has(definitions[IDS.interior].name)),"same wall keeps distinct outside and inside materials")
	return initial_records
