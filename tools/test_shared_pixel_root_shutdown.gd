extends SceneTree
## Fresh process exercises first retirement during actual root exit propagation.
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
class Owner extends Node:
	var pool:RefCounted
	var ledger:RefCounted
	func _exit_tree()->void:
		pool.release("old");ledger.release("old")
		var clean:bool=ledger.reserved_bytes==0 and ledger.retiring_pixel_outputs==0
		print("ROOT_EXIT_RETIRE ","PASS" if clean else "FAIL"," reserved=",ledger.reserved_bytes," pending=",ledger.retiring_pixel_outputs)
		if not clean:get_tree().quit(1)
func _initialize()->void:
	var owner:=Owner.new();owner.ledger=Admission.new();owner.ledger.byte_limit=128*1024*1024
	owner.pool=Pool.new();owner.pool.admission=owner.ledger
	var row:Dictionary={"path":"fixture.png","width":1024,"height":1024,"source_bytes":1,"output_bytes":1024*1024*4,"extension":"dds"}
	var offer:Dictionary=owner.pool.offer({"rows":{"test":row}})
	if not owner.ledger.reserve_bundle("old",{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained):quit(2);return
	owner.pool.commit("old",offer)
	var image:=Image.create_empty(1024,1024,false,Image.FORMAT_RGBA8);image.fill(Color.RED)
	if not owner.pool.publish("old","test","digest",image):quit(3);return
	image=null;owner.ledger.park("old")
	root.add_child(owner)
	if root.get_node_or_null("ResourceRetirement")!=null:quit(4);return
	begin_shutdown.call_deferred()
func begin_shutdown()->void:
	# Simulate a service that has already been removed before root exit; its
	# absence must not cause an attempted add_child during propagation.
	var service:Node=root.get_node_or_null("ResourceRetirement")
	if service!=null:service.free()
	quit()
