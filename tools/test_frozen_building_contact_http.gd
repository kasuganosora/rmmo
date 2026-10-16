extends "res://tools/test_world3d_mcp.gd"
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Contact=preload("res://scripts/world3d/frozen_placement_contact.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Market=preload("res://tools/axel_market_layout_content.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
var checks:Array=[]
func check(ok:bool,label_:String)->void:
	checks.append({"check":label_,"passed":ok});super.check(ok,label_)
func frozen(parts:Array,id_:String)->Dictionary:
	var records:Array=[]
	for item:Array in parts:
		records.append({"uuid":"source_"+str(records.size()),"kind":"box","position":item[0],"rotation":[0.,0.,0.],"size":item[1],"surface_id":"block","color":[.5,.5,.5],"collision":"block","building":{"id":id_,"part":"main/wall_"+str(records.size()),"role":"wall","floor":0,"floor_y":0.}})
	var result:=Frozen.bake(records);var record:Dictionary=result.records[0]
	record.erase("building");record.uuid=id_;record.fortification={"id":id_,"part":"baked","role":"prefab"};return record
func reject_unchanged(name_:String,args:Dictionary,label_:String)->void:
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	await call_tool(name_,args,false)
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),label_)
func same_authored_state(a:Dictionary,b:Dictionary)->bool:
	# Native undo deliberately never reuses issued UUID sequence numbers.
	var left:=a.duplicate(true);var right:=b.duplicate(true);left.erase("next");right.erase("next")
	return equivalent(left,right) and int(b.next)>=int(a.next)
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=120000
	var directory:=Paths.external_root().path_join("__frozen_building_contact_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":"frozen_building_test","name":"Frozen building test fixture"}))
	var path:=directory.path_join("map.gltf");var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.2,0),Vector3(80,.4,80))
	var wall:=frozen([[[ -12.,5.,0.],[2.,10.,30.]],[[0.,5.,-12.],[26.,10.,2.]]],"frozen_L_wall");doc.records.append(wall)
	var p:={"width":9.,"depth":12.,"floors":1,"rooms_per_floor":1,"front_canopy":false,"shutters":false,"chimney":false}
	var source:=B.generate(p);check(source.ok,"small real generated house fixture")
	if not source.ok:print(source);quit(1);return
	var occupancy:=Foot.components(source.records,Vector3.ZERO,Basis.IDENTITY);var broad:=Foot.record_shape(wall)
	check(Foot.batches_overlap(occupancy,[broad]),"fixture truly overlaps frozen combined bounding box")
	check(not Contact.intersects(wall,occupancy,broad,{}),"L shaped frozen empty corner stays clear")
	var shifted:Dictionary=wall.duplicate(true);shifted.position[0]+=10.
	check(Contact.intersects(shifted,occupancy,Foot.record_shape(shifted),{}),"actual frozen wall intersects occupied building volume")
	var solid:=frozen([[[0.,5.,0.],[40.,20.,40.]]],"solid")
	check(Contact.intersects(solid,occupancy,Foot.record_shape(solid),{}),"building fully enclosed by frozen solid remains blocked")
	var beam:=frozen([[[0.,3.,0.],[20.,1.,2.]]],"beam")
	check(Contact.intersects(beam,occupancy,Foot.record_shape(beam),{}),"real low beam remains blocked")
	var invalid:=wall.duplicate(true);invalid.house_prefab.sha256="invalid"
	check(Contact.intersects(invalid,occupancy,broad,{}),"invalid frozen payload stays conservative")
	var fixture:=wall.duplicate(true);fixture.fixture={}
	check(Contact.intersects(fixture,occupancy,broad,{}),"articulated frozen fixture keeps full-sweep protection")
	var house_owner:=wall.duplicate(true);house_owner.building={"id":"existing_house"}
	check(Contact.intersects(house_owner,occupancy,broad,{}),"existing building interiors stay occupied and cannot contain a new house")
	var mirrored:Array=occupancy.duplicate(true)
	for shape:Dictionary in mirrored:shape.polygon.reverse()
	check(not Contact.intersects(wall,mirrored,broad,{}),"convex footprint orientation does not change narrow phase")
	var rotated:=wall.duplicate(true);var basis:=Basis(Vector3.UP,deg_to_rad(37.));var offset:=Vector3(30,0,20)
	rotated.position=B.arr(offset+basis*B.vec(wall.position));rotated.rotation=[0.,37.,0.]
	check(not Contact.intersects(rotated,Foot.components(source.records,offset,basis),Foot.record_shape(rotated),{}),"rotated frozen box uses actual pose and keeps its empty corner")
	check(doc.save(path)==OK,"native temporary fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var socket:=TCPServer.new();port=31990
	while socket.listen(port,"127.0.0.1")!=OK:port+=1
	socket.stop();check(editor.start_mcp(port).ok,"real current 3D HTTP loopback")
	var discovery:=await rpc("tools/list");var names:Array=discovery.result.tools.map(func(t):return t.name)
	check(names.has("preview_buildings") and names.has("generate_buildings") and names.has("place_asset") and not names.has("paint_tile"),"current 3D generation and library tools discovered")
	var args:={"parameters":p,"placements":[{"position":[0.,0.,0.]}]};var before:=doc.recovery_snapshot()
	var preview:=await call_tool("preview_buildings",args)
	check(equivalent(preview,editor._buildings.summary(editor._buildings.prepare(args))),"UI and MCP share precise frozen placement validation")
	check(equivalent(before,doc.recovery_snapshot()),"preview has no side effect")
	var intact_payload:Dictionary=doc._find("frozen_L_wall").house_prefab.duplicate(true)
	doc._find("frozen_L_wall").house_prefab.sha256="invalid"
	await reject_unchanged("generate_buildings",args,"HTTP corrupted frozen payload fails closed without side effects")
	doc._find("frozen_L_wall").house_prefab=intact_payload
	await reject_unchanged("generate_buildings",{"parameters":p,"placements":[{"position":[-10.,0.,0.]}]},"true frozen wall collision rejects without changes or undo entry")
	await reject_unchanged("generate_buildings",{"parameters":{"floors":0},"placements":[{"position":[0.,0.,0.]}]},"invalid generation schema is atomic")
	var history:int=doc._undo.size();var made:=await call_tool("generate_buildings",args)
	if not made.get("ok",false):editor._mcp.stop();quit(1);return
	check(doc._undo.size()==history+1,"valid generation is one native transaction")
	var generated:=doc.recovery_snapshot();var member:String=doc.map_meta.building_instances[made.building_ids[0]].parts.values()[0]
	await call_tool("select_objects",{"ids":[member]})
	var saved:=await call_tool("save_prefab",{"name":"Frozen corner house","pack_root":directory})
	await call_tool("undo");check(same_authored_state(before,doc.recovery_snapshot()),"generation undo restores exact authored state and preserves monotonic IDs")
	await call_tool("redo");check(equivalent(generated,doc.recovery_snapshot()),"generation redo restores exact frozen house")
	await call_tool("undo")
	await reject_unchanged("place_asset",{"asset_id":saved.asset_id,"position":[-10.,0.,0.]},"complete library prefab true collision rejects atomically")
	history=doc._undo.size();await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[0.,0.,0.]})
	check(doc._undo.size()==history+1 and doc.map_meta.building_instances.size()==1,"complete library house allowed in true empty corner with one transaction")
	var placed:=doc.recovery_snapshot()
	await call_tool("undo");check(same_authored_state(before,doc.recovery_snapshot()),"library undo exact authored state and monotonic IDs")
	await call_tool("redo");check(equivalent(placed,doc.recovery_snapshot()),"library redo exact")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(equivalent(placed.records,doc.records) and equivalent(placed.map_meta,doc.map_meta),"native save and reopen retain precise placement and building semantics")
	await reject_unchanged("set_object_transform",{"id":"frozen_L_wall","position":[0.,0.,0.]},"frozen authoring lock remains enforced")
	# Exercise the actual market graph request through HTTP in this temporary
	# document. No authored surface manifest is copied, so this is topology only.
	var snapshot:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/wall_regenerated_records.json"))
	var source_doc:=Doc.new();source_doc.records=snapshot.records;source_doc.map_meta=snapshot.map_meta
	var prepared:=Market.prepare(source_doc);check(prepared.ok,"current market sources and native input preparation")
	var request:=Market.road_request(source_doc,prepared)
	check(not request.has("error"),"commercial spurs produce precise native graph request")
	var original:Dictionary=City.resolve(source_doc.map_meta).roads
	doc.map_meta.editor_layout=City.defaults();doc.map_meta.editor_layout.roads=original.duplicate(true);editor._city.refresh()
	var graph_before:=doc.recovery_snapshot();var graph_result:=await call_tool("update_road_graph",request)
	var graph:Dictionary=City.resolve(doc.map_meta).roads;var nodes:Dictionary={};var adjacency:Dictionary={}
	for n:Dictionary in graph.nodes:nodes[n.id]=n;adjacency[n.id]=[]
	for e:Dictionary in graph.edges:adjacency[e.from].append(e.to);adjacency[e.to].append(e.from)
	var seen:Dictionary={};var queue:Array=["axel_n_5f5f7b16e16f"]
	while not queue.is_empty():
		var id_:String=queue.pop_front()
		if seen.has(id_):continue
		seen[id_]=true;queue.append_array(adjacency[id_])
	for key:String in ["commercial_apothecary","commercial_general"]:
		var junction:="market_access_main_"+key
		check(adjacency[junction].size()==3 and seen.has("market_access_door_"+key),"commercial entry really shares a degree-three main-road junction: "+key)
	check(not graph_result.diagnostics.any(func(d):return str(d.get("edges",[])).contains("market_access_")),"commercial spurs have no unconnected crossing diagnostics")
	var old_edge:Dictionary=original.edges.filter(func(e):return e.id=="axel_e_be73f25d73ff")[0]
	var split_edges:Array=graph.edges.filter(func(e):return e.id==old_edge.id or e.id.begins_with("market_split_"+old_edge.id))
	var properties:=old_edge.duplicate(true)
	for key:String in ["id","from","to","width_start","width_end"]:properties.erase(key)
	var intact:=split_edges.size()==3
	for e:Dictionary in split_edges:
		var copy:=e.duplicate(true)
		for key:String in ["id","from","to","width_start","width_end"]:copy.erase(key)
		intact=intact and equivalent(copy,properties) and e.width_start==5. and e.width_end==5.
	check(intact and split_edges[0].from==old_edge.from and split_edges[-1].to==old_edge.to,"split preserves source edge metadata, 5m width and both outer endpoint identities")
	var graph_after:=doc.recovery_snapshot()
	await call_tool("undo");check(same_authored_state(graph_before,doc.recovery_snapshot()),"commercial graph update undo exact")
	await call_tool("redo");check(same_authored_state(graph_after,doc.recovery_snapshot()),"commercial graph update redo exact")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(equivalent(City.resolve(editor._doc.map_meta).roads,graph),"commercial shared-node graph survives native save reopen")
	FileAccess.open(OUT+"/market_road_connection_probe.json",FileAccess.WRITE).store_string(JSON.stringify({"source_snapshot_sha256":FileAccess.get_sha256(OUT+"/wall_regenerated_records.json"),"plan_sha256":FileAccess.get_sha256(Market.PLAN),"request":request,"split_edges":split_edges,"diagnostics":graph_result.diagnostics,"reachable_nodes":seen.keys(),"temporary_fixture":path},"\t"))
	editor._mcp.stop();editor.queue_free();await settle()
	FileAccess.open(OUT+"/frozen_building_contact_http.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failed,"fixture":path,"phase":"complete","scope":"shared UI/current 3D MCP frozen building placement narrow phase; temporary map only"},"\t"));quit(1 if failed else 0)
