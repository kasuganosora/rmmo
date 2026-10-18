extends RefCounted
## Runtime selection is explicit. A real connection failure never selects Mock.
static func startup()->Dictionary:
	var mode:="real" if ProjectSettings.get_setting("rmmo/network/use_real_server",false) else "mock"
	var address:=str(ProjectSettings.get_setting("rmmo/network/server_url","http://127.0.0.1:7777"))
	if OS.has_environment("RMMO_CLIENT_BACKEND"):mode=OS.get_environment("RMMO_CLIENT_BACKEND")
	if OS.has_environment("RMMO_SERVER_URL"):address=OS.get_environment("RMMO_SERVER_URL")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--backend="):mode=arg.trim_prefix("--backend=")
		if arg.begins_with("--server-url="):address=arg.trim_prefix("--server-url=")
	return {"mode":mode,"address":address,"ok":mode in ["mock","real"]}

static func endpoint(address:String)->Dictionary:
	var value:=address.strip_edges().trim_suffix("/")
	if not value.contains("://"):value="http://"+value
	var pattern:=RegEx.new()
	pattern.compile("^(https?|wss?)://(\\[[0-9a-fA-F:]+\\]|[a-zA-Z0-9._-]+)(?::([0-9]{1,5}))?$")
	var found:=pattern.search(value)
	if found==null:return {"ok":false,"error":"服务器地址须为 http(s)://主机:端口，不含路径或账号"}
	if not found.get_string(3).is_empty() and (int(found.get_string(3))<1 or int(found.get_string(3))>65535):return {"ok":false,"error":"服务器端口无效"}
	var secure:=found.get_string(1) in ["https","wss"]
	var host:=found.get_string(2)+(":"+found.get_string(3) if not found.get_string(3).is_empty() else "")
	return {"ok":true,"http":("https://" if secure else "http://")+host,"websocket":("wss://" if secure else "ws://")+host+"/ws"}
