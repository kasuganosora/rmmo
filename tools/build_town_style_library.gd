extends "res://tools/build_house_playground.gd"
## Textured reference families, authored once and frozen before town placement.
const STYLE_MAP="D:/code/rmmo_runtime/cache/world3d/town_styles_20261005/map.gltf"
func run()->void:
	create_timer(1800).timeout.connect(func():quit(2));Engine.max_fps=30
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var skyline:bool="--skyline" in OS.get_cmdline_user_args()
	review_directory="town_skyline_styles_20261005" if skyline else "town_styles_20261005"
	DEST="D:/code/rmmo_runtime/cache/world3d/town_skyline_styles_20261005/map.gltf" if skyline else STYLE_MAP;rpc_timeout_ms=240000
	var presets:Array=Blueprint.town_presets().filter(func(p):return p.id in ["town_tall_shop","town_tall_eaves_shop","town_compact_home"]) if skyline else Blueprint.town_presets()
	var doc=Doc.new();doc.map_meta.map_name="参考街区 · 房型库"
	doc.map_meta.spawn=[0,.95,-42];doc.map_meta.environment={"interior_cutaway":false};doc.map_meta.building_instances={}
	var ground_id:String=doc.add_box("ground",Vector3(0,-.25,0),Vector3(180,.5,115));assignments[ground_id]="street"
	for i in presets.size():
		var preset:Dictionary=presets[i];var plan:=Blueprint.generate(preset.parameters)
		check(plan.ok,"valid reference style "+preset.id)
		if not plan.ok:print(plan);quit(1);return
		var at:=Vector3((i%4)*38-57,0,floori(i/4.)*48-22);var id:String="style_"+preset.id
		var value:={"version":Blueprint.VERSION,"parameters":plan.parameters,"position":Blueprint.arr(at),"yaw":0.0,"parts":{},"signatures":{}}
		for r:Dictionary in plan.records:
			r.uuid="obj_%d"%doc._next;doc._next+=1;r.building.id=id;r.position=Blueprint.arr(Blueprint.vec(r.position)+at)
			r.editor_group=id;r.editor_group_name=preset.name
			value.parts[r.building.part]=r.uuid;value.signatures[r.building.part]=Blueprint.geometry_signature(r);doc.records.append(r)
		doc.map_meta.building_instances[id]=value
		houses.append({"preset":preset.id,"name":preset.name,"parameters":plan.parameters,"position":Blueprint.arr(at),"building_id":id,"number":i+1})
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=DEST;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=DEST.get_base_dir().path_join("drafts");root.add_child(editor);await settle();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP style library")
	var discovery:=await rpc("tools/list")
	check(discovery.result.tools.any(func(t):return t.name=="list_building_templates"),"3D template discovery")
	var templates:=await call_tool("list_building_templates")
	check(equivalent(templates.town_presets,Blueprint.town_presets()),"HTTP and UI share all reference presets")
	var before:=doc.recovery_snapshot();var history:int=doc._undo.size()
	await call_tool("generate_buildings",{"parameters":{"width":-1},"placements":[{"position":[0,0,0]}]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid generation has no side effects")
	await call_tool("set_environment",{"preset":"day","sun_rotation":[-43,145,0],"sun_energy":1.15,"ambient_energy":.58,"sun_shadows":true,"ambient_occlusion":true})
	await paint_gallery()
	if failed:quit(1);return
	# Paint while authoring, then compile through the same UI/MCP bake operation.
	for house:Dictionary in houses:
		var result:=await call_tool("bake_building",{"id":house.building_id})
		if not result.get("ok",false):quit(1);return
		var value:Dictionary=doc.map_meta.building_instances[house.building_id]
		check(value.baked and value.parts.size()<110,"bounded fixed components "+house.preset+" count="+str(value.parts.size()))
		if house==houses[0]:
			await call_tool("undo");check(not doc.map_meta.building_instances[house.building_id].get("baked",false),"undo bake")
			await call_tool("redo");check(doc.map_meta.building_instances[house.building_id].baked,"redo bake")
		doc._undo.clear();doc._redo.clear()
	var expected:Array=doc.records.duplicate(true)
	await call_tool("save_world")
	await call_tool("open_world",{"path":DEST});doc=editor._doc
	check(equivalent(doc.records,expected),"native save/reopen all textured fixed styles")
	await render_gallery()
	var report:={"failures":failed,"houses":houses,"map_path":DEST,"sha256":FileAccess.get_sha256(DEST),"records":doc.records.size()}
	var file:=FileAccess.open(Review.review_path(review_directory+"/showcase.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	editor.free();print("TOWN_STYLE_LIBRARY failures=",failed);quit(1 if failed else 0)
