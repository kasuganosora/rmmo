extends RefCounted
## Serialized async business requests. UI actions are delivered once through
## poll_combat_tick, including callers which still use synchronous adapters.
var transport:Node
var projection:RefCounted
var environment:RefCounted
var social:RefCounted
var _serial:=0
var _jobs:Array=[]
var _running:=false
var _epoch:=0
var _event_cursor:=0
var _event_acked:=0
var _event_busy:=false
var _events_at:=0
var _event_stream_active:=false
var _event_stream_legacy:=false
var _event_ack_busy:=false
var _event_scope:Dictionary={}
var _event_applied:Dictionary={}
var _event_identity:=""
var _training_unsupported:=false
var _training_retry:Dictionary={}

func busy()->bool:return _running or not _jobs.is_empty()

func _init(owner:Node)->void:
	environment=preload("res://scripts/net/remote/environment.gd").new(owner)
	social=preload("res://scripts/net/remote/social.gd").new(owner)
	transport=owner;projection=preload("res://scripts/net/remote/projection.gd").new(owner)

func reset_event_stream()->void:
	if not _event_identity.is_empty():
		_event_applied.erase(_event_identity);_event_applied[_event_identity]=_event_cursor
		var limit:=clampi(int(ProjectSettings.get_setting("rmmo/network/event_resume_cache_entries",64)),8,512)
		while _event_applied.size()>limit:_event_applied.erase(_event_applied.keys()[0])
	_event_identity=""
	_event_cursor=0;_event_acked=0;_event_busy=false;_events_at=0
	_event_stream_active=false;_event_stream_legacy=false;_event_ack_busy=false;_event_scope.clear()

func cancel()->void:
	_epoch+=1;reset_event_stream()
	var jobs:=_jobs;_jobs=[]
	for job:Dictionary in jobs:transport.response_ready.emit(int(job.id),{"ok":false,"error":"connection_closed","actions":[]})
	projection.reset();environment.reset();social.reset()
	_training_unsupported=false;_training_retry.clear()

func dispatch(operation:String,args:Array=[])->Dictionary:
	if not transport.is_world_ready():return failure("世界尚未就绪，请等待加载完成")
	if _jobs.size()>=64:return failure("请求过多，请稍后重试")
	args=args.duplicate(true)
	if operation=="attack":args.append(projection.target(str(args[0])))
	if operation=="skill":
		while args.size()<4:args.append(null)
		args.append(projection.target(str(args[1])) if args[1]!=null else {})
	if operation=="resurrection_resolve":
		var life:Dictionary=transport.business_snapshots.get("resurrection",{})
		if life.get("offer",{}).get("offer_id","")!=str(args[0]):return failure("复活邀请已变化")
		args.append(int(life.get("resolve_sequence",0))+1)
	if operation=="cancel_status":
		var snapshot:Dictionary=transport.business_snapshots.get("statuses",{})
		if str(args[0]) not in snapshot.get("cancelable",[]):return failure("此状态不允许主动取消")
		args.append(int(projection.statuses_snapshot().get("sequence",0)))
	if operation in ["skill_learn","skill_respec","attribute_respec"]:
		if _training_unsupported:return failure("此服务器尚不支持技能学习")
		var training:Dictionary=projection.training_view()
		if not training.get("enabled",false):return failure("此服务器尚未启用技能学习")
		args.append(int(training.get("sequence",0))+1)
	if operation=="abandon_quest":args.append(projection.acceptance(str(args[0])))
	if operation=="quest" and str(args[0])=="complete":args.append(projection.acceptance(str(args[1])))
	if operation=="guild_change":
		var observed:Dictionary=social.snapshot_guild()
		if observed.get("loaded",false):
			args[0].expected_revision=int(observed.get("revision",0))
			if args[0].action not in ["create","accept","decline"]:args[0].guild_id=str(observed.get("id",""))
	_serial+=1
	_jobs.append({"id":_serial,"operation":operation,"args":args.duplicate(true),"scope":transport.context(),"epoch":_epoch,"shop_revision":projection.shop_revision})
	if not _running:_pump.call_deferred()
	return {"deferred":true,"request_id":_serial}

func failure(message:String)->Dictionary:
	return {"ok":false,"error":message,"actions":[{"type":"system_message","text":message}]}

func _pump()->void:
	if _running:return
	_running=true
	while not _jobs.is_empty():
		var job:Dictionary=_jobs.pop_front()
		while transport._snapshot_inflight and job.epoch==_epoch:
			await transport.get_tree().process_frame
		var result:Dictionary
		if job.epoch!=_epoch or job.scope!=transport.context():result=failure("请求所属世界已变更")
		else:result=await _execute(str(job.operation),job.args,job.scope,int(job.epoch),int(job.shop_revision))
		if job.epoch==_epoch:
			if job.scope==transport.context() or job.operation in ["respawn","resurrection_resolve"]:
				transport._network_actions.append_array(result.get("actions",[]))
			else:result={"ok":false,"error":"stale_world_response"}
		var reply:=result.duplicate(true);reply.actions=[]
		transport.response_ready.emit(int(job.id),reply)
	_running=false

func _execute(operation:String,args:Array,scope:Dictionary,epoch:int,shop_revision:int)->Dictionary:
	if operation in ["quest_history","guild_refresh","guild_change"]:
		var result:Dictionary=await social.execute(operation,args)
		if scope!=transport.context() or epoch!=_epoch:return failure("请求所属世界已变更")
		if not result.ok:
			result.actions=social.actions()
			result.actions.append({"type":"system_message","text":str(result.get("error","请求失败"))})
			return result
		if operation=="guild_change":
			var refreshed:Dictionary=await transport.refresh_gameplay_snapshots()
			if scope!=transport.context() or epoch!=_epoch:return failure("请求所属世界已变更")
			if not refreshed.ok:return failure("操作已提交，状态刷新失败，请等待同步；不要重复提交")
			transport._project_snapshots();result.actions.append_array(projection.actions())
		return result
	var path:="";var body:Dictionary={};var method:=HTTPClient.METHOD_POST
	var snapshots:Dictionary=transport.business_snapshots
	match operation:
		"inventory":
			path="/v1/gameplay/inventory";body=args[0].duplicate(true);body.sequence=int(snapshots.get("inventory",{}).get("sequence",0))+1
			if body.has("reference"):
				var item:Dictionary=projection.instance(str(body.reference),body.get("action")=="lock");body.erase("reference")
				if item.is_empty():return failure("物品实例不存在或不唯一，请重新选择背包格子")
				body.instance_id=item.instance_id
		"attack":
			var target:Dictionary=args[1] if args.size()>1 else projection.target(str(args[0]))
			if target.is_empty() or target!=projection.target(str(args[0])):return failure("目标已变化，请重新选择")
			path="/v1/gameplay/attack";body={"target":target,"sequence":int(snapshots.get("combat-state",{}).get("sequence",0))+1}
		"skill","item":
			var skill:=str(args[0]);var item_id:=""
			if operation=="item":
				var item:Dictionary=projection.instance(skill)
				if item.is_empty():return failure("物品实例不存在或不唯一")
				item_id=str(item.id);skill=str(projection.items.get(item_id,{}).get("use_skill",""))
				if skill.is_empty():return failure("此物品没有服务器使用效果")
			var definition:Dictionary=await projection.definition("skills",skill)
			if definition.is_empty():return failure("技能定义不可用")
			var mode:=str(definition.get("target",{}).get("mode","self"))
			var target:Dictionary={"id":transport._session_character_id,"map":transport.world_session.get("map_ref",""),"generation":0}
			if mode=="unit":
				var target_id:=str(args[1]) if args.size()>1 and args[1]!=null else ""
				target=args[4] if args.size()>4 else projection.target(target_id)
				if target.is_empty() or target!=projection.target(target_id):return failure("目标已变化，请重新选择有效的服务器目标")
			path="/v1/gameplay/casts";body={"skill_uuid":skill,"sequence":int(snapshots.get("skills",{}).get("sequence",0))+1,"target":target}
			if not item_id.is_empty():body.item_uuid=item_id
			if mode=="area":
				if args.size()<3 or not args[2] is Vector3 or not args[2].is_finite():return failure("请选择有效的地面位置")
				if args.size()<4 or not (args[3] is float or args[3] is int) or not is_finite(float(args[3])):return failure("请选择有效的施法方向")
				var ground:Vector3=args[2];body.target={"id":"","map":transport.world_session.map_ref,"generation":0};body.aim={"position_m":[ground.x,ground.y,ground.z],"yaw_radians":wrapf(float(args[3]),-PI,PI)}
		"house_view","house_change":
			var request:Dictionary=environment.request(operation,args);path=request.path;method=request.method;body=request.body
		"claim_reward":
			path="/v1/gameplay/rewards/"+str(args[0]).uri_encode()+"/claim"
		"cancel_cast":
			var cast_id:=str(snapshots.get("skills",{}).get("last",{}).get("cast_id",""))
			if cast_id.is_empty():return failure("当前没有可中断的施法")
			path="/v1/gameplay/casts/"+cast_id.uri_encode()+"/cancel";body={"cast_id":cast_id}
		"cancel_status":
			path="/v1/gameplay/statuses";body={"status_id":str(args[0]),"expected_sequence":int(args[1])}
		"skill_training_view":
			if _training_unsupported:return failure("此服务器尚不支持技能学习")
			path="/v1/gameplay/skill-training";method=HTTPClient.METHOD_GET
		"skill_learn","skill_respec","attribute_respec":
			path="/v1/gameplay/skill-training"
			body={"sequence":int(args[-1]),"action":"learn" if operation=="skill_learn" else ("attributes_respec" if operation=="attribute_respec" else "respec")}
			if operation=="skill_learn":body.skill_uuid=str(args[0])
			if not _training_retry.is_empty():
				if _training_retry.get("action")!=body.action or _training_retry.get("skill_uuid","")!=body.get("skill_uuid",""):return failure("上次技能操作结果尚未确认，请先重试该操作")
				body=_training_retry.duplicate(true)
		"interact":
			var target:Dictionary=projection.target(str(args[0]))
			if target.is_empty():return failure("交互对象已离开")
			path="/v1/gameplay/interactions";body={"target":target,"action":"talk"}
		"quest":
			var target:Dictionary=projection.target(str(projection.last_dialogue.get("target",{}).get("id","")))
			if target.is_empty():return failure("请先与任务 NPC 交谈")
			path="/v1/gameplay/interactions";body={"target":target,"action":str(args[0]),"quest":str(args[1])}
			if str(args[0])=="complete" and args.size()>2 and args[2].has("acceptance_id"):body.acceptance_id=str(args[2].acceptance_id)
		"resurrection_resolve":
			path="/v1/gameplay/resurrection/resolve";body={"offer_id":str(args[0]),"accept":bool(args[1]),"sequence":int(args[2])}
		"respawn":
			path="/v1/gameplay/respawn";body={"sequence":int(snapshots.get("resurrection",{}).get("respawn_sequence",0))+1}
		"abandon_quest":
			var accepted:Dictionary=args[1] if args.size()>1 else {}
			if accepted.is_empty():return failure("任务接受记录已变化，请刷新任务列表")
			path="/v1/gameplay/quests";body={"action":"abandon","quest":str(args[0])}
			body.merge(accepted)
		"fixture":
			var value:float=args[2]
			if not is_finite(value) or value not in [0.,1.]:return failure("服务器门窗只接受完全打开或关闭")
			var found:Dictionary={}
			for row:Dictionary in snapshots.get("interactions",{}).get("objects",[]):
				if row.get("kind")=="fixture" and row.get("owner_id")==str(args[0]) and row.get("fixture_id")==str(args[1]):found=row;break
			if found.is_empty():return failure("服务器尚未注册此门窗")
			var action:="open" if value==1. else "close"
			if found.get("state")==("open" if value==1. else "closed"):return {"ok":true,"actions":[]}
			if action not in found.get("actions",[]):return failure("此门窗不允许该操作")
			var page:Dictionary=snapshots.interactions
			path="/v1/world/interactions";body={"map_id":page.map_id,"generation":int(page.generation),"definition_revision":page.definition_revision,"expected_revision":int(page.revision),"object_id":found.id,"action":action}
		"map_interaction":
			var page:Dictionary=snapshots.get("interactions",{})
			path="/v1/world/interactions";body={"map_id":page.get("map_id",""),"generation":int(page.get("generation",0)),"definition_revision":page.get("definition_revision",""),"expected_revision":int(page.get("revision",0)),"object_id":str(args[0]),"action":str(args[1])}
		"shop_open":
			var target:Dictionary=projection.target(str(args[0]))
			if target.is_empty():return failure("商人已离开")
			path="/v1/gameplay/shop?entity="+str(target.id).uri_encode()+"&map="+str(target.map).uri_encode()+"&generation="+str(target.generation);method=HTTPClient.METHOD_GET
		"shop":
			if projection.shop.is_empty():return failure("请先与商人交谈并打开商店")
			path="/v1/gameplay/shop";body=args[0].duplicate(true);body.target=projection.target(str(projection.shop.get("target",{}).get("id","")));body.sequence=int(projection.shop.get("sequence",0))+1
			if body.has("reference"):
				var item:Dictionary=projection.instance(str(body.reference));body.erase("reference")
				if item.is_empty():return failure("请选择唯一的物品实例")
				body.instance_id=item.instance_id
		_:
			return failure("未识别的真实服务器请求："+operation)
	if scope!=transport.context() or epoch!=_epoch:return failure("请求所属世界已变更")
	var response:Dictionary
	if operation in ["skill_learn","skill_respec","attribute_respec"]:_training_retry=body.duplicate(true)
	if transport.world_session.get("gameplay_protocol",0)==1 and operation in ["attack","skill","item","cancel_cast","cancel_status"]:
		var kind:="attack" if operation=="attack" else ("cancel" if operation=="cancel_cast" else ("cancel_status" if operation=="cancel_status" else "cast"))
		response=await transport.gameplay_command(kind,body)
	else:
		# HTTP cancel has an empty body; only the WS command carries cast_id.
		response=await transport.request_api(path,method,{} if operation=="cancel_cast" else body)
	if epoch!=_epoch or scope!=transport.context() and operation not in ["respawn","resurrection_resolve"]:return failure("请求所属世界已变更")
	if operation in ["skill_training_view","skill_learn","skill_respec","attribute_respec"]:
		if response.get("status",0) in [404,405]:_training_unsupported=true
		if response.get("ok",false) or int(response.get("status",0)) in [400,401,403,404,405,409,415]:_training_retry.clear()
	if operation in ["respawn","resurrection_resolve"] and epoch==_epoch:
		# Respawn may commit a new actor generation before HTTP arrives. Recover
		# the authoritative receipt and session; never repeat the mutation.
		var session:Dictionary=await transport.request_api("/v1/world/session")
		if session.ok:
			var current:Dictionary=session.body
			transport._receive({"push":true,"ok":true,"resync":true,"world_session":current.get("data",{}),"actor_3d":current.get("actor_3d",{}),"actors_3d":current.get("actors_3d",[])})
		var life:Dictionary=await transport.request_api("/v1/gameplay/resurrection")
		var sequence_key:="respawn_sequence" if operation=="respawn" else "resolve_sequence"
		if life.ok and int(life.body.get("data",{}).get(sequence_key,-1))==int(body.sequence):
			var accepted:bool=life.body.data.get("alive",false)
			if operation=="resurrection_resolve":accepted=life.body.data.get("resolve_last",{}).get("offer_id","")==str(body.offer_id) and life.body.data.resolve_last.get("accepted",false)==bool(body.accept)
			if accepted:response={"ok":true,"body":{"data":life.body.data}}
	if not response.ok:return failure("服务器拒绝操作："+str(response.get("error",response.get("status","unknown"))))
	var data:Variant=response.body.get("data",{})
	var actions:Array=[]
	if operation in ["house_view","house_change"] and data is Dictionary:actions.append_array(environment.result(data))
	if operation in ["interact","quest"] and data is Dictionary:actions.append_array(projection.dialogue(data))
	if operation in ["shop_open","shop"] and data is Dictionary and shop_revision==projection.shop_revision:
		projection.shop=data.duplicate(true)
		var listings:Array=[]
		for offer:Dictionary in data.get("offers",[]):
			var item:Dictionary=offer.get("item",{});projection.register_item(str(item.get("uuid","")),item)
			listings.append({"item_id":item.get("uuid",""),"name":item.get("name",""),"buy_price":int(offer.get("price",0))})
		actions.append({"type":"open_shop","shop_id":data.get("target",{}).get("id",""),"title":data.get("name","商店"),"listings":listings,"gold":int(data.get("gold",0)),"buyback":data.get("buyback",[])})
	var refreshed:Dictionary=await transport.refresh_world_snapshots() if operation in ["respawn","resurrection_resolve"] else await transport.refresh_gameplay_snapshots()
	if not refreshed.ok:return failure("操作已提交，状态刷新失败，请等待同步；不要重复提交")
	if operation=="claim_reward":actions.append({"type":"system_message","text":"已领取服务器掉落"})
	transport._project_snapshots()
	actions.append_array(projection.actions())
	if operation=="skill_respec":actions.append({"type":"skill_respec"})
	return {"ok":true,"data":data,"actions":actions}

func poll_events()->void:
	if transport.world_session.get("gameplay_protocol",0)==1 and not _event_stream_legacy:
		_poll_stream_events();return
	if _event_busy or not transport.is_world_ready():return
	var now:=Time.get_ticks_msec()
	if now<_events_at:return
	var interval:=clampf(float(ProjectSettings.get_setting("rmmo/network/runtime_fallback_interval_sec",2.)),1.,30.) if transport.world_session.get("gameplay_protocol",0)==1 else clampf(float(ProjectSettings.get_setting("rmmo/network/event_interval_sec",.1)),.05,5.)
	_events_at=now+int(interval*1000.)
	_event_busy=true;var epoch:=_epoch;var scope:Dictionary=transport.context()
	var result:Dictionary=await transport.request_api("/v1/gameplay/combat-events?after="+str(_event_cursor)+"&limit=100")
	if result.ok and epoch==_epoch and scope==transport.context():
		var page:Dictionary=result.body.get("data",{})
		for delivery:Dictionary in page.get("events",[]):
			var cursor:=int(delivery.get("cursor",0))
			if cursor<=_event_cursor:continue
			var event:Dictionary=delivery.get("event",{})
			if event.get("map","")==transport.world_session.get("map_ref",""):
				transport._network_actions.append({"type":"remote_combat_event","event":event.duplicate(true)})
			_event_cursor=cursor
		if _event_cursor>_event_acked:
			var through:=_event_cursor
			var acknowledged:Dictionary=await transport.request_api("/v1/gameplay/combat-events/ack",HTTPClient.METHOD_POST,{"through":through})
			if acknowledged.ok and epoch==_epoch and scope==transport.context():_event_acked=through
	if epoch==_epoch:_event_busy=false

func _poll_stream_events()->void:
	if not transport.is_world_ready():return
	if _event_scope!=transport.context():
		reset_event_stream();_event_scope=transport.context().duplicate(true)
		_event_identity=str(transport.endpoint_address)+"|"+str(transport._session_user)+"|"+str(transport._selected_id)
		_event_cursor=int(_event_applied.get(_event_identity,0))
	if _event_stream_active:
		if _event_cursor>_event_acked and not _event_ack_busy and Time.get_ticks_msec()>=_events_at:_ack_stream_events()
		return
	if _event_busy or Time.get_ticks_msec()<_events_at:return
	_event_busy=true;var scope:=_event_scope.duplicate();var epoch:=_epoch
	var result:Dictionary=await transport.gameplay_command("subscribe_events",{"after":_event_cursor})
	if epoch!=_epoch or scope!=transport.context():return
	_event_busy=false
	if result.ok:_event_stream_active=true
	elif result.get("error")=="combat_stream_unavailable":_event_stream_legacy=true
	elif result.get("error")=="invalid_combat_cursor":
		_event_cursor=0;_event_acked=0;_event_applied.erase(_event_identity);_events_at=Time.get_ticks_msec()+1000
	else:_events_at=Time.get_ticks_msec()+1000

func receive_stream_events(payload:String)->void:
	if transport.world_session.get("gameplay_protocol",0)!=1:return
	var page:Variant=JSON.parse_string(payload)
	if not page is Dictionary or not page.get("events") is Array:transport.disconnect_server("服务器战斗事件格式无效");return
	if _event_scope!=transport.context():return
	for delivery:Variant in page.events:
		if not delivery is Dictionary or not delivery.get("event") is Dictionary:transport.disconnect_server("服务器战斗事件格式无效");return
		var cursor:int=transport._runtime_snapshot._integer(delivery.get("cursor"))
		if cursor<=0:transport.disconnect_server("服务器战斗事件游标无效");return
		if cursor<=_event_cursor:continue
		var event:Dictionary=delivery.event
		if event.get("map","")==transport.world_session.get("map_ref",""):transport._network_actions.append({"type":"remote_combat_event","event":event.duplicate(true)})
		_event_cursor=cursor
	# A duplicated pending page must be acknowledged again, even when the
	# earlier receipt was applied but its ACK was lost.
	var next:int=transport._runtime_snapshot._integer(page.get("next_cursor",0))
	if next<0 or next>_event_cursor:transport.disconnect_server("服务器战斗事件游标无效");return
	if next>0:
		_event_acked=mini(_event_acked,next-1)
		if _event_stream_active and not _event_ack_busy:_ack_stream_events()

func _ack_stream_events()->void:
	_event_ack_busy=true;var through:=_event_cursor;var scope:=_event_scope.duplicate();var epoch:=_epoch
	var result:Dictionary=await transport.gameplay_command("ack_events",{"through":through})
	if epoch!=_epoch or scope!=transport.context():return
	_event_ack_busy=false
	if result.ok:_event_acked=maxi(_event_acked,through)
	_events_at=Time.get_ticks_msec()+100
