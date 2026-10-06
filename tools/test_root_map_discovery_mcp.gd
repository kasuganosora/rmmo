extends "res://tools/test_world3d_mcp.gd"
func run()->void:
	var directory:=Paths.cache_directory("root_map_discovery_%d"%Time.get_ticks_usec())
	var path:=directory.path_join("map.gltf")
	check(Doc.new().save(path)==OK,"temporary map saved")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;root.add_child(editor)
	await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"loopback MCP")
	var definitions:=await rpc("tools/list")
	check(definitions.result.tools.any(func(t):return t.name=="list_resource_packs"),"3D map discovery tool exposed")
	var before:=FileAccess.get_sha256(path)
	var reply:=await call_tool("list_resource_packs")
	var shared:Array=reply.packs.filter(func(p):return p.shared)
	check(not shared.is_empty(),"shared pack discovered")
	if not shared.is_empty():
		var town_path:=Paths.external_root().path_join("maps/medieval_river_town/map.gltf")
		check(shared[0].maps.any(func(m):return m.name=="medieval_river_town" and m.path==town_path),"actual town discovered at original path without opening or editing it")
	await call_tool("list_resource_packs",{"unknown":true},false)
	check(FileAccess.get_sha256(path)==before and editor._path==path,"discovery and invalid call preserve document")
	editor.free();session.world3d_editor_doc=null;session.world3d_editor_path=""
	Io._remove_tree(directory)
	print("ROOT_MAP_DISCOVERY failures=",failed);quit(1 if failed else 0)
