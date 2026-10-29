extends RefCounted
## One finite observation of an already prepared private preview. The ticket
## owns no textures; scene/material discovery belongs to the weak collector.
## Call pump from normal processing, before the target frame_pre_draw.
var backend:Object
var after_drawn:Callable
var timeout_msec:=30000
var _viewport:WeakRef
var _consumer:WeakRef
var _collector:WeakRef
var _completed:Callable
var _engine:Object
var _ticket:=0
var _serial:=0
var _query_serial:=0
var _state:="idle"
var _deadline:=0
var _ids:Dictionary={}
var _proof:Dictionary={}
var profile:={"begins":0,"queries":0,"draws":0,"retries":0,"cancels":0}

func start(viewport:SubViewport,consumer:Node,collector:RefCounted,completed:Callable)->void:
	cancel()
	_viewport=weakref(viewport);_consumer=weakref(consumer);_collector=weakref(collector)
	_completed=completed;_deadline=Time.get_ticks_msec()+timeout_msec;_state="start"

func active()->bool:return _state not in ["idle","complete","failed"]

func pump()->void:
	if not active():return
	if not _alive():cancel();return
	if Time.get_ticks_msec()>=_deadline:
		_finish(false,"纹理预览准备超时",ERR_TIMEOUT);return
	match _state:
		"start":_begin()
		"query":_query(false)
		"redraw":_draw("drawing_verified")
		"verify":_query(true)

func _alive()->bool:
	var consumer:Node=_consumer.get_ref() if _consumer!=null else null
	var viewport:SubViewport=_viewport.get_ref() if _viewport!=null else null
	return consumer!=null and consumer.is_inside_tree() and not consumer.is_queued_for_deletion() and viewport!=null and viewport.is_inside_tree() and not viewport.is_queued_for_deletion()

func _begin()->void:
	var collector:RefCounted=_collector.get_ref() if _collector!=null else null
	if collector==null:
		_finish(false,"预览纹理已释放",ERR_UNAVAILABLE);return
	var textures:Array[Texture2D]=collector.live_textures()
	if collector.has_method("snapshot") and int(collector.snapshot().get("textures",textures.size()))!=textures.size():
		_finish(false,"预览纹理已释放",ERR_UNAVAILABLE);return
	if textures.is_empty():
		if collector.has_textures():_finish(false,"预览纹理已释放",ERR_UNAVAILABLE)
		else:_draw("drawing_plain")
		return
	_engine=backend if backend!=null else (Engine.get_singleton("TextureStreaming") if Engine.has_singleton("TextureStreaming") else null)
	for method:String in ["begin_texture_observation","query_texture_observation","cancel_texture_observation"]:
		if _engine==null or not _engine.has_method(method):
			_finish(false,"当前引擎不支持流式纹理预览就绪检查",ERR_UNAVAILABLE);return
	for texture:Texture2D in textures:_ids[texture.get_instance_id()]=true
	_ticket=int(_engine.call("begin_texture_observation",textures))
	if _ticket<=0:
		_finish(false,"流式纹理预览观察不可用",ERR_UNAVAILABLE);return
	profile.begins+=1
	# Begin must precede UPDATE_ONCE. The first progressive image is allowed;
	# its real feedback, then a verified redraw, determine final completion.
	_draw("drawing_initial")

func _draw(phase:String)->void:
	var viewport:SubViewport=_viewport.get_ref()
	_state=phase;profile.draws+=1
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	var callback:=_drawn.bind(_serial,phase)
	if after_drawn.is_valid():after_drawn.call(callback)
	else:preload("res://scripts/util/frame_presentation.gd").after_drawn(callback)

func _drawn(serial:int,phase:String)->void:
	if serial!=_serial or _state!=phase:return
	if not _alive():cancel();return
	if Time.get_ticks_msec()>=_deadline:_finish(false,"纹理预览准备超时",ERR_TIMEOUT);return
	if phase=="drawing_plain":_finish(true)
	else:_state="verify" if phase=="drawing_verified" else "query"

func _query(verifying:bool)->void:
	_state="await_query";_query_serial+=1;profile.queries+=1
	_engine.call("query_texture_observation",_ticket,_queried.bind(_serial,_query_serial,verifying))

func _queried(result:Dictionary,serial:int,query_serial:int,verifying:bool)->void:
	if serial!=_serial or query_serial!=_query_serial or _state!="await_query":return
	if not _alive():cancel();return
	if Time.get_ticks_msec()>=_deadline:_finish(false,"纹理预览准备超时",ERR_TIMEOUT);return
	var sample:=_sample(result)
	if not sample.error.is_empty():_finish(false,sample.error,ERR_UNAVAILABLE);return
	if not sample.ready:
		_proof.clear();_state="query";return
	if verifying and _same_proof(_proof,sample.rows):
		_finish(true);return
	if verifying:profile.retries+=1
	_proof=sample.rows;_state="redraw"

func _sample(result:Dictionary)->Dictionary:
	var sample:={"error":"","ready":false,"rows":{}}
	if int(result.get("observation_id",0))!=_ticket or not result.get("textures") is Array:
		sample.error="流式纹理观察结果无效";return sample
	var rows:Dictionary={};var ready:bool=result.get("covered",false) and result.get("ready",false)
	for row:Variant in result.textures:
		if not row is Dictionary:
			sample.error="流式纹理观察结果无效";return sample
		var id:=int(row.get("texture_id",0))
		if not _ids.has(id) or rows.has(id) or not row.get("valid",false) or row.get("status","")=="unavailable":
			sample.error="预览纹理已失效";return sample
		var demand:bool=row.get("visible_demand",false)
		var row_ready:bool=row.get("ready",false)
		if demand:
			row_ready=row_ready and row.get("stable",false) and not row.get("executing",true) and int(row.get("pending_mip",0))==-1 and int(row.get("current_mip",-1))>=0 and row.get("current_mip") == row.get("fit_mip")
			row_ready=row_ready and row.has("decision_version") and row.has("reload_version")
		else:row_ready=row_ready and row.get("status","")=="no_visible_demand"
		ready=ready and row_ready
		# Scalars only: neither state samples nor callbacks retain texture owners.
		rows[id]={"demand":demand,"decision":row.get("decision_version"),"reload":row.get("reload_version"),"fit":row.get("fit_mip"),"current":row.get("current_mip")}
	if rows.size()!=_ids.size():sample.error="预览纹理观察不完整";return sample
	sample.ready=ready;sample.rows=rows;return sample

func _same_proof(before:Dictionary,after:Dictionary)->bool:
	if before.size()!=after.size():return false
	for id:int in before:
		if not after.has(id) or before[id].demand!=after[id].demand:return false
		# No-demand belongs to the marked feedback period, not this viewport.
		# Unrelated reloads do not delay these valid, covered rows.
		if after[id].demand and before[id]!=after[id]:return false
	return true

func _finish(ok:bool,error:String="",error_code:int=OK)->void:
	var completed:=_completed
	cancel();_state="complete" if ok else "failed"
	if completed.is_valid():completed.call({"ok":ok,"error":error,"error_code":error_code})

func cancel()->void:
	_serial+=1
	if _ticket>0 and is_instance_valid(_engine):
		_engine.call("cancel_texture_observation",_ticket);profile.cancels+=1
	var viewport:SubViewport=_viewport.get_ref() if _viewport!=null else null
	if viewport!=null:viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	_ticket=0;_state="idle";_engine=null;_viewport=null;_consumer=null;_collector=null
	_completed=Callable();_ids.clear();_proof.clear()

func snapshot()->Dictionary:
	return {"state":_state,"active":active(),"observation_id":_ticket,"query_inflight":_state=="await_query","profile":profile.duplicate()}
