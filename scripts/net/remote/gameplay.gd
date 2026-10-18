extends RefCounted
## Serialized async business requests. UI actions are delivered once through
## poll_combat_tick, including callers which still use synchronous adapters.
var transport:Node
var projection:RefCounted
var environment:RefCounted
var _serial:=0
var _jobs:Array=[]
var _running:=false
var _epoch:=0
var _event_cursor:=0
var _event_busy:=false
var _events_at:=0

func busy()->bool:return _running or not _jobs.is_empty()

func _init(owner:Node)->void:
	environment=preload("res://scripts/net/remote/environment.gd").new(owner)
	transport=owner;projection=preload("res://scripts/net/remote/projection.gd").new(owner)

func cancel()->void:
	_epoch+=1;_event_cursor=0;_event_busy=false;_events_at=0
	var jobs:=_jobs;_jobs=[]
	for job:Dictionary in jobs:transport.response_ready.emit(int(job.id),{"ok":false,"error":"connection_closed","actions":[]})
	projection.reset();environment.reset()

func dispatch(operation:String,args:Array=[])->Dictionary:
	if not transport.is_world_ready():return failure("世界尚未就绪，请等待加载完成")
	if _jobs.size()>=64:return failure("请求过多，请稍后重试")
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
			if job.scope==transport.context() or job.operation=="respawn":
				transport._network_actions.append_array(result.get("actions",[]))
			else:result={"ok":false,"error":"stale_world_response"}
		var reply:=result.duplicate(true);reply.actions=[]
		transport.response_ready.emit(int(job.id),reply)
	_running=false

func _execute(operation:String,args:Array,scope:Dictionary,epoch:int,shop_revision:int)->Dictionary:
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
			var target:Dictionary=projection.target(str(args[0]))
			if target.is_empty():return failure("目标已离开，请重新选择")
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
				target=projection.target(str(args[1]) if args.size()>1 else "")
				if target.is_empty():return failure("请选择有效的服务器目标")
			path="/v1/gameplay/casts";body={"skill_uuid":skill,"sequence":int(snapshots.get("skills",{}).get("sequence",0))+1,"target":target}
			if not item_id.is_empty():body.item_uuid=item_id
			if mode=="area":
				if args.size()<3 or not args[2] is Vector3 or not args[2].is_finite():return failure("请选择有效的地面位置")
				var ground:Vector3=args[2];body.target={"id":"","map":transport.world_session.map_ref,"generation":0};body.aim={"position_m":[ground.x,ground.y,ground.z],"yaw_radians":0.}
		"house_view","house_change":
			var request:Dictionary=environment.request(operation,args);path=request.path;method=request.method;body=request.body
		"claim_reward":
			path="/v1/gameplay/rewards/"+str(args[0]).uri_encode()+"/claim"
		"cancel_cast":
			var cast_id:=str(snapshots.get("skills",{}).get("last",{}).get("cast_id",""))
			if cast_id.is_empty():return failure("当前没有可中断的施法")
			path="/v1/gameplay/casts/"+cast_id.uri_encode()+"/cancel"
		"interact":
			var target:Dictionary=projection.target(str(args[0]))
			if target.is_empty():return failure("交互对象已离开")
			path="/v1/gameplay/interactions";body={"target":target,"action":"talk"}
		"quest":
			var target:Dictionary=projection.target(str(projection.last_dialogue.get("target",{}).get("id","")))
			if target.is_empty():return failure("请先与任务 NPC 交谈")
			path="/v1/gameplay/interactions";body={"target":target,"action":str(args[0]),"quest":str(args[1])}
		"respawn":
			path="/v1/gameplay/respawn";body={"sequence":int(snapshots.get("resurrection",{}).get("respawn_sequence",0))+1}
		"abandon_quest":
			var accepted:Dictionary={}
			for quest:Dictionary in snapshots.get("progression",{}).get("quests",[]):
				if quest.get("definition",{}).get("uuid","")==str(args[0]):accepted=quest
			if accepted.is_empty():return failure("任务接受记录已变化，请刷新任务列表")
			path="/v1/gameplay/quests";body={"action":"abandon","quest":str(args[0])}
			if accepted.has("accepted_at_key"):body.accepted_at_key=str(accepted.accepted_at_key)
			else:body.accepted_at_game=accepted.get("accepted_at_game")
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
	var response:Dictionary=await transport.request_api(path,method,body)
	if operation=="respawn" and epoch==_epoch:
		# Respawn may commit a new actor generation before HTTP arrives. Recover
		# the authoritative receipt and session; never repeat the mutation.
		var session:Dictionary=await transport.request_api("/v1/world/session")
		if session.ok:
			var current:Dictionary=session.body
			transport._receive({"push":true,"ok":true,"resync":true,"world_session":current.get("data",{}),"actor_3d":current.get("actor_3d",{}),"actors_3d":current.get("actors_3d",[])})
		var life:Dictionary=await transport.request_api("/v1/gameplay/resurrection")
		if life.ok and int(life.body.get("data",{}).get("respawn_sequence",-1))==int(body.sequence) and life.body.data.get("alive",false):response={"ok":true,"body":{"data":life.body.data}}
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
	var refreshed:Dictionary=await transport.refresh_world_snapshots()
	if not refreshed.ok:return failure("操作已提交，状态刷新失败，请等待同步；不要重复提交")
	if operation=="claim_reward":actions.append({"type":"system_message","text":"已领取服务器掉落"})
	transport._project_snapshots()
	actions.append_array(projection.actions())
	return {"ok":true,"data":data,"actions":actions}

func poll_events()->void:
	if _event_busy or not transport.is_world_ready():return
	var now:=Time.get_ticks_msec()
	if now<_events_at:return
	_events_at=now+int(clampf(float(ProjectSettings.get_setting("rmmo/network/event_interval_sec",.1)),.05,5.)*1000.)
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
		if _event_cursor>0:await transport.request_api("/v1/gameplay/combat-events/ack",HTTPClient.METHOD_POST,{"through":_event_cursor})
	if epoch==_epoch:_event_busy=false
