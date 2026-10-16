extends "res://tools/test_world3d_mcp.gd"
const Contact=preload("res://scripts/world_editor/terrain_bridge_contact.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Clearance=preload("res://scripts/world_editor/bridge_clearance.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
var terrain_id:String
var bridge_id:="creek_crossing"
func snapshot()->Dictionary:
	var value:Dictionary=editor._doc.recovery_snapshot();value.erase("next");return value
func rejected(tool:String,args:Dictionary,label:String)->void:
	var before:=snapshot();var history:int=editor._doc._undo.size()
	var result:=await call_tool(tool,args,false)
	check(result.get("conflicts",[]).has(bridge_id),label+" identifies actual protected bridge")
	check(equivalent(before,snapshot()) and history==editor._doc._undo.size(),label+" is atomic")
func flat(point:Array,y:float)->Dictionary:
	return {"id":terrain_id,"mode":"flatten","shape":"rectangle","points":[point],"plot_width":1.,"plot_depth":1.,"blend_margin":.5,"target_height":y,"strength":1.,"cross_tiles":true}
func transformed_case(bridge:Dictionary)->void:
	for scale_:Vector3 in [Vector3(1.3,1.3,1.3),Vector3(1.8,.9,.55)]:
		var ground:Dictionary=editor._doc._find(terrain_id).duplicate(true)
		var crossing:=bridge.duplicate(true)
		var pose:=Transform3D(Basis(Vector3.UP,deg_to_rad(37))*Basis.from_scale(scale_),Vector3(1300,4,-900))
		for r:Dictionary in [ground,crossing]:
			r.position=City.xyz(pose*City.vec(r.position));r.size=City.xyz(City.vec(r.size)*scale_);r.rotation=[0,37,0]
		var p:Vector3=pose*Vector3(-.4,0,0)
		var lowered:=Terrain.stroke(ground,{"id":ground.uuid,"mode":"lower","points":[[p.x,p.z]],"radius":.6,"strength":.05})
		check(lowered.ok and lowered.changed and Contact.preserves(ground,lowered,crossing,{}),"yaw, scale "+str(scale_)+" and distant coordinates preserve below-arch excavation")
		var footing:Vector3=pose*Vector3(-2.5,0,0)
		var hole:=Terrain.stroke(ground,{"id":ground.uuid,"mode":"hole","points":[[footing.x,footing.z]],"radius":1.})
		check(hole.ok and hole.changed and not Contact.preserves(ground,hole,crossing,{}),"transformed complete foundation coverage rejects off-centre footing holes")
		# Compare against the actual shared frozen-prefab Node3D, rather than a
		# duplicated expected matrix formula. Its scale is local to its rotation.
		var node:=preload("res://scripts/world3d/house_prefab.gd").visual(crossing,false)
		var original:=bridge.duplicate(true);original.position=[0,0,0];original.rotation=[0,0,0];original.size=[1,1,1]
		var local:=Contact.geometry(original,{});var transformed:=Contact.geometry(crossing,{})
		var same:bool=local.bases.size()==transformed.bases.size()
		for i in local.bases.size():
			for vertex:Vector2 in local.bases[i].polygon:
				var expected:Vector3=node.transform*Vector3(vertex.x,preload("res://scripts/world_editor/terrain_prop_contact.gd").height(local.bases[i].point,local.bases[i].normal,vertex),vertex.y)
				var best:=INF
				for actual:Vector2 in transformed.bases[i].polygon:best=minf(best,actual.distance_to(Vector2(expected.x,expected.z)))
				same=same and best<.0002
		check(same,"every projected foundation vertex matches actual Frozen.visual Node3D transform for "+str(scale_))
		node.free()
func cache_invalidation(bridge:Dictionary,directory:String)->void:
	var copied:=bridge.duplicate(true);copied.asset_path=directory.path_join("contact_source.glb")
	check(DirAccess.copy_absolute(bridge.asset_path,copied.asset_path)==OK,"source replacement test copies only into its isolated cache directory")
	var cache:Dictionary={};var initial:=Contact.geometry(copied,cache)
	check(not initial.is_empty(),"isolated source copy proves the saved foundation geometry")
	var bytes:=FileAccess.get_file_as_bytes(copied.asset_path);var count:=bytes.decode_u32(12)
	var gltf:Dictionary=JSON.parse_string(bytes.slice(20,20+count).get_string_from_utf8());var changed:=false
	for node:Dictionary in gltf.nodes:
		if node.get("name")=="abutment":
			var p:Array=node.get("translation",[0.,0.,0.]);p[0]+=.125;node.translation=p;changed=true
	check(changed,"test changes actual source abutment geometry, not metadata only")
	var json:=JSON.stringify(gltf).to_utf8_buffer()
	while json.size()%4:json.append(32)
	var replacement:=bytes.slice(0,12);replacement.resize(20);replacement.encode_u32(12,json.size());replacement.encode_u32(16,0x4e4f534a)
	replacement.append_array(json);replacement.append_array(bytes.slice(20+count));replacement.encode_u32(8,replacement.size())
	var file:=FileAccess.open(copied.asset_path,FileAccess.WRITE);file.store_buffer(replacement);file.close()
	check(Contact.geometry(copied,cache).is_empty() and cache.size()==2,"same-path changed GLB SHA invalidates operation cache and refuses stale source proof")
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	var directory:=Paths.cache_directory("terrain_bridge_contact_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");check(Doc.new().save(path)==OK,"isolated bridge excavation map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32480
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real 3D HTTP bridge contact fixture starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(t):return t.name=="generate_terrain_river") and definitions.any(func(t):return t.name=="sculpt_terrain"),"existing 3D river and brush tools remain discoverable")
	var terrain:=await call_tool("create_terrain",{"center":[-6,8.465,0],"width":12.,"depth":24.,"cell_size":.5})
	terrain_id=terrain.id
	var east:=await call_tool("create_terrain",{"center":[6,8.465,0],"width":12.,"depth":24.,"cell_size":.5})
	# The bridge is intentionally built before digging: old soil occupies the
	# opening. Treating the old swept bounding box as solid forbids this workflow.
	var args:={"id":bridge_id,"prefab_id":"stone_segmental","start":[-3,8.49,0],"end":[3,8.49,0],"width":6.2,"depth":1.5,"camber":0.,"arches":1,"wing_length":0.,"auto_clearance":false,"clearance_mode":"stream"}
	await call_tool("generate_bridge",args)
	var bridge:Dictionary=editor._doc._find(bridge_id)
	var mesh:=Contact.geometry(bridge,{})
	check(not mesh.is_empty() and mesh.bases.size()==4,"actual frozen source has both complete native abutment bases")
	if mesh.is_empty():quit(1);return
	var before:=snapshot();var history:int=editor._doc._undo.size()
	var river:={"id":"under_bridge","terrain_ids":[terrain_id],"points":[[0,-10],[0,10]],"width":3.6,"bank_width":1.,"water_level":7.45,"depth":.5,"curved":false,"natural_materials":false}
	var generated:=await call_tool("generate_terrain_river",river)
	if not generated.get("ok",false):quit(1);return
	var after:=snapshot()
	check(not equivalent(before.records.filter(func(r):return r.uuid==east.id),after.records.filter(func(r):return r.uuid==east.id)),"river edits both adjacent terrain tiles across the bridge opening")
	check(editor._doc._undo.size()==history+1 and equivalent(before.records.filter(func(r):return r.uuid==bridge_id),after.records.filter(func(r):return r.uuid==bridge_id)),"river digs old solid soil under arch without modifying bridge, in one transaction")
	var flow:=Clearance.fit(bridge.duplicate(true),editor._doc.records,false)
	check(flow.ok and flow.get("clearance",-1)>=.2,"generated whole water surface fits the actual stone opening")
	await call_tool("undo");check(equivalent(before,snapshot()),"undo restores uncut soil and removes derived water")
	await call_tool("redo");check(equivalent(after,snapshot()),"redo restores complete river layer and unchanged native bridge")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(equivalent(after.records,editor._doc.records),"native save/reopen retains cut bed and frozen bridge")
	await rejected("sculpt_terrain",flat([2.5,0],6.5),"lowering actual abutment below its foundation")
	await rejected("sculpt_terrain",{"id":terrain_id,"mode":"hole","points":[[2.5,0]],"radius":.8,"cross_tiles":true},"hole under actual abutment")
	await rejected("sculpt_terrain",flat([0,0],8.),"backfilling the open arch")
	await rejected("sculpt_terrain",flat([2.5,0],9.),"raising soil through foundation and deck")
	# A deeper/wider natural river must also reject atomically when it reaches
	# the footings; this is the same operation as the successful creation above.
	var deep:=river.duplicate(true);deep.width=6.;deep.depth=2.
	await rejected("generate_terrain_river",deep,"river undermining both abutments")
	for state in ["locked","hidden"]:
		await call_tool("set_object_properties",{"ids":[bridge_id],state:true})
		await rejected("sculpt_terrain",flat([2.5,0],6.5),state+" bridge preserves footing protection")
		await call_tool("undo")
	# Unknown structure/pose cannot opt into a source-specific exception.
	var tilted:=bridge.duplicate(true);tilted.rotation[0]=2.
	check(Contact.geometry(tilted,{}).is_empty(),"tilted native bridge retains conservative protection")
	var bad:=bridge.duplicate(true);bad.house_prefab.sha256="0".repeat(64)
	check(Contact.geometry(bad,{}).is_empty(),"invalid frozen source hash cannot grant excavation permission")
	bad=bridge.duplicate(true);bad.bridge_mesh.depth+=.1
	check(Contact.geometry(bad,{}).is_empty(),"recipe inconsistent with frozen structural triangles fails closed")
	transformed_case(bridge)
	cache_invalidation(bridge,directory)
	var ui_before:=snapshot()
	var brush:={"id":terrain_id,"mode":"lower","points":[[0.,0.]],"radius":.6,"strength":.05,"cross_tiles":true}
	var ui:Dictionary=editor._terrain.prepare(brush)
	check(ui.ok and ui.changed and equivalent(ui_before,snapshot()),"interactive brush shares native contact proof and prepare is read-only")
	await call_tool("sculpt_terrain",brush);await call_tool("undo")
	# A second real two-span bridge proves that a middle pier and its pointed
	# cutwater are foundations, not overhead arch surfaces.
	var middle:=await call_tool("create_terrain",{"center":[40,8.465,0],"width":24.,"depth":24.,"cell_size":.5})
	terrain_id=middle.id;bridge_id="two_arches"
	args.id=bridge_id;args.start=[34,8.49,0];args.end=[46,8.49,0];args.arches=2
	await call_tool("generate_bridge",args)
	var pier_mesh:=Contact.geometry(editor._doc._find(bridge_id),{})
	check(not pier_mesh.is_empty() and pier_mesh.bases.size()>4,"actual middle pier contributes its complete cutwater sole")
	await rejected("sculpt_terrain",flat([40,0],6.5),"middle pier support removal")
	await rejected("sculpt_terrain",flat([40,3.4],6.5),"off-centre pointed cutwater support removal")
	var result:={"failures":failed,"map":path,"map_sha256":FileAccess.get_sha256(path),"source_sha256":mesh.source_sha256,"frozen_sha256":bridge.house_prefab.sha256,"actual_base_triangles":mesh.bases.size(),"projected_structure_triangles":mesh.body.size(),"scope":"Shared native terrain/river protection, no new schema. CPU and actual loopback HTTP; no GPU or formal map changes."}
	FileAccess.open(OUT.path_join("terrain_bridge_contact_http_review.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("TERRAIN_BRIDGE_CONTACT_HTTP ",directory," failures=",failed);quit(1 if failed else 0)
