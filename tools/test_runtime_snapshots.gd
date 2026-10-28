extends SceneTree
const Snapshot=preload("res://scripts/net/remote/runtime_snapshot.gd")
const Real=preload("res://scripts/net/real_server.gd")
const Gameplay=preload("res://scripts/net/remote/gameplay.gd")
var failures:=0

class PagingTransport extends Real:
	var total:=1024
	var reads:=0
	var legacy:=false
	func request_api(path:String,_method:int=HTTPClient.METHOD_GET,_body:Dictionary={})->Dictionary:
		reads+=1
		if legacy and path.contains("unclaimed=true"):return {"ok":false,"status":400}
		var after:=0
		if path.contains("after="):after=int(path.get_slice("after=",1).get_slice("&",0))
		var rows:Array=[]
		for n in range(after,mini(total,after+50)):rows.append({"claimed":false,"reward":{"id":str(n+1)}})
		return {"ok":true,"body":{"data":{"rewards":rows,"more":after+50<total,"next":str(mini(total,after+50))}}}

class CapacityTransport extends Real:
	var reads:=0
	var status:=413
	func request_api(_path:String,_method:int=HTTPClient.METHOD_GET,_body:Dictionary={})->Dictionary:
		reads+=1
		return {"ok":false,"status":status,"body":{"error":"snapshot_too_large"}}

class DelayedTransport extends Real:
	var batch:Dictionary={}
	var environment_ticket:=Ticket.new()
	var definition_ticket:=Ticket.new()
	var delay_definition:=false
	func _read_runtime_batch()->Dictionary:return batch
	func _receive_world_snapshot(_body:Dictionary)->void:pass
	func request_api(path:String,_method:int=HTTPClient.METHOD_GET,_body:Dictionary={})->Dictionary:
		if path=="/v1/environment":return await environment_ticket.finished
		if path.begins_with("/v1/gameplay/definition") and delay_definition:return await definition_ticket.finished
		return {"ok":true,"body":{"data":world_session}}

class EventTransport extends Node:
	var world_session:Dictionary={"map_ref":"test/map"}
	var _network_actions:Array=[]
	var polls:=0
	var acks:=0
	func context()->Dictionary:return {"session_epoch":1}
	func is_world_ready()->bool:return true
	func request_api(path:String,_method:int=HTTPClient.METHOD_GET,_body:Dictionary={})->Dictionary:
		if path.ends_with("/ack"):
			acks+=1
			return {"ok":acks>1}
		polls+=1
		return {"ok":true,"body":{"data":{"events":[{"cursor":1,"event":{"map":"test/map"}}] if polls==1 else []}}}

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func scope()->Dictionary:return {"boot_id":"boot","session_epoch":1,"map_generation":2,"map_ref":"test/map"}
func frame(revision:int,full:bool=true)->Dictionary:
	var resources:Dictionary={}
	for name:String in Snapshot.RESOURCES:
		resources[name]={"version":"a".repeat(64)}
		if full:resources[name].data=[] if name=="entities" else {}
	return {"ok":true,"schema":1,"revision":revision,"world_context":scope(),"game_time_us":revision*1000000,"server_elapsed":float(revision),"resources":resources}
func collect_full(transport:Node,result:Dictionary)->void:result.value=await transport.refresh_world_snapshots();result.done=true
func collect_hydrate(transport:Node,result:Dictionary)->void:result.value=await transport.gameplay.projection.hydrate();result.done=true

func run()->void:
	var cache:=Snapshot.new();cache.known(scope())
	var first:=frame(1);first.resources.entities.data=[{"uuid":"npc","state":{"generation":4}}]
	var result:Dictionary=cache.apply(first,scope())
	check(result.ok and result.changed.size()==13,"full resource set accepted")
	result=cache.apply(frame(2,false),scope())
	check(result.ok and result.changed.is_empty() and result.snapshots.entities.size()==1 and result.snapshots.statuses.game_time_us==2000000,"unchanged resources retained while clock advances")
	var hidden:=frame(3,false);hidden.resources.entities={"version":"b".repeat(64),"data":[]}
	check(cache.apply(hidden,scope()).ok and cache.snapshots.entities.is_empty(),"explicit empty set clears old NPCs")
	check(cache.apply(first,scope()).get("ignored",false) and cache.snapshots.entities.is_empty(),"late full snapshot cannot resurrect old NPC")
	var invalid:=frame(4,false);invalid.resources.inventory={"version":"c".repeat(64),"data":{"sequence":9}};invalid.resources.entities.data=null
	result=cache.apply(invalid,scope())
	check(not result.ok and cache.revision==3 and not cache.snapshots.inventory.has("sequence"),"invalid resource causes no partial publication")
	result=cache.apply(frame(5,false),scope())
	check(result.get("need_full",false) and cache.revision==3,"conditional base replaced by parallel response requires full recovery")
	var older_context:=frame(100);older_context.world_context.map_generation=1
	check(not cache.apply(older_context,scope()).ok and cache.revision==3,"older world context rejected even with high revision")
	var zero_scope:=scope();zero_scope.map_generation=0
	var zero_frame:=frame(1);zero_frame.world_context.erase("map_generation")
	var zero_cache:=Snapshot.new();zero_cache.known(zero_scope)
	check(zero_cache.apply(zero_frame,zero_scope).ok,"protobuf JSON omitted zero map generation preserves valid context")
	var pages:=PagingTransport.new()
	result=await pages._read_rewards()
	check(result.ok and result.body.data.rewards.size()==1024 and pages.reads==21,"1024 legal pending rewards recover across 21 bounded pages")
	pages.legacy=true;pages.reads=0;pages.total=1;pages._unclaimed_rewards_supported=0
	result=await pages._read_rewards()
	check(result.ok and pages.reads==2 and pages._unclaimed_rewards_supported==-1,"old server rejecting new reward filter uses historical endpoint")
	pages.free()
	var capacity:=CapacityTransport.new();capacity.world_session=scope()
	result=await capacity._read_runtime_batch()
	var again:Dictionary=await capacity._read_runtime_batch()
	check(result.get("capacity_fallback",false) and again.get("legacy",false) and capacity.reads==1 and capacity._runtime_snapshot.versions.is_empty(),"oversized batch uses bounded endpoints and suppresses repeated oversized reads")
	capacity.world_session.map_generation=3
	await capacity._read_runtime_batch()
	check(capacity.reads==2,"world context change retries batch capability")
	capacity._runtime_snapshot.clear();capacity.status=404;capacity.reads=0
	await capacity._read_runtime_batch();await capacity._read_runtime_batch()
	check(capacity.reads==1 and capacity._runtime_snapshot.supported==-1,"old server capability fallback is remembered")
	capacity.free()
	var event_transport:=EventTransport.new();var gameplay:=Gameplay.new(event_transport)
	await gameplay.poll_events();gameplay._events_at=0
	await gameplay.poll_events();gameplay._events_at=0
	await gameplay.poll_events()
	check(event_transport.acks==2 and gameplay._event_acked==1 and event_transport._network_actions.size()==1,"lost ACK retries; empty polls after successful ACK do not resend or replay event")
	event_transport.free()
	var delayed:=DelayedTransport.new();root.add_child(delayed);delayed.world_session=scope()
	delayed._runtime_snapshot.known(scope());delayed.batch=delayed._runtime_snapshot.apply(frame(1),scope())
	var waiting:={"done":false};collect_full(delayed,waiting)
	var newer:=frame(2);newer.resources["combat-state"].data={"hp":77};newer.resources["combat-state"].version="b".repeat(64)
	delayed._runtime_snapshot.apply(newer,scope());delayed._snapshot_read_serial=2;delayed._publish_runtime_cache(scope(),2)
	delayed.environment_ticket.resolve({"ok":true,"body":{}})
	await process_frame
	check(waiting.done and waiting.value.ok and delayed.business_snapshots["combat-state"].hp==77 and delayed._snapshot_published_serial==2,"old full refresh waiting on HTTP cannot overwrite newer published batch")
	delayed.delay_definition=true;delayed.business_snapshots={"entities":[{"uuid":"old","kind":"creatures","definition":"old-def"}]};delayed._snapshot_published_serial=3
	var hydration:={"done":false};collect_hydrate(delayed,hydration)
	delayed.business_snapshots={"entities":[{"uuid":"new","kind":"creatures","definition":"new-def"}],"skills":{"grants":{"tank":true}}};delayed._snapshot_published_serial=4
	delayed.gameplay.projection.definitions["creatures:new-def"]={"name":"new"}
	var effect:={"type":"threat","threat":{"flat":10,"reduction_bp":0}}
	delayed.gameplay.projection.definitions["skills:tank"]={"target":{"mode":"unit"},"effects":[effect]}
	result=await delayed.gameplay.projection.hydrate()
	check(result.ok and delayed.skill_catalog.get_skill("tank").effects==[effect] and delayed.skill_catalog.get_skill("tank").requires_target,"new hostile threat skill fields survive client projection")
	delayed.definition_ticket.resolve({"ok":true,"body":{"data":{"name":"old"}}})
	await process_frame
	check(hydration.done and not hydration.value.ok and delayed.gameplay.projection.entities.has("new") and not delayed.gameplay.projection.entities.has("old"),"delayed old hydration cannot clear or overwrite newer NPC projection")
	delayed.queue_free()
	print("RUNTIME_SNAPSHOT_TESTS failures=",failures);quit(0 if failures==0 else 1)
