extends "res://tools/test_world3d_mcp.gd"
const Layer=preload("res://scripts/world3d/terrain_river_layer.gd")
const River=preload("res://scripts/world_editor/terrain_river_tools.gd")
const T=preload("res://scripts/world3d/terrain_surface.gd")

func assert_atomic(before:Dictionary,history:int,label:String)->void:
	check(equivalent(before,editor._doc.recovery_snapshot()) and editor._doc._undo.size()==history,label)

func malformed_layers(layer:Dictionary)->void:
	check(Layer.valid({"terrain_rivers":[layer]}),"generated layer passes shared metadata validator")
	check(Layer.valid(JSON.parse_string(JSON.stringify({"terrain_rivers":[layer]}))),"JSON numeric roundtrip remains valid")
	var bad:=layer.duplicate(true);bad.request={}
	check(not Layer.valid({"terrain_rivers":[bad]}),"missing persisted request rejected before UI access")
	bad=layer.duplicate(true);bad.request.id="other"
	check(not Layer.valid({"terrain_rivers":[bad]}),"request identity must match owning layer")
	bad=layer.duplicate(true);bad.terrains.append(bad.terrains[0].duplicate(true))
	check(not Layer.valid({"terrain_rivers":[bad]}),"duplicate terrain snapshots rejected")
	bad=layer.duplicate(true);bad.terrains[0].before.position[0]+=1.
	check(not Layer.valid({"terrain_rivers":[bad]}),"snapshots cannot restore a different terrain transform")
	bad=layer.duplicate(true);bad.terrains[0].before.terrain_mesh.holes[0]=true
	check(not Layer.valid({"terrain_rivers":[bad]}),"snapshots cannot rewrite unrelated holes")
	bad=layer.duplicate(true);bad.water[0].signature="z".repeat(64)
	check(not Layer.valid({"terrain_rivers":[bad]}),"invalid water signature rejected")
	bad=layer.duplicate(true);bad.water[0].id="unrelated_prop"
	check(not Layer.valid({"terrain_rivers":[bad]}),"restoration cannot own an unrelated prop ID")
	var current:Dictionary=layer.terrains[0].after.duplicate(true)
	current.terrain_mesh.heights.resize(1)
	check(not Layer.restore(current,layer.terrains[0].before,layer.terrains[0].after).ok,"malformed live grid fails without indexing missing samples")

func run()->void:
	create_timer(360).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	var directory:=Paths.cache_directory("river_boundary_review_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new();check(doc.save(path)==OK,"isolated review fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31290
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"review uses real HTTP MCP")
	var names:Array=(await rpc("tools/list")).result.tools.map(func(t):return t.name)
	check(["generate_terrain_river","preview_terrain_river","remove_terrain_river","list_terrain_rivers"].all(func(n):return n in names),"river lifecycle tools discovered")
	var ground:=await call_tool("create_terrain",{"center":[0,0,0],"width":32.,"depth":32.,"cell_size":1.})
	var river:={"id":"review_a","terrain_ids":[ground.id],"points":[[-12,0],[12,0]],"width":4.,"bank_width":2.,"water_level":-.5,"depth":1.5,"natural_materials":false}
	await call_tool("generate_terrain_river",river)
	malformed_layers(editor._doc.map_meta.terrain_rivers[0])
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var crossing:=river.duplicate(true);crossing.id="review_crossing";crossing.points=[[0,-12],[0,12]]
	await call_tool("preview_terrain_river",crossing,false);await call_tool("generate_terrain_river",crossing,false)
	assert_atomic(before,history,"equal-height overlap cannot borrow another river's owned samples")
	var separate:=river.duplicate(true);separate.id="review_separate";separate.points=[[-12,10],[12,10]]
	await call_tool("generate_terrain_river",separate)
	await call_tool("remove_terrain_river",{"id":river.id})
	check(absf(T.sample(editor._doc._find(ground.id),Vector3(0,0,0)))<.001 and T.sample(editor._doc._find(ground.id),Vector3(0,0,10))< -1.,"disjoint river removal preserves other owned river bed")
	await call_tool("undo");await call_tool("undo")
	assert_atomic(before,history,"both river transactions undo to exact pre-overlap state")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	before=editor._doc.recovery_snapshot();history=editor._doc._undo.size()
	await call_tool("generate_terrain_river",crossing,false);assert_atomic(before,history,"overlap guard survives save and reopen")
	await call_tool("set_object_properties",{"ids":[editor._doc.map_meta.terrain_rivers[0].water[0].id],"locked":true})
	before=editor._doc.recovery_snapshot();history=editor._doc._undo.size()
	await call_tool("remove_terrain_river",{"id":river.id},false);assert_atomic(before,history,"locked water rejects complete restoration atomically");await call_tool("undo")
	await call_tool("sculpt_terrain",{"id":ground.id,"mode":"raise","points":[[12,14]],"radius":1.,"strength":.2})
	var unowned:float=T.sample(editor._doc._find(ground.id),Vector3(12,0,14))
	var original:=river.duplicate(true);river.points=[[-12,-8],[12,-8]]
	await call_tool("generate_terrain_river",river)
	check(absf(T.sample(editor._doc._find(ground.id),Vector3(0,0,0)))<.001 and T.sample(editor._doc._find(ground.id),Vector3(0,0,-8))< -1. and T.sample(editor._doc._find(ground.id),Vector3(12,0,14))==unowned,"same-ID reroute preserves unrelated sculpt")
	await call_tool("remove_terrain_river",{"id":river.id})
	check(editor._doc.map_meta.terrain_rivers.is_empty() and T.sample(editor._doc._find(ground.id),Vector3(12,0,14))==unowned,"remove restores owned bed and preserves unrelated sculpt")
	# Persist an actual minimal HTTP request, then change unrelated panel inputs.
	# Loading it must reconstruct backend defaults, not reuse those stale inputs.
	var minimal:={"id":"minimal","terrain_ids":[ground.id],"points":[[-8,0],[8,0]],"water_level":-.5,"natural_materials":false}
	await call_tool("generate_terrain_river",minimal)
	var panel:Node=editor._terrain_panel.river_panel
	panel.settings.fields.id.text=minimal.id;panel.settings.fields.width.value=40.;panel.settings.fields.bank_width.value=12.;panel.settings.fields.depth.value=9.;panel.settings.fields.curved.button_pressed=false
	panel.load_existing()
	check(panel.args().width==8. and panel.args().bank_width==4. and panel.args().depth==2. and panel.args().curved,"loading a minimal saved request restores canonical defaults")
	before=editor._doc.recovery_snapshot();history=editor._doc._undo.size()
	var corrupt:Dictionary=editor._doc.map_meta.terrain_rivers[0].request;editor._doc.map_meta.terrain_rivers[0].request={}
	check(not River.catalog(editor).ok and not River.apply(editor,{"id":minimal.id},false,true).ok,"corrupt persisted request fails safely in UI and mutating API")
	editor._doc.map_meta.terrain_rivers[0].request=corrupt
	assert_atomic(before,history,"invalid metadata path leaves records and history intact")
	# Pure material ownership test avoids decoding PBR images for this contract.
	var owned:Dictionary=editor._doc.map_meta.terrain_rivers[0].duplicate(true)
	owned.terrains[0].after.terrain_depth_blend={"water_level":-.5}
	var mock:={"touched":{ground.id:{0:true}},"entries":[{"record":owned.terrains[0].after}]}
	check(not River.ownership_conflict(mock,[owned],{"id":"second","natural_materials":true}).is_empty(),"equal shared terrain material cannot acquire ambiguous restoration ownership")
	check(River.ownership_conflict(mock,[owned],{"id":"second","natural_materials":false}).is_empty(),"unowned disjoint river may retain existing shared material")
	var live:Dictionary=editor._doc._find(ground.id)
	var no_bed:=live.duplicate(true);no_bed.terrain_mesh.heights.fill(0.)
	check(not River.restoration_conflict(editor,"older",[owned],{ground.id:no_bed}).is_empty(),"legacy equal-height dependency blocks removal of earlier bed")
	var preserved:=live.duplicate(true)
	check(River.restoration_conflict(editor,"older",[owned],{ground.id:preserved}).is_empty(),"restoring exact surface required by another layer is safe")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	await call_tool("remove_terrain_river",{"id":minimal.id})
	check(editor._doc.map_meta.terrain_rivers.is_empty(),"validated snapshots still restore after final reopen")
	var left:=await call_tool("create_terrain",{"center":[60,0,0],"width":16.,"depth":16.,"cell_size":2.})
	var right:=await call_tool("create_terrain",{"center":[76,0,0],"width":16.,"depth":16.,"cell_size":1.})
	var mixed:={"id":"mixed_river","terrain_ids":[left.id],"points":[[56,0],[80,0]],"width":4.,"bank_width":2.,"water_level":-.5,"depth":1.5,"natural_materials":false}
	await call_tool("generate_terrain_river",mixed)
	var continuous:=true
	for z in range(-8,9):
		continuous=continuous and absf(T.sample(editor._doc._find(left.id),Vector3(8,0,z))-T.sample(editor._doc._find(right.id),Vector3(-8,0,z)))<.0001
	check(continuous,"river joins and validates all samples across mixed grid neighbours")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	await call_tool("remove_terrain_river",{"id":mixed.id})
	check(absf(T.sample(editor._doc._find(left.id),Vector3(8,0,0)))<.001 and absf(T.sample(editor._doc._find(right.id),Vector3(-8,0,0)))<.001,"mixed-grid layer removes continuously after reopen")
	print("RIVER_BOUNDARY_REVIEW_ARTIFACTS ",directory)
	editor._mcp.stop();editor.queue_free();await settle();print("RIVER_BOUNDARY_REVIEW_FINISHED failures=",failed);quit(0 if failed==0 else 1)
