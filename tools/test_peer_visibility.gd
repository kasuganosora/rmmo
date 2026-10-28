extends SceneTree
const Visibility=preload("res://scripts/net/remote/peer_visibility.gd")
const Real=preload("res://scripts/net/real_server.gd")
const Wire=preload("res://scripts/net/protocol/protobuf.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func actor(id:String,generation:int=2,x:float=1.)->Dictionary:
	return {"id":id,"generation":generation,"sequence":0,"location":{"map_ref":"test/map","position_m":{"x":x,"y":0.,"z":0.}}}
func run()->void:
	var visibility=Visibility.new()
	var first:={"revision":1,"full_snapshot":true,"actors":[actor("peer")]}
	var encoded:Dictionary=Wire.encode("ActorVisibility",first)
	var decoded:Dictionary=Wire.decode("ActorVisibility",encoded.bytes)
	check(encoded.ok and decoded.ok and decoded.data.full_snapshot,"visibility protobuf roundtrip")
	check(visibility.apply(decoded.data,"test/map","self").ok and visibility.peers.has("peer"),"full snapshot creates visible peer")
	var hidden:={"revision":2,"hidden":[{"id":"peer","generation":2}]}
	var result:Dictionary=visibility.apply(hidden,"test/map","self")
	check(result.removed==["peer"] and visibility.peers.is_empty(),"temporary hide removes projection")
	check(visibility.apply(first,"test/map","self").get("ignored",false) and visibility.peers.is_empty(),"late snapshot cannot undo hiding")
	check(visibility.apply({"revision":3,"actors":[actor("peer") ]},"test/map","self").ok and visibility.peers.has("peer"),"same generation can reenter visibility")
	result=visibility.apply({"revision":4,"actors":[actor("peer",3)] ,"hidden":[{"id":"peer","generation":2}]},"test/map","self")
	check(result.removed==["peer"] and visibility.peers.peer.generation==3,"new generation replaces retired body atomically")
	visibility.apply({"revision":5,"hidden":[{"id":"peer","generation":2}]},"test/map","self")
	check(visibility.peers.peer.generation==3,"old generation hide cannot delete replacement")
	result=visibility.apply({"revision":7,"actors":[actor("missing")]},"test/map","self")
	check(result.get("gap",false) and visibility.revision==5 and not visibility.peers.has("missing"),"missing delta requires a full recovery")
	visibility.apply({"revision":8,"full_snapshot":true},"test/map","self")
	check(visibility.peers.is_empty() and visibility.revision==8,"empty recovery snapshot clears every peer")
	visibility.apply({"revision":9,"actors":[actor("peer",3,4.)]},"test/map","self")
	visibility.apply({"revision":10,"actors":[actor("peer",3,5.)]},"test/map","self")
	check(visibility.peers.peer.location.position_m.x==5.,"physics updates order even when input sequence stays equal")
	var invalid:=actor("bad");invalid.location.map_ref="other/map"
	result=visibility.apply({"revision":11,"actors":[actor("valid"),invalid]},"test/map","self")
	check(not result.ok and visibility.revision==10 and not visibility.peers.has("valid"),"malformed frame has no partial effects")
	visibility.clear()
	check(visibility.revision==0 and visibility.peers.is_empty(),"new world context resets revision and peers")
	var server:=Real.new();root.add_child(server)
	server._session_character_id="self"
	var state:={"boot_id":"test","session_epoch":4,"map_generation":10,"map_ref":"test/map","ready_token":"ticket","ready":true,"movement_sequence":0,"protocol_version":2,"visibility_protocol":1}
	check(server._valid_session(JSON.parse_string(JSON.stringify(state))),"HTTP JSON float-valued protocol negotiates identically to protobuf integers")
	var bad_version:=state.duplicate();bad_version.visibility_protocol=1.5
	check(not server._valid_session(bad_version),"fractional visibility protocol is rejected")
	server.world_session=state.duplicate(true)
	server._receive({"world_session":state,"actor_3d":actor("self",10),"visibility":first,"ok":true,"push":true})
	server._receive({"world_session":state,"visibility":hidden,"ok":true,"push":true})
	check(not server.actors.has("peer") and not server._retired_actors.has("peer"),"adapter hides without creating a permanent tombstone")
	server._receive({"world_session":state,"actor_left":"peer","actor_left_generation":2,"push":true})
	server._receive({"world_session":state,"visibility":{"revision":3,"actors":[actor("peer")]},"ok":true,"push":true})
	check(server.actors.has("peer"),"legacy departure cannot poison negotiated reentry")
	var old_state:=state.duplicate(true);old_state.ready=false
	server._receive_world_snapshot(JSON.parse_string(JSON.stringify({"data":old_state,"actor_3d":actor("self",10,-20.),"visibility":first})))
	check(server.world_session.ready and server.self_actor.location.position_m.x==1. and server.actors.has("peer"),"late HTTP snapshot cannot rewind Ready, self position or visible peers")
	var transferred:=state.duplicate(true);transferred.session_epoch=5;transferred.map_generation=11;transferred.ready=false
	server._receive({"world_session":transferred,"actor_3d":actor("self",11),"visibility":{"revision":1,"full_snapshot":true},"ok":true,"push":true,"resync":true})
	server._receive({"world_session":state,"visibility":{"revision":900,"full_snapshot":true,"actors":[actor("peer")]},"ok":true,"push":true,"resync":true})
	check(server.world_session.map_generation==11 and not server.actors.has("peer") and server._peer_visibility.revision==1,"old context cannot override a newer transfer with a larger revision")
	server.disconnect_server();server.queue_free()
	print("PEER_VISIBILITY_TESTS failures=",failures);quit(0 if failures==0 else 1)
