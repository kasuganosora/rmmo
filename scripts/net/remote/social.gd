extends RefCounted
## On-demand journal history and guild operations; live guild state shares the
## existing progression resource so protocol-1 clients keep their resource layout.
var transport:Node
var guild:Dictionary={}
var _guild_signature:=""
var _guild_supported:=0
var _history_supported:=0
var _guild_publication:=0

func _init(owner:Node)->void:transport=owner

func reset()->void:
	_guild_publication+=1
	guild.clear();_guild_signature="";_guild_supported=0;_history_supported=0

func snapshot_guild()->Dictionary:
	var progression:Dictionary=transport.business_snapshots.get("progression",{})
	if progression.get("guild") is Dictionary:
		guild=progression.guild.duplicate(true);_guild_supported=1
	var result:=guild.duplicate(true)
	result.supported=_guild_supported>=0
	result.loaded=_guild_supported!=0
	result.self_id=transport._session_character_id
	return result

func actions()->Array:
	var current:=snapshot_guild()
	var signature:=JSON.stringify(current)
	if signature==_guild_signature:return []
	_guild_signature=signature
	return [{"type":"guild_update","guild":current}]

func execute(operation:String,args:Array)->Dictionary:
	var scope:Dictionary=transport.context();var connection:int=transport._connection_revision
	var history:=operation=="quest_history"
	if history and _history_supported<0:return {"ok":false,"unsupported":true,"error":"此服务器尚未提供任务完成历史"}
	if not history and _guild_supported<0:return {"ok":false,"unsupported":true,"error":"此服务器尚未提供公会管理"}
	var path:="/v1/gameplay/quest-history?cursor="+str(args[0]).uri_encode() if history else "/v1/gameplay/guilds"
	if history and int(args[1])>0:path+="&limit="+str(clampi(int(args[1]),1,100))
	var method:=HTTPClient.METHOD_GET
	var body:Dictionary={}
	if operation=="guild_change":
		var current:=snapshot_guild()
		if not current.get("loaded",false):
			var loaded:Dictionary=await execute("guild_refresh",[])
			if not loaded.ok:return loaded
			current=snapshot_guild()
		body=args[0].duplicate(true);method=HTTPClient.METHOD_POST
		body.request_id=str(current.get("next_request_id","1"))
		if not body.has("expected_revision"):body.expected_revision=int(current.get("revision",0))
		if body.action not in ["create","accept","decline"] and not body.has("guild_id"):body.guild_id=str(current.get("id",""))
	if scope!=transport.context() or connection!=transport._connection_revision:return {"ok":false,"error":"stale_world_response"}
	var local_publication:=_guild_publication
	var runtime_publication:int=transport._snapshot_published_serial if not history else 0
	var observed_guild:Variant=transport.business_snapshots.get("progression",{}).get("guild")
	if observed_guild is Dictionary:observed_guild=observed_guild.duplicate(true)
	var response:Dictionary=await transport.request_api(path,method,body)
	if scope!=transport.context() or connection!=transport._connection_revision:return {"ok":false,"error":"stale_world_response"}
	if not response.ok:
		if int(response.get("status",0)) in [404,405]:
			if history:_history_supported=-1
			else:_guild_supported=-1;guild.clear()
			return {"ok":false,"unsupported":true,"error":"此服务器尚未提供任务完成历史" if history else "此服务器尚未提供公会管理"}
		if operation=="guild_change":await execute("guild_refresh",[])
		return {"ok":false,"error":"服务器拒绝操作："+str(response.get("error","unknown"))}
	var data:Variant=response.body.get("data",{})
	if not data is Dictionary:return {"ok":false,"error":"invalid_social_snapshot"}
	if history:
		_history_supported=1
		var page:Dictionary=data.duplicate(true);page.quests=[]
		for entry:Dictionary in data.get("entries",[]):
			page.quests.append({"id":"history:"+str(entry.get("id","")),"definition_id":entry.get("quest",""),"title":entry.get("name",entry.get("quest","任务")),"status":"completed","completed_at_utc":entry.get("completed_at_utc",""),"objectives":[],"reward":{"gold":int(entry.get("gold",0)),"exp":int(entry.get("experience",0)),"items":[]}})
		return {"ok":true,"data":page,"actions":[]}
	var current_guild:Variant=transport.business_snapshots.get("progression",{}).get("guild")
	# A pushed snapshot may already be acknowledged while this HTTP read is
	# pending. Never replace it with an older roster or request receipt: an idle
	# stream need not send that resource again. Concurrent HTTP publications also
	# supersede this read, even when the world context has not changed.
	if local_publication!=_guild_publication or (current_guild is Dictionary and (runtime_publication!=transport._snapshot_published_serial or current_guild!=observed_guild)):
		return {"ok":true,"data":snapshot_guild(),"actions":actions()}
	_guild_publication+=1
	_guild_supported=1;guild=data.duplicate(true)
	if not transport.business_snapshots.has("progression"):transport.business_snapshots.progression={}
	transport.business_snapshots.progression.guild=guild.duplicate(true)
	return {"ok":true,"data":data,"actions":actions()}
