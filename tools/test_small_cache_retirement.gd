extends "res://tools/test_prefab_cache_alias_lifetime.gd"
class Marker extends RefCounted:
	var payload:Array=[]
func fill()->Array:
	var watches:Array=[]
	for i:int in 24:
		var marker:=Marker.new()
		for surface:int in 128:
			var vertices:=PackedVector3Array();vertices.resize(1024)
			marker.payload.append([vertices])
		watches.append(weakref(marker))
		var packet:={"length":128*1024*12,"data":{"marker":marker}}
		packet.make_read_only();Prefab._decoded[str(i)]=packet;Prefab._decoded_bytes+=packet.length
	return watches
func run()->void:
	var watches:=fill();var borrowed:Dictionary=Prefab._decoded["0"]
	var digests:Dictionary={}
	for i:int in 24:digests[str(i)]=true
	var began:=Time.get_ticks_usec();Prefab.evict_geometry(digests);var elapsed:=Time.get_ticks_usec()-began
	check(Prefab._decoded.is_empty() and Prefab._decoded_bytes==0,"decoded cache identity/charge disappears synchronously")
	check(watches.all(func(watch):return watch.get_ref()!=null),"small outer array retains every large inner owner until bounded disposal")
	var service:Node=root.get_node("ResourceRetirement");service.set_process(false)
	check(not service._advance(service.pending[0],1) and service.pending[0].values.size()<24,"one microsecond slice advances without draining all packets")
	drain()
	check(watches[0].get_ref()!=null and watches.slice(1).all(func(watch):return watch.get_ref()==null),"borrowed immutable packet survives; unowned packets release")
	check(borrowed.is_read_only() and borrowed.data.marker.payload.size()==128,"retirement never mutates borrowed nested arrays")
	borrowed={};check(watches[0].get_ref()==null,"final independent borrower controls lifetime")
	print("SMALL_CACHE_RETIREMENT ",JSON.stringify({"eviction_us":elapsed,"profile":service.profile}))
	print("SMALL_CACHE_RETIREMENT failures=",failures);quit(1 if failures else 0)
