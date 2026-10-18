extends Node
const Net=preload("res://scripts/net/net.gd")
const Config=preload("res://scripts/net/connection_config.gd")
var mode:="mock"
var error:=""
var real:Node

func _ready()->void:
	var options:=Config.startup()
	if not options.ok:
		var message:="未知连接模式："+str(options.mode)
		# Invalid real-mode configuration is terminal, never a silent Mock login.
		configure(true,options.address);error=message;real.configuration_error=message;return
	configure(options.mode=="real",options.address)

func configure(use_real:bool,address:String="")->Dictionary:
	var current:=Net.server()
	if current!=null and current.has_method("is_logged_in") and current.is_logged_in():return {"ok":false,"error":"请先退出登录再切换连接模式"}
	if current!=null and current.get("_login_inflight"):return {"ok":false,"error":"请等待当前登录请求结束"}
	preload("res://scripts/net/request_pipeline.gd").reset()
	if is_instance_valid(real):real.disconnect_server();real.queue_free();real=null
	var mock:=get_node_or_null("/root/MockServer")
	mode="real" if use_real else "mock"
	error=""
	if mock!=null:mock.set_process(not use_real)
	if use_real:
		real=load("res://scripts/net/real_server.gd").new();real.name="RealServer";add_child(real)
		real.endpoint_address=address
		Net.set_server(real)
	else:
		Net.clear_server_override()
		if mock!=null and mock.combat_stats==null:
			mock._init_combat_layers()
			if not Net.session().use_world3d():mock._load_pack(mock.start_map_pack_path())
	if not address.is_empty():Net.session().server_address=address
	return {"ok":true,"mode":mode}
