extends "res://tools/test_world3d_buildings.gd"
const Index=preload("res://scripts/world3d/stream_index.gd")
func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	var specs:Array=[]
	for kind in ["tower","tree","short"]:
		for part in 2:
			var mesh:=BoxMesh.new();mesh.size=Vector3(2,8 if kind!="short" else 3,2)
			specs.append({"uuid":kind+"__"+str(part),"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,Vector3(128,part*mesh.size.y,0)),"chunk_min":Vector2i(4,0),"chunk_max":Vector2i(4,0),"extras":{"rmmo_wind":{}} if kind=="tree" else {}})
	var indexed:=Index.build(specs)
	check(indexed.stream_building_groups.keys()==["structure:tower"],"only tall rigid imported assets receive whole-structure residency")
	check(indexed.stream_building_groups["structure:tower"].size()==2,"all structure parts grouped")
	var directory:=Paths.cache_directory("tall_prop_%d"%Time.get_ticks_usec());var path:=directory.path_join("map.gltf")
	check(Doc.new().save(path)==OK,"temporary native map")
	var session=Net.session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;root.add_child(editor);await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"loopback MCP")
	var definitions:=await rpc("tools/list")
	check(definitions.result.tools.any(func(t):return t.name=="place_asset"),"3D placement discovery")
	var found:=await call_tool("list_assets",{"query":"写实方形红顶尖塔·三层窗"})
	check(found.assets.size()==1,"published spire found")
	if found.assets.size()!=1:editor.free();quit(1);return
	var initial:int=editor._doc.records.size()
	await call_tool("place_asset",{"asset_id":found.assets[0].asset_id,"position":[128,0,0]})
	var records:Array=editor._doc.records.duplicate(true)
	await call_tool("place_asset",{"asset_id":found.assets[0].asset_id,"position":[128,0]},false)
	check(equivalent(records,editor._doc.records),"invalid placement has no side effects")
	await call_tool("undo");check(editor._doc.records.size()==initial,"native undo")
	await call_tool("redo");check(equivalent(records,editor._doc.records),"native redo")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(equivalent(records,editor._doc.records),"native save reopen preserves independent instance")
	var host:=Node3D.new();root.add_child(host);var scene=editor._doc.build();host.add_child(scene)
	Stream.sync(scene,host,Vector3.ZERO)
	var meshes:Dictionary=scene.get_meta("stream_meshes");var bodies:Dictionary=scene.get_meta("stream_bodies")
	check(meshes.size()==6,"all six spire parts render beyond ordinary prop radius")
	check(bodies.is_empty(),"distant spire does not expand collision residency")
	Stream.sync(scene,host,Vector3(128,0,0));check(not bodies.is_empty(),"nearby spire remains physical")
	Stream.sync(scene,host,Vector3(-2000,0,0));check(meshes.is_empty(),"spire released beyond town visibility")
	host.free();editor.free();session.world3d_editor_doc=null;session.world3d_editor_path="";Io._remove_tree(directory)
	print("TALL_PROP_RESIDENCY failures=",failed);quit(1 if failed else 0)
