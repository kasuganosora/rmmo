extends SceneTree
## MockServer preparation thread in background mode: the main loop keeps running
## while the server graph compiles, the same autoload node becomes the server,
## deferred notices run once, and the prepared start pack matches a direct load.
## --require-early joins through Net.server() before the tree is ready.
const MOCK_SERVER_BACKGROUND:=true
const Host=preload("res://scripts/net/mock_server_host.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	var node:Node=root.get_node("MockServer")
	check(node.has_meta(Host.PREPARATION) and not node.has_method("login"),"autoload starts as the preparing host")
	Host.call_when_ready(node,&"set_meta",["host_probe_notice",true])
	if "--require-early" in OS.get_cmdline_user_args():
		var server:Node=preload("res://scripts/net/net.gd").server()
		check(server==node and node.has_method("login") and not node.has_meta(Host.PREPARATION),"early Net.server() installs the same node")
		check(node.get_meta("host_probe_notice",false),"pending notice runs on installation")
	run.call_deferred(node)
func run(node:Node)->void:
	var frames:=0;var longest:=0;var last:=Time.get_ticks_usec()
	while node.has_meta(Host.PREPARATION):
		await process_frame
		var now:=Time.get_ticks_usec();longest=maxi(longest,now-last);last=now;frames+=1
	await process_frame
	var profile:Dictionary=Host.profile_of(node)
	print("HOST_PROFILE ",JSON.stringify({"frames_while_preparing":frames,"longest_frame_us":longest,"profile":profile}))
	check(node.has_method("login") and node.is_processing(),"same node becomes the processing server")
	check(node.get_meta("host_probe_notice",false),"notice deferred until installation")
	check(int(profile.get("scripts",0))>200 and profile.has("compile_us") and profile.has("pack_us"),"preparation compiled the server graph and read the pack")
	if not "--require-early" in OS.get_cmdline_user_args():
		check(frames>0,"main loop kept running while the server was prepared")
	var am:Node=root.get_node("AssetManager")
	var Pack=load("res://scripts/map/tilemap_pack.gd")
	var direct=Pack.load_pack(am.start_map_pack_ref())
	var prepared=node._map_pack
	check(prepared!=null and node.map_collision==prepared.collision and not prepared.detached,"prepared pack became the server map")
	check(str(prepared.pack_dir)==str(direct.pack_dir) and prepared.map_id==direct.map_id and prepared.sheets.size()==direct.sheets.size(),"prepared pack resolves like a direct load")
	var same:=true;var cached:=0
	for i in direct.sheets.size():
		var a:Image=prepared.sheets[i];var b:Image=direct.sheets[i]
		if (a==null)!=(b==null) or (a!=null and (a.get_size()!=b.get_size() or a.get_format()!=b.get_format() or a.get_data()!=b.get_data())):same=false
		if a!=null and a==b:cached+=1
	check(same,"prepared sheets equal a direct load byte for byte")
	check(cached==direct.sheets.filter(func(s):return s!=null).size(),"prepared sheets are shared through the AssetManager cache")
	check(prepared.collision.width==direct.collision.width and prepared.collision.data==direct.collision.data and prepared.warps==direct.warps and prepared.npcs.size()==direct.npcs.size() and prepared.events.size()==direct.events.size(),"prepared map data equals a direct load")
	print("RESULT failures=",failures)
	quit(1 if failures>0 else 0)
