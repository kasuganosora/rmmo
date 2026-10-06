extends SceneTree
func _init() -> void:call_deferred("run")
func run() -> void:
	var am=root.get_node("AssetManager")
	assert(am.start_map_pack_ref()=="user://content/packs/default")
	assert(am.default_map_pack_path()=="user://content/packs/default")
	var server=root.get_node("MockServer")
	server.login("demo","demo","local")
	var login_result: Array=await server.login_finished
	assert(login_result[0])
	server.enter_world(1)
	var result: Array=await server.enter_world_ready
	assert(result[0],str(result))
	var spawn: Dictionary=result[2]
	assert(spawn.map_id=="Axel256",str(spawn.map_id))
	assert(int(spawn.cell.x)==112 and int(spawn.cell.y)==119,str(spawn.cell))
	assert(server.map_collision.check_passage(112,119,1))
	print("PASS configured default pack resolves editor town; login enters Axel256 at (112,119), walkable")
	quit(0)
