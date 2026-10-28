extends RefCounted
## One bounded, acknowledged resource stream per world context. HTTP is used
## only for legacy servers and explicit capacity recovery.
var transport:Node
var active:=false
var busy:=false
var revision:=0
var retry_at:=0
var environment_at:=0
var environment_busy:=false
var scope:Dictionary={}
var projecting:=false
var dirty:=false
var projection_at:=0

func _init(owner:Node)->void:transport=owner
func enabled()->bool:return transport.world_session.get("gameplay_protocol",0)==1
func reset()->void:
	active=false;busy=false;revision=0;retry_at=0;environment_at=0;environment_busy=false;scope.clear();dirty=false;projection_at=0
func _scope()->void:
	if scope!=transport.context():reset();scope=transport.context().duplicate(true)
func tick(now:int)->void:
	_scope()
	if not enabled():return
	if dirty and not projecting and now>=projection_at:_project()
	if now>=environment_at and not environment_busy:
		environment_at=now+int(clampf(float(ProjectSettings.get_setting("rmmo/network/environment_interval_sec",5.)),1.,60.)*1000.)
		_calibrate()
func _calibrate()->void:
	environment_busy=true;var context:=scope.duplicate();var connection:int=transport._connection_revision
	var sky:Dictionary=await transport._read_runtime_environment()
	if connection==transport._connection_revision and context==transport.context():
		environment_busy=false
		if sky.ok:transport.business_snapshots.environment=sky.body.duplicate(true)
func read()->Dictionary:
	_scope()
	if Time.get_ticks_msec()<retry_at:return {"ok":true,"http_fallback":true}
	while busy:
		await transport.get_tree().process_frame
		if scope!=transport.context():return {"ok":false,"error":"stale_gameplay_snapshot"}
	busy=true;var context:=scope.duplicate();var connection:int=transport._connection_revision
	var result:Dictionary=await transport.rpc_call("runtime_stream",{"protocol":1,"ack_revision":revision,"resync":not active})
	if connection!=transport._connection_revision or context!=transport.context():return {"ok":false,"error":"stale_gameplay_snapshot"}
	busy=false
	if result.get("error")=="snapshot_too_large":return {"ok":true,"http_fallback":true}
	if not result.get("ok",false):return result
	if transport._runtime_snapshot.revision<=0:return {"ok":false,"error":"snapshot_base_missing"}
	return {"ok":true,"snapshots":transport._runtime_snapshot.snapshots.duplicate(true),"revision":transport._runtime_snapshot.revision}
func receive(message:Dictionary)->void:
	_scope()
	if not enabled() or message.get("runtime_stream_protocol",0)!=1:return
	if message.get("error")=="snapshot_too_large":
		active=false;revision=0
		retry_at=Time.get_ticks_msec()+int(clampf(float(ProjectSettings.get_setting("rmmo/network/snapshot_capacity_retry_sec",30.)),1.,300.)*1000.)
		transport._runtime_snapshot.clear();transport._published_runtime_versions.clear()
		transport._snapshot_at=0
		return
	var json:=str(message.get("runtime_snapshot_json",""))
	if json.is_empty():return
	var body:Variant=JSON.parse_string(json)
	if not body is Dictionary:transport.disconnect_server("服务器玩法流格式无效");return
	transport._runtime_snapshot.known(scope)
	var applied:Dictionary=transport._runtime_snapshot.apply(body,scope)
	if applied.get("need_full",false):active=false;revision=0;retry_at=0;return
	if not applied.ok:transport.disconnect_server("服务器玩法流快照无效");return
	active=true;revision=maxi(revision,int(body.revision))
	transport._send("runtime_stream",{"ack_revision":int(body.revision)})
	if not applied.get("ignored",false):
		dirty=true
		if transport.is_world_ready() and not projecting and Time.get_ticks_msec()>=projection_at:_project()
func _project()->void:
	projecting=true;var context:=scope.duplicate();var connection:int=transport._connection_revision
	while dirty and context==transport.context() and connection==transport._connection_revision:
		dirty=false
		transport._snapshot_read_serial+=1
		var published:Dictionary=transport._publish_runtime_cache(context,transport._snapshot_read_serial)
		if not published.ok:break
		var result:Dictionary=await transport.gameplay.projection.hydrate()
		if context!=transport.context() or connection!=transport._connection_revision:break
		if not result.ok:
			dirty=true;projection_at=Time.get_ticks_msec()+int(clampf(float(ProjectSettings.get_setting("rmmo/network/projection_retry_sec",1.)),.1,30.)*1000.);break
		transport._project_snapshots();transport._network_actions.append_array(transport.gameplay.projection.actions())
	projecting=false
