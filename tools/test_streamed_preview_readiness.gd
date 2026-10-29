extends SceneTree
## CPU protocol test only: callbacks, texture identities and engine observations
## are controlled stubs. This cannot prove GPU feedback, residency or pixels.
const CONTROLLER_PATH:="res://scripts/world_editor/streamed_preview_readiness.gd"
var checks:=0
var failures:=0

class Collector extends RefCounted:
	var textures:Array=[]
	func capture(values:Array[Texture2D])->void:
		textures.clear()
		for texture:Texture2D in values:textures.append(weakref(texture))
	func live_textures()->Array[Texture2D]:
		var values:Array[Texture2D]=[]
		for ref:WeakRef in textures:
			var texture:Texture2D=ref.get_ref()
			if texture!=null:values.append(texture)
		return values
	func has_textures()->bool:return not textures.is_empty()
	func snapshot()->Dictionary:return {"textures":textures.size()}

class Backend extends RefCounted:
	var next_id:=40
	var begun:Array=[]
	var cancelled:Array=[]
	var queries:Array=[]
	var query_count:=0
	var max_queries:=0
	var events:Array=[]
	var viewport:WeakRef
	var begin_before_draw:=true
	func begin_texture_observation(textures:Array)->int:
		next_id+=1
		var ids:Array=[]
		for texture:Texture2D in textures:ids.append(texture.get_instance_id())
		begun.append({"id":next_id,"textures":ids})
		var target:SubViewport=viewport.get_ref()
		begin_before_draw=begin_before_draw and target!=null and target.render_target_update_mode==SubViewport.UPDATE_DISABLED
		events.append("begin")
		return next_id
	func query_texture_observation(id:int,callback:Callable)->void:
		queries.append({"id":id,"callback":callback});query_count+=1
		max_queries=maxi(max_queries,queries.size());events.append("query")
	func cancel_texture_observation(id:int)->void:
		cancelled.append(id);events.append("cancel")
	func deliver(result:Dictionary)->Callable:
		if queries.is_empty():return Callable()
		var query:Dictionary=queries.pop_front()
		query.callback.call(result)
		return query.callback

class MissingQuery extends RefCounted:
	var begins:=0
	func begin_texture_observation(_textures:Array)->int:begins+=1;return 9
	func cancel_texture_observation(_id:int)->void:pass

class Harness extends RefCounted:
	var consumer:Node
	var viewport:SubViewport
	var collector:=Collector.new()
	var backend:=Backend.new()
	var controller:RefCounted
	var textures:Array[Texture2D]=[]
	var draws:Array=[]
	var results:Array=[]
	var events:Array=[]
	var draw_requested:=true
	func schedule_draw(callback:Callable)->void:
		draw_requested=draw_requested and viewport.render_target_update_mode==SubViewport.UPDATE_ONCE
		draws.append(callback);events.append("draw")
	func completed(result:Dictionary)->void:results.append(result.duplicate(true))
	func start()->void:controller.start(viewport,consumer,collector,completed)
	func draw()->Callable:
		if draws.is_empty():return Callable()
		var callback:Callable=draws.pop_front()
		viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		callback.call()
		return callback
	func dispose()->void:
		controller.cancel();controller=null
		draws.clear();backend.queries.clear();textures.clear();collector.textures.clear()
		if is_instance_valid(consumer):consumer.free()
		if is_instance_valid(viewport):viewport.free()

func check(value:bool,label:String)->void:
	checks+=1;print("PASS " if value else "FAIL ",label)
	if not value:failures+=1

func _initialize()->void:run.call_deferred()

func fixture(texture_count:int=2)->Harness:
	var value:=Harness.new()
	value.consumer=Node.new();root.add_child(value.consumer)
	value.viewport=SubViewport.new();root.add_child(value.viewport)
	value.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	for i:int in texture_count:value.textures.append(PlaceholderTexture2D.new())
	value.collector.capture(value.textures)
	value.backend.events=value.events;value.backend.viewport=weakref(value.viewport)
	value.controller=load(CONTROLLER_PATH).new()
	value.controller.backend=value.backend;value.controller.after_drawn=value.schedule_draw
	return value

func row(texture:Texture2D,mip:int=1,decision:int=1,reload:int=1)->Dictionary:
	return {"texture_id":texture.get_instance_id(),"valid":true,"visible_demand":true,
		"status":"ready","ready":true,"request_mip":mip,"desired_mip":mip,"fit_mip":mip,
		"current_mip":mip,"pending_mip":-1,"executing":false,"stable":true,
		"decision_version":decision,"reload_version":reload,"budget_limited":false}

func observation(value:Harness,rows:Array=[],ready:bool=true,covered:bool=true)->Dictionary:
	if rows.is_empty():
		for i:int in value.textures.size():rows.append(row(value.textures[i],i+1))
	return {"observation_id":value.controller.snapshot().observation_id,
		"target_generation":7,"completed_generation":7 if covered else 6,
		"covered":covered,"ready":ready,"textures":rows}

func query_ready(value:Harness,label:String)->bool:
	for i:int in 4:
		if not value.backend.queries.is_empty():break
		value.controller.pump()
	var ready:=value.backend.queries.size()==1
	check(ready,label+": exactly one query available")
	return ready

func draw_ready(value:Harness,label:String)->bool:
	for i:int in 4:
		if not value.draws.is_empty():break
		value.controller.pump()
	var ready:=value.draws.size()==1
	check(ready,label+": exactly one draw queued")
	return ready

func first_query(value:Harness,label:String)->bool:
	value.start()
	check(value.backend.begun.is_empty() and value.draws.is_empty(),label+": start only queues work")
	if not draw_ready(value,label):return false
	check(value.backend.begin_before_draw and value.draw_requested and value.events.slice(0,2)==["begin","draw"],label+": observation begins before UPDATE_ONCE and draw registration")
	check(value.backend.queries.is_empty(),label+": no query before a completed draw")
	value.draw()
	return query_ready(value,label)

func finish_confirmation(value:Harness,data:Dictionary,label:String)->void:
	check(value.results.is_empty(),label+": ready observation alone is not a captured frame")
	if not draw_ready(value,label):return
	value.draw()
	if not query_ready(value,label):return
	value.backend.deliver(data)
	for i:int in 3:value.controller.pump()
	check(value.results.size()==1 and value.results[0].get("ok",false),label+": matching post-draw observation completes once")
	check(not value.controller.snapshot().active,label+": caller can stop processing after completion")
	check(value.backend.cancelled.count(data.observation_id)==1,label+": completed ticket is released exactly once")

func pending_case()->void:
	var value:=fixture()
	if first_query(value,"pending"):
		var waiting:=observation(value,[],false,false)
		for item:Dictionary in waiting.textures:item.ready=false;item.status="waiting_feedback"
		value.backend.deliver(waiting)
		for i:int in 30:value.controller.pump()
		check(value.results.is_empty() and value.controller.snapshot().active,"pending feedback never succeeds after an arbitrary frame count")
		check(value.backend.queries.size()==1 and value.backend.max_queries==1 and value.controller.snapshot().query_inflight,"repeated pumps keep only one query in flight")
		var ready:=observation(value)
		value.backend.deliver(ready)
		finish_confirmation(value,ready,"mixed texture mips 1 and 2")
	value.dispose()

func versions_case()->void:
	var value:=fixture()
	if first_query(value,"versions"):
		var initial:=observation(value)
		var replay:=value.backend.deliver(initial)
		if replay.is_valid():replay.call(initial)
		if draw_ready(value,"versions"):
			var draw_replay:=value.draw()
			if draw_replay.is_valid():draw_replay.call()
			if query_ready(value,"versions"):
				var changed:=initial.duplicate(true)
				changed.textures[1].decision_version=2;changed.textures[1].reload_version=2
				value.backend.deliver(changed)
				check(value.results.is_empty(),"same mip with newer decision/reload versions requires another captured frame")
				finish_confirmation(value,changed,"changed versions")
				if replay.is_valid():replay.call(initial)
				if draw_replay.is_valid():draw_replay.call()
				for i:int in 3:value.controller.pump()
				check(value.results.size()==1 and value.backend.max_queries==1,"duplicate query/draw callbacks cannot finish twice or overlap queries")
	value.dispose()

func no_demand_case()->void:
	var value:=fixture()
	if first_query(value,"no demand"):
		var data:=observation(value)
		var ignored:Dictionary=data.textures[1]
		ignored.visible_demand=false;ignored.status="no_visible_demand"
		ignored.fit_mip=0;ignored.current_mip=3;ignored.pending_mip=2;ignored.executing=true;ignored.stable=false
		value.backend.deliver(data)
		var changed:=data.duplicate(true)
		changed.textures[1].decision_version=99;changed.textures[1].reload_version=99
		changed.textures[1].current_mip=2;changed.textures[1].pending_mip=1
		finish_confirmation(value,changed,"covered no-demand texture ignores mip, IO and version changes")
	value.dispose()

func budget_case()->void:
	var value:=fixture()
	if first_query(value,"budget fit"):
		var data:=observation(value)
		var limited:Dictionary=data.textures[0]
		limited.status="budget_limited";limited.budget_limited=true
		limited.request_mip=0;limited.desired_mip=0;limited.fit_mip=2;limited.current_mip=2
		value.backend.deliver(data)
		finish_confirmation(value,data,"budget-limited fitted mip is final without forcing mip zero")
	value.dispose()

func readiness_gate_case(kind:String)->void:
	var value:=fixture()
	if first_query(value,kind):
		var data:=observation(value)
		match kind:
			"uncovered":data.covered=false
			"not_ready":data.ready=false
			"second_pending":data.textures[1].pending_mip=0
			"second_executing":data.textures[1].executing=true
			"second_unstable":data.textures[1].stable=false
			"second_wrong_fit":data.textures[1].current_mip=3
			"second_not_ready":data.textures[1].ready=false
			"second_no_version":data.textures[1].erase("reload_version")
		value.backend.deliver(data)
		for i:int in 8:value.controller.pump()
		check(value.results.is_empty() and value.draws.is_empty() and value.controller.snapshot().active,kind+": one unresolved part blocks final redraw and success")
		check(value.backend.queries.size()==1 and value.backend.max_queries==1,kind+": waiting remains bounded to one query")
		var ready:=observation(value);value.backend.deliver(ready)
		finish_confirmation(value,ready,kind+" resolves")
	value.dispose()

func cancel_restart_case()->void:
	var value:=fixture()
	if first_query(value,"cancel and restart"):
		var old_result:=observation(value)
		var old_query:Dictionary=value.backend.queries.pop_front()
		value.controller.cancel()
		check(not value.controller.snapshot().active and value.results.is_empty(),"hide cancellation stops processing without publishing success")
		check(value.backend.cancelled==[old_result.observation_id],"cancellation retires only its own observation ticket")
		value.start()
		if draw_ready(value,"restart"):
			var next_id:int=value.controller.snapshot().observation_id
			old_query.callback.call(old_result)
			check(value.results.is_empty() and next_id!=old_result.observation_id and value.controller.snapshot().observation_id==next_id,"late query from hidden generation cannot modify restarted observation")
			var old_draw:=value.draw()
			if query_ready(value,"restart"):
				var current:=observation(value);value.backend.deliver(current)
				finish_confirmation(value,current,"restart completes its own generation")
				if old_draw.is_valid():old_draw.call()
				check(value.results.size()==1,"late restart draw cannot republish completed result")
	value.dispose()

func teardown_case(viewport_exit:bool,query_pending:bool)->void:
	var value:=fixture();var label:=("viewport free" if viewport_exit else "consumer exit")+(" during query" if query_pending else " during draw")
	value.start()
	if draw_ready(value,label):
		var id:int=value.controller.snapshot().observation_id
		var late_draw:Callable
		var late_query:Dictionary={};var data:=observation(value)
		if query_pending:
			value.draw()
			if query_ready(value,label):late_query=value.backend.queries.pop_front()
		else:late_draw=value.draws.pop_front()
		if viewport_exit:value.viewport.free();value.viewport=null
		else:root.remove_child(value.consumer)
		value.controller.pump()
		if late_draw.is_valid():late_draw.call()
		if not late_query.is_empty():late_query.callback.call(data)
		check(not value.controller.snapshot().active and value.results.is_empty() and value.backend.queries.is_empty(),label+": late callback cannot query or complete")
		check(value.backend.cancelled.count(id)==1,label+": ticket is cancelled exactly once")
	value.dispose()

func independent_tickets_case()->void:
	var first:=fixture();var second:=fixture()
	second.backend=first.backend;second.controller.backend=first.backend
	first.start();second.start()
	if draw_ready(first,"first independent ticket") and draw_ready(second,"second independent ticket"):
		first.draw();second.draw();first.controller.pump();second.controller.pump()
		var first_id:int=first.controller.snapshot().observation_id
		var second_id:int=second.controller.snapshot().observation_id
		check(first_id!=second_id and first.backend.queries.size()==2,"two controllers may each own one query on the same engine backend")
		if first.backend.queries.size()==2:
			var abandoned:Dictionary=first.backend.queries.pop_front();var old:=observation(first)
			first.controller.cancel();abandoned.callback.call(old)
			check(first.backend.cancelled==[first_id] and second.controller.snapshot().active and second.controller.snapshot().observation_id==second_id,"cancelling one controller leaves its sibling observation active")
			var ready:=observation(second);second.backend.deliver(ready)
			finish_confirmation(second,ready,"sibling after cancellation")
			check(first.results.is_empty() and first.backend.cancelled==[first_id,second_id],"each observation is retired once without cross-controller completion")
	first.dispose();second.dispose()

func no_textures_case()->void:
	var value:=fixture(0);value.controller.backend=RefCounted.new()
	value.start()
	if draw_ready(value,"no textures"):
		check(value.backend.begun.is_empty() and value.results.is_empty(),"no textures draw needs no engine observation API")
		value.draw()
		for i:int in 4:value.controller.pump()
		check(value.results.size()==1 and value.results[0].get("ok",false) and not value.controller.snapshot().active,"no textures completes after exactly one acknowledged draw")
		check(value.draws.is_empty(),"no textures never schedules a confirmation draw")
	value.dispose()

func explicit_failure_case(kind:String)->void:
	var value:=fixture()
	if kind=="missing_api":value.controller.backend=RefCounted.new()
	elif kind=="partial_api":value.controller.backend=MissingQuery.new()
	elif kind=="dead_textures":value.textures.clear()
	elif kind=="partial_textures":value.textures.remove_at(1)
	if kind in ["missing_api","partial_api","dead_textures","partial_textures"]:
		value.start()
		for i:int in 4:value.controller.pump()
	else:
		if first_query(value,kind):
			var data:=observation(value)
			match kind:
				"wrong_ticket":data.observation_id+=100
				"missing_texture":data.textures.remove_at(1)
				"duplicate_texture":data.textures[1]=data.textures[0].duplicate()
				"foreign_texture":data.textures[1].texture_id+=1000000
				"unavailable":data.textures[1].status="unavailable"
				"invalid_texture":data.textures[1].valid=false
			value.backend.deliver(data)
			for i:int in 4:value.controller.pump()
	check(value.results.size()==1 and not value.results[0].get("ok",true),kind+": invalid observation fails explicitly")
	if not value.results.is_empty():check(not str(value.results[0].get("error","")).is_empty() and value.results[0].get("error_code",OK)!=OK,kind+": failure includes error and error_code")
	check(not value.controller.snapshot().active,kind+": failed controller is inactive")
	value.dispose()

func late_deadline_case(query_pending:bool)->void:
	var value:=fixture();var label:="query callback" if query_pending else "draw callback"
	value.start()
	if draw_ready(value,label+" deadline"):
		if query_pending:value.draw()
		if not query_pending or query_ready(value,label+" deadline"):
			# Move only this private fixture's deadline; no sleep or frame-count
			# success approximation is involved in exercising the callback gate.
			value.controller._deadline=Time.get_ticks_msec()
			if query_pending:value.backend.deliver(observation(value))
			else:value.draw()
			check(value.results.size()==1 and not value.results[0].get("ok",true) and value.results[0].get("error_code",OK)==ERR_TIMEOUT,label+": expired operation fails before the next pump")
			check(not value.controller.snapshot().active,label+": deadline failure retires the controller")
	value.dispose()

func real_engine_capability_case()->void:
	var backend_:Object=Engine.get_singleton("TextureStreaming") if Engine.has_singleton("TextureStreaming") else null
	var available:=backend_!=null
	for method:String in ["begin_texture_observation","query_texture_observation","cancel_texture_observation"]:
		available=available and backend_.has_method(method)
	if available:
		print("REAL_ENGINE_OBSERVATION_API available; absent-API behavior uses the dedicated protocol stubs")
		return
	var value:=fixture();value.controller.backend=null;value.start()
	for i:int in 4:value.controller.pump()
	check(value.results.size()==1 and not value.results[0].get("ok",true) and value.results[0].get("error_code",OK)==ERR_UNAVAILABLE,"actual installed engine without observation API reports explicit unsupported failure")
	check(value.draws.is_empty() and not value.controller.snapshot().active,"unsupported real engine neither captures a frame nor remains active")
	value.dispose()

func run()->void:
	if not FileAccess.file_exists(CONTROLLER_PATH):printerr("Readiness controller is not installed");quit(2);return
	pending_case();versions_case();no_demand_case();budget_case();cancel_restart_case()
	for kind:String in ["uncovered","not_ready","second_pending","second_executing","second_unstable","second_wrong_fit","second_not_ready","second_no_version"]:readiness_gate_case(kind)
	for viewport_exit:bool in [false,true]:
		for query_pending:bool in [false,true]:teardown_case(viewport_exit,query_pending)
	independent_tickets_case();no_textures_case();real_engine_capability_case()
	late_deadline_case(false);late_deadline_case(true)
	for kind:String in ["missing_api","partial_api","dead_textures","partial_textures","wrong_ticket","missing_texture","duplicate_texture","foreign_texture","unavailable","invalid_texture"]:explicit_failure_case(kind)
	print("STREAMED_PREVIEW_READINESS_CPU checks=",checks," failures=",failures," protocol_stub=true gpu_proven=false")
	quit(0 if failures==0 else 1)
