extends RefCounted
## Main-owned tail of an initial loading operation. Workers may finish every
## model while their pool stays alive for sharing and safe rejection cleanup.
var pool:RefCounted
var consumers:Array[String]=[]
var retained_reservations:Array[String]=[]
var retained_packets:Array[Dictionary]=[]
var completed_owners:Dictionary={}
var completed_success:=false
var published:=false
var released:=false

func publish_ready()->int:
	assert(Thread.is_main_thread())
	if released or published or not completed_success:return 0
	published=true
	var count_:int=preload("res://scripts/world3d/native_texture_sharing.gd").publish(completed_owners)
	completed_owners.clear()
	return count_

func release_now()->void:
	if released:return
	assert(Thread.is_main_thread())
	released=true
	completed_owners.clear()
	# Load lazily: the drainer recognizes this ownership edge and calls us.
	var drainer:Script=load("res://scripts/world3d/asset_worker_drainer.gd")
	for packet:Dictionary in retained_packets:drainer.dispose_result(packet)
	retained_packets.clear()
	if pool!=null:
		for consumer:String in consumers:
			pool.release(consumer)
			pool.admission.release(consumer) # A cancelled parked continuation still owns scratch.
		for reservation:String in retained_reservations:pool.admission.release(reservation)
	retained_reservations.clear()
	consumers.clear();pool=null
