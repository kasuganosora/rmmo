extends "res://tools/test_world3d_mcp.gd"
const City=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const D=preload("res://scripts/world3d/bridge_data.gd")
const Meshes=preload("res://scripts/world3d/bridge_mesh.gd")
const StreamClearance=preload("res://scripts/world_editor/bridge_stream_clearance.gd")
const Clearance=preload("res://scripts/world_editor/bridge_clearance.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
var directory:String
var path:String
var center:=Vector3(331.18333,8.49,125.5)
var axis:=Vector3(.26667,0,8).normalized()
var water_id:String

func snapshot()->Dictionary:
	var value:Dictionary=editor._doc.recovery_snapshot();value.erase("next");return value

func reject(args:Dictionary,part:="")->void:
	var before:=snapshot();var undo_count:int=editor._doc._undo.size()
	var result:=await call_tool("generate_bridge",args,false)
	check(equivalent(before,snapshot()) and undo_count==editor._doc._undo.size(),"invalid bridge leaves records, metadata and history unchanged")
	if not part.is_empty():check(part in result.get("error",""),"diagnostic identifies "+part)

func mesh_of(faces:Array)->ArrayMesh:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array(faces)
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return mesh

func exact_geometry_cases()->void:
	# A narrow tooth is off the arch centre and lies beyond the nominal deck
	# width. A centre ray or a clipped two-metre navigation strip misses it.
	var faces:Array=[Vector3(-2,.5,-5),Vector3(2,.5,-5),Vector3(2,.5,5),Vector3(-2,.5,-5),Vector3(2,.5,5),Vector3(-2,.5,5),Vector3(1.6,.4,3.7),Vector3(1.61,.1,3.71),Vector3(1.62,.4,3.7)]
	for origin:Vector3 in [Vector3.ZERO,Vector3(7800,17,-6500)]:
		var water:={"polygon":PackedVector2Array([Vector2(-1.8,-8),Vector2(1.8,-8),Vector2(1.8,8),Vector2(-1.8,8)]),"plane":Plane(Vector3.UP,origin.y),"source_id":"whole_water"}
		for i in water.polygon.size():water.polygon[i]+=Vector2(origin.x,origin.z)
		var result:=StreamClearance.measure_mesh(mesh_of(faces),Transform3D(Basis.IDENTITY,origin),StreamClearance.patches([water],origin))
		check(result.ok and absf(result.clearance-.1)<.001,"full wet width and flow direction detect narrow trim tooth at "+str(origin))
		var split:Array=[]
		for half in [-1,1]:
			var p:=PackedVector2Array([Vector2(-1.8,0),Vector2(1.8,0),Vector2(1.8,half*8),Vector2(-1.8,half*8)])
			for i in p.size():p[i]+=Vector2(origin.x,origin.z)
			split.append({"polygon":p,"plane":water.plane,"source_id":"tile"+str(half)})
		var tiled:=StreamClearance.measure_mesh(mesh_of(faces),Transform3D(Basis.IDENTITY,origin),StreamClearance.patches(split,origin))
		check(tiled.ok and absf(tiled.clearance-result.clearance)<.001,"water tile seams and reversed winding preserve minimum")
	# A vertical pier has zero XZ triangle area but must still block flowing water.
	var wall:=mesh_of([Vector3(0,-.3,-4),Vector3(0,.5,-4),Vector3(0,.5,4)])
	var water:={"polygon":PackedVector2Array([Vector2(-1.8,-6),Vector2(1.8,-6),Vector2(1.8,6),Vector2(-1.8,6)]),"plane":Plane(Vector3.UP,0),"source_id":"pier_water"}
	var blocked:=StreamClearance.measure_mesh(wall,Transform3D.IDENTITY,StreamClearance.patches([water],Vector3.ZERO))
	check(blocked.ok and blocked.clearance<0,"zero-area XZ vertical pier remains an obstruction")
	water.plane=Plane(Vector3(-.1,1,0).normalized(),0)
	var sloped:=StreamClearance.measure_mesh(mesh_of([Vector3(-1,.4,-1),Vector3(1,.4,-1),Vector3(1,.4,1)]),Transform3D.IDENTITY,StreamClearance.patches([water],Vector3.ZERO))
	check(sloped.ok and absf(sloped.clearance-.3)<.0001,"sloping water plane uses actual height, not a constant centre level")
	water.plane=Plane(Vector3(-.25,1,0).normalized(),0)
	var high_side:=StreamClearance.measure_mesh(mesh_of([Vector3(-1,.4,-1),Vector3(1,.4,-1),Vector3(1,.4,1)]),Transform3D.IDENTITY,StreamClearance.patches([water],Vector3.ZERO))
	check(high_side.ok and high_side.clearance<StreamClearance.HEIGHT,"sloped water high side can fail while centre remains above limit")
	water.plane=Plane(Vector3.RIGHT,0)
	check(not StreamClearance.measure_mesh(wall,Transform3D.IDENTITY,StreamClearance.patches([water],Vector3.ZERO)).ok,"invalid vertical water plane fails conservatively")
	water.polygon=PackedVector2Array([Vector2.ZERO,Vector2(1,0),Vector2(2,0)])
	var record:={"bridge_mesh":{"camber":0.},"position":[0,0,0]};var original:=record.duplicate(true)
	check(not StreamClearance.fit(record,[water],true).ok and record==original,"degenerate water polygon is rejected before geometry or recipe mutation")

func fixture()->Dictionary:
	var doc:=Doc.new()
	# A distant ordinary navigable bridge remains governed by the old default.
	for side in [-1,1]:doc.add_box("grass",Vector3(470+side*35,-.25,125.5),Vector3(40,.5,24))
	doc.add_box("water",Vector3(470,-2.04,125.5),Vector3(30,.08,60))
	for z:float in [116.35,134.65]:doc.add_box("grass",Vector3(center.x,8.215,z),Vector3(24,.5,12.7))
	doc.add_box("river_bed",Vector3(center.x,6.65,125.5),Vector3(24,.5,3.6))
	water_id=doc.add_box("water",Vector3(center.x,7.4,125.5),Vector3(24,.1,3.6));doc._find(water_id).collision="none"
	var graph:={"nodes":[],"edges":[]}
	for i in 4:
		var p:Vector3=center+axis*[-18.,-5.02,5.02,18.][i]-Vector3.UP*.025
		graph.nodes.append({"id":"n%d"%i,"position":City.xyz(p)})
	for i in 3:graph.edges.append({"id":"e%d"%i,"from":"n%d"%i,"to":"n%d"%(i+1),"width_start":5.,"width_end":5.,"kind":"bridge" if i==1 else "ground"})
	for i in [1,2]:
		var p:Vector3=City.vec(graph.nodes[i].position)+Vector3(15,0,0)
		graph.nodes.append({"id":"east%d"%i,"position":City.xyz(p)})
		graph.edges.append({"id":"branch%d"%i,"from":"n%d"%i,"to":"east%d"%i,"width_start":2.,"width_end":2.,"kind":"ground"})
	var data:=City.resolve({});data.roads=graph;var settings:=Plan.defaults();settings.material_id="pack:default:paving/outdoor_flagstone/material";settings.kerb_enabled=true;settings.kerb_width=.24;settings.kerb_height=.035
	var plan:=Plan.build(graph,settings);check(plan.ok,"T-junction native roads with continuous kerbs planned")
	if not plan.ok:print(plan);return {}
	var paint:=preload("res://scripts/world_editor/road_tools.gd").new();var material:=preload("res://scripts/world_editor/surface_material_library.gd").new().find(settings.material_id);var parts:Array=[]
	for r:Dictionary in plan.records:
		check(paint.paint_default(r,material).ok,"existing road material applied");doc.records.append(r);parts.append({"key":r.road_source,"id":r.uuid,"signature":Surface.signature(r),"paint_signature":City.token(r.surface_paint)})
	data.road_surface={"version":1,"settings":settings,"graph_token":City.token(graph),"parts":parts};doc.map_meta.editor_layout=data
	check(doc.save(path)==OK,"isolated creek and T-road fixture saved")
	return {"doc":doc,"graph":graph}

func old_slabs_absent(binding:Dictionary)->void:
	var mask:Array=preload("res://scripts/world3d/road_bridges.gd").stone_polygon(binding);var area:=0.
	for r:Dictionary in editor._doc.records:
		if not r.has("road_mesh"):continue
		for shape:Dictionary in Foot.record_shapes(r):
			var overlap:=Plan.intersection(Array(shape.polygon).slice(0,-1),mask)
			if not overlap.is_empty():area+=preload("res://scripts/world3d/roof_plan.gd").area(overlap)
	check(area<.001,"converted crossing contains no residual road or kerb across the wet opening")

func crossing_geometry(record:Dictionary,mesh:Mesh)->void:
	var bvh:=TriangleMesh.new();check(bvh.create_from_faces(mesh.get_faces()),"actual generated collision faces form a CPU query mesh")
	var walkable:=true
	for i in 33:
		var x:=lerpf(-2.99,2.99,i/32.)
		for z in [-1.8,0.,1.8]:
			var hit:=bvh.intersect_ray(Vector3(x,.5,z),Vector3.DOWN)
			walkable=walkable and not hit.is_empty() and absf(hit.position.y)<.003
	check(walkable,"flat bridge has continuous actual deck through both directions and walking width")
	var pose:=Transform3D(Basis.from_euler(City.vec(record.rotation)*PI/180),City.vec(record.position));var inverse:=pose.affine_inverse();var flowing:=true
	for i in 9:
		var z:=lerpf(123.71,127.29,i/8.)
		var a:=inverse*Vector3(center.x-10,7.55,z);var b:=inverse*Vector3(center.x+10,7.55,z)
		var hit:=bvh.intersect_ray(a,(b-a).normalized())
		flowing=flowing and (hit.is_empty() or a.distance_to(hit.position)>a.distance_to(b))
	check(flowing,"actual mesh leaves upstream-to-downstream air above all nine wet cross sections; no central support blocks stream")

func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	exact_geometry_cases()
	directory=Paths.cache_directory("stream_bridge_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory);path=directory.path_join("map.gltf")
	if fixture().is_empty():quit(1);return
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32240
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real current 3D HTTP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	for name_:String in ["preview_bridge","generate_bridge"]:
		var schema:Dictionary=definitions.filter(func(d):return d.name==name_)[0].inputSchema
		check(schema.properties.clearance_mode.enum==["navigable","stream"],"HTTP discovery exposes explicit mode for "+name_)
	check(not definitions.any(func(d):return d.name=="paint_tile"),"legacy 2D remains unregistered")
	var old_preview:=await call_tool("preview_bridge",{"id":"ordinary_navigation","prefab_id":"stone_segmental","start":[450,.025,125.5],"end":[490,.025,125.5],"width":7.2,"depth":5.,"camber":.6})
	check(old_preview.get("ok",false) and old_preview.navigation.width==2. and old_preview.navigation.required_height==2.5 and old_preview.navigation.clearance>=2.5,"omitted mode preserves actual navigable two-metre-wide 2.5m clearance")
	var args:={"id":"stream_bridge","prefab_id":"stone_segmental","start":City.xyz(center-axis*3),"end":City.xyz(center+axis*3),"width":6.2,"depth":1.5,"camber":0.,"arches":1,"wing_length":0.,"auto_clearance":false,"clearance_mode":"stream","road_edge_id":"e1"}
	var before:=snapshot();var preview:=await call_tool("preview_bridge",args)
	if not preview.get("ok",false):quit(1);return
	check(preview.navigation.mode=="stream" and preview.navigation.clearance>=.2 and preview.navigation.scope=="entire_overlapped_water_surface" and preview.camber==0.,"low skewed stone arch clears full 3.6m water with no hump")
	check(not preview.trimmed_roads.is_empty() and equivalent(before,snapshot()),"preview identifies actual T-road cuts without mutation")
	var nav:=args.duplicate(true);nav.erase("clearance_mode")
	await reject(nav,"2.5");await reject(args.merged({"clearance_mode":"navigable"},true),"2.5")
	await reject(args.merged({"clearance_mode":"ignore"},true))
	await reject(args.merged({"plan_token":"stale"},true),"过期")
	# Actual wider water reaches the sloping arch flanks and must be rejected,
	# although the centre of the same bridge still has ample clearance.
	await call_tool("set_object_transform",{"id":water_id,"size":[24,.1,3.9]})
	await reject(args,"完整水面");await call_tool("undo")
	await call_tool("set_object_transform",{"id":water_id,"size":[24,.1,5.]})
	await reject(args,"完整水面");await call_tool("undo")
	await call_tool("set_object_transform",{"id":water_id,"rotation":[0,0,2.]})
	await reject(args,"完整水面");await call_tool("undo")
	await call_tool("set_object_transform",{"id":water_id,"position":[center.x,7.55,125.5]})
	await reject(args,"完整水面");await call_tool("undo")
	var protected:String=preview.trimmed_roads[0]
	await call_tool("set_object_properties",{"ids":[protected],"locked":true});await reject(args,"保护");await call_tool("undo")
	var obstacle:String=editor._doc.add_box("block",center+Vector3.UP,Vector3(.2,2,.2));editor._doc._find(obstacle).editor_hidden=true
	await reject(args,"冲突")
	editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=obstacle)
	# All automatic fitting remains constrained by the original 15% slope.
	var low:=args.duplicate(true);low.erase("road_edge_id");low.start[1]-=.465;low.end[1]-=.465;low.auto_clearance=true
	await reject(low,"15%")
	var automatic:=args.duplicate(true);automatic.erase("road_edge_id");automatic.start[1]-=.04;automatic.end[1]-=.04;automatic.auto_clearance=true
	var fitted:=await call_tool("preview_bridge",automatic)
	check(fitted.get("ok",false) and fitted.camber>0 and fitted.max_grade<=.15 and fitted.navigation.clearance>=.2,"automatic fit solves exact whole-water clearance within unchanged grade limit")
	var ui:VBoxContainer=editor._city.panel.bridge_panel;ui.current_id=args.id;ui.road_edge_id="e1"
	var values:=args.duplicate(true)
	for key in ["id","prefab_id","road_edge_id"]:values.erase(key)
	# UI spin boxes intentionally author millimetres. Leave 2 mm at either end
	# rather than testing below the six-metre minimum after skewed rounding.
	values.start=City.xyz(center-axis*3.002);values.end=City.xyz(center+axis*3.002)
	ui.build(values)
	for i in ui.presets.item_count:
		if ui.presets.get_item_metadata(i)=="stone_segmental":ui.presets.select(i)
	ui.show_preview();check(not ui.preview.is_empty() and ui.request().clearance_mode=="stream" and "非通航" in ui.info.text,"UI mode and actual preview use same shared clearance business")
	if ui.preview.is_empty():print("UI_DIAGNOSTIC ",ui.info.text," ",ui.request())
	if not ui.preview.is_empty():
		ui.apply();check(editor._doc._find(args.id).get("bridge_mesh",{}).get("clearance_mode","")=="stream","UI applies the same atomic native stream bridge")
		await call_tool("undo");check(equivalent(before,snapshot()),"UI application undo restores original T-junction")
	ui.invalidate();var count:int=editor._doc._undo.size()
	preview=await call_tool("preview_bridge",args)
	await call_tool("generate_bridge",args.merged({"plan_token":preview.plan_token}))
	check(editor._doc._undo.size()==count+1,"bridge, T-road cut and binding form one transaction")
	var bridge:Dictionary=editor._doc._find(args.id);var binding:Dictionary=City.resolve(editor._doc.map_meta).roads.edges.filter(func(e):return e.id=="e1")[0].stone_bridge
	check(bridge.bridge_mesh.clearance_mode=="stream" and bridge.get("prefab_locked",false) and bridge.has("house_prefab"),"mode persists in native automatically frozen bridge")
	old_slabs_absent(binding)
	var after:=snapshot();await call_tool("undo");check(equivalent(before,snapshot()),"undo restores original T-road surfaces and graph")
	await call_tool("redo");check(equivalent(after,snapshot()),"redo restores complete bridge and source identity")
	await call_tool("save_world");var saved:=snapshot();await call_tool("open_world",{"path":path})
	check(equivalent(saved,snapshot()),"native bridge mode, PBR, cuts and metadata survive save/reopen")
	bridge=editor._doc._find(args.id);ui.load_record(bridge);check(ui.request().clearance_mode=="stream","UI restores creek mode from saved bridge")
	var measured:=Clearance.fit(bridge.duplicate(true),editor._doc.records,false);check(measured.ok and measured.clearance>=.2,"reopened frozen source recipe retains exact wet clearance")
	var mesh:=Meshes.new().build(bridge);var triangles:=0;var textured:=true
	for i in mesh.get_surface_count():
		triangles+=mesh.surface_get_array_index_len(i)/3;var mat:StandardMaterial3D=mesh.surface_get_material(i);textured=textured and mat.albedo_texture!=null and mat.normal_enabled and mat.normal_texture!=null
	check(mesh.get_surface_count()==3 and textured,"existing three-material PBR pipeline retained")
	crossing_geometry(bridge,mesh)
	var ordinary:=bridge.duplicate(true);ordinary.bridge_mesh.erase("clearance_mode")
	var unchanged:=Meshes.new().build(ordinary)
	check(unchanged.get_faces()==mesh.get_faces() and unchanged.get_meta("bridge_lods")==mesh.get_meta("bridge_lods"),"clearance purpose does not alter bridge geometry, collision or LOD")
	var report:={"scope":"Shared non-navigable stream clearance; current bridge kit unchanged. Isolated native candidate, not formal town publication.","map":path,"map_sha256":FileAccess.get_sha256(path),"source_path":bridge.asset_path,"source_sha256":FileAccess.get_sha256(bridge.asset_path),"frozen_sha256":bridge.house_prefab.sha256,"frozen_decoded_bytes":bridge.house_prefab.length,"triangles":triangles,"surfaces":mesh.get_surface_count(),"navigation":measured,"request":args,"failures":failed,"resource_review":"Existing PBR/LOD source unchanged; generated geometry measured and native save/reopen checked.","visual_review":"Pending coordinated background GPU near/mid/far and actual town shoulder review.","rss_vram":"Not measured"}
	FileAccess.open(OUT+"/stream_bridge_http_review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	editor._mcp.stop();editor.queue_free();await settle()
	print("STREAM_BRIDGE_HTTP_FINISHED failures=",failed);quit(1 if failed else 0)
