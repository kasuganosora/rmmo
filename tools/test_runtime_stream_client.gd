extends SceneTree
const Real=preload("res://scripts/net/real_server.gd")
const Snapshot=preload("res://scripts/net/remote/runtime_snapshot.gd")
class StreamProjection extends RefCounted:
	var calls:=0
	var failures:=0
	var gate:RefCounted
	func hydrate()->Dictionary:
		calls+=1
		if gate!=null:
			var wait:RefCounted=gate;gate=null
			await wait.finished
		if failures>0:failures-=1;return {"ok":false,"error":"definition_temporarily_unavailable"}
		return {"ok":true}
	func actions()->Array:return []
	func reset()->void:pass
class StreamTransport extends Real:
	var acknowledgements:Array=[]
	var published:=0
	func is_world_ready()->bool:return true
	func _send(operation:String,body:Dictionary)->Ticket:
		if operation=="runtime_stream":acknowledgements.append(body.duplicate(true))
		var ticket:=Ticket.new();ticket.resolve({"ok":true});return ticket
	func _project_snapshots()->void:published+=1
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func scope(epoch:int=1)->Dictionary:return {"boot_id":"boot","session_epoch":epoch,"map_generation":2,"map_ref":"test/map"}
func frame(revision:int,epoch:int=1)->Dictionary:
	var resources:Dictionary={}
	for name:String in Snapshot.RESOURCES:resources[name]={"version":"a".repeat(64),"data":[] if name=="entities" else {}}
	return {"ok":true,"schema":1,"revision":revision,"world_context":scope(epoch),"game_time_us":revision*1000000,"server_elapsed":float(revision),"resources":resources}
func packet(revision:int,epoch:int=1)->Dictionary:return {"runtime_stream_protocol":1,"runtime_snapshot_json":JSON.stringify(frame(revision,epoch))}
func peer()->StreamTransport:
	var value:=StreamTransport.new();value.world_session=scope();value.world_session.gameplay_protocol=1
	value.gameplay.projection=StreamProjection.new()
	value.runtime_stream._scope();value.runtime_stream.environment_at=Time.get_ticks_msec()+100000
	return value
func run()->void:
	var value:=peer();var projection:StreamProjection=value.gameplay.projection
	value.runtime_stream.receive(packet(1))
	check(value.runtime_stream.active and value._published_runtime_revision==1 and value.acknowledgements.size()==1,"stream baseline applies and ACKs only accepted capture")
	value.runtime_stream.receive(packet(1))
	check(projection.calls==1 and value.acknowledgements.size()==2,"retransmission is ACKed without repeated projection")
	projection.failures=1;value.runtime_stream.receive(packet(2))
	check(value.runtime_stream.dirty and not value.runtime_stream.projecting,"failed cold definition retains pending projection")
	var before:=projection.calls;value.runtime_stream.tick(Time.get_ticks_msec())
	check(projection.calls==before,"projection retry is bounded by monotonic delay")
	value.runtime_stream.receive(packet(3))
	check(projection.calls==before,"new incoming changes cannot bypass projection retry backoff")
	value.runtime_stream.projection_at=0;value.runtime_stream.tick(Time.get_ticks_msec())
	check(not value.runtime_stream.dirty and value._published_runtime_revision==3 and projection.calls==before+1,"projection retries without requiring another server state change")
	var barrier:=Real.Ticket.new();projection.gate=barrier
	value.runtime_stream.receive(packet(4))
	check(value.runtime_stream.projecting,"old projection waits on cold definition")
	value.world_session=scope(2);value.world_session.gameplay_protocol=1
	value.runtime_stream.reset();value._runtime_snapshot.clear();value._published_runtime_versions.clear()
	value.runtime_stream.receive(packet(5,2))
	check(value.runtime_stream.dirty and value.runtime_stream.projecting,"new world waits while old projection owns its asynchronous latch")
	barrier.resolve({"ok":true})
	value.runtime_stream.environment_at=Time.get_ticks_msec()+100000
	value.runtime_stream.tick(Time.get_ticks_msec())
	check(value._published_runtime_revision==5 and not value.runtime_stream.dirty and not value.runtime_stream.projecting,"new context is projected after old cold load completes without needing another push")
	value.runtime_stream.receive({"runtime_stream_protocol":1,"error":"runtime_snapshot_unavailable"})
	check(value.runtime_stream.active and value.runtime_stream.retry_at==0,"transient server capture failure retains automatic WS retry capability")
	value.runtime_stream.receive({"runtime_stream_protocol":1,"error":"snapshot_too_large"})
	check(not value.runtime_stream.active and value.runtime_stream.retry_at>Time.get_ticks_msec() and value._runtime_snapshot.versions.is_empty(),"capacity notification clears conditional baseline and enables bounded HTTP recovery")
	value.free()
	print("RUNTIME_STREAM_CLIENT_TESTS failures=",failures);quit(0 if failures==0 else 1)
