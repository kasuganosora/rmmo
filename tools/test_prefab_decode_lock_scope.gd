extends "res://tools/test_house_geometry_identity_reuse.gd"
## A destructor is observable work: cache eviction must not execute it while
## preventing unrelated worker lookups. No large allocation is needed to test
## the byte-budget boundary.
class ReleaseProbe extends RefCounted:
	static var released_outside_lock:=false
	static func observe_lock()->bool:
		var mutex:Mutex=preload("res://scripts/world3d/house_prefab.gd")._decode_mutex
		var available:=mutex.try_lock()
		if available:mutex.unlock()
		return available
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			var worker:=Thread.new()
			if worker.start(observe_lock)==OK:released_outside_lock=worker.wait_to_finish()

func run()->void:
	var policy=preload("res://scripts/world3d/runtime_package_policy.gd")
	policy.verify_packages=false
	var value:=encode(fixture())
	House._decoded.clear();House._decoded_bytes=House.DECODE_BUDGET
	House._decoded["eviction_probe"]={"length":1,"retained_bytes":House.DECODE_BUDGET,"probe":ReleaseProbe.new()}
	var packet:=House._decode_packet(value)
	check(not packet.is_empty() and not House._decoded.has("eviction_probe"),"budget eviction retains the requested valid packet")
	check(ReleaseProbe.released_outside_lock,"evicted packet destructors run after releasing the shared cache mutex")
	check(House._decoded_bytes==House.retained_decode_bytes(packet),"eviction keeps exact retained-byte accounting")
	# Trusted package identity is the authored SHA and length. Different String
	# owners must not require rescanning the entire encoded payload on every hit.
	var equivalent:=value.duplicate();equivalent.data=value.data.to_utf8_buffer().get_string_from_utf8()
	check(is_same(House._decode_packet(equivalent),packet),"independently restored shared package identity reuses one canonical packet")
	var changed:=fixture();changed.materials[0]["values"].roughness=.6
	var declared:=value.duplicate();declared.data=encode(changed).data
	check(is_same(House._decode_packet(declared),packet),"trusted cache hit does not reauthenticate encoded package bytes")
	policy.verify_packages=true
	var verified:=House._decode_packet(value)
	check(not verified.is_empty() and verified.verified,"diagnostic access replaces a trusted packet with verified data")
	check(House._decode_packet(declared).is_empty(),"explicit diagnostic access still rejects mismatched encoded bytes")
	check(is_same(House._decode_packet(value),verified),"diagnostic failure leaves the valid canonical packet intact")
	House.evict_geometry({value.sha256:true})
	check(House._decoding.is_empty() and House._decoded_bytes==0,"flights and retained bytes are released")
	print("PREFAB_DECODE_LOCK_SCOPE checks=",checks," failures=",failures);quit(1 if failures else 0)
