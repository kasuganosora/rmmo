extends RefCounted
## A main-owned input lease for existing CPU workers. This is resource lifetime,
## not a replacement for the caller's admission/accounting policy. Detaching a
## map transfers the SAME lease to the SceneTree drainer until a completed join.
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")

class Lease extends RefCounted:
	var owners:Array=[]
	var released:=false
	func release()->void:
		owners.clear();released=true

static func snapshot_surfaces(surfaces:Array)->Array:
	var result:Array=surfaces.duplicate()
	for at:int in result.size():
		if result[at] is Array:result[at]=result[at].duplicate()
	return result

static func watch(worker:Thread,tree:SceneTree,owners:Array)->Dictionary:
	if tree==null:return {}
	var lease:=Lease.new();lease.owners=owners
	var token:=Drainer.CancelToken.new()
	token.set_meta("admission_owner",lease);token.set_meta("admission_release",lease.release)
	var drainer:=Drainer.for_tree(tree);drainer.watch(worker,token)
	return {"worker":worker,"token":token,"lease":lease,"drainer":drainer}

static func complete(ticket:Dictionary)->void:
	# Caller has joined and transferred the result to a main-owned consumer, or
	# Thread.start failed. Never release inputs while a worker could use them.
	if ticket.is_empty():return
	if ticket.worker.is_alive():return
	if is_instance_valid(ticket.drainer):ticket.drainer.forget(ticket.worker)
	var token:RefCounted=ticket.token
	ticket.lease.release()
	token.remove_meta("admission_release");token.remove_meta("admission_owner")
	ticket.clear()

static func pending(retired:Array)->int:
	for at:int in range(retired.size()-1,-1,-1):
		var lease:Variant=retired[at].get_ref()
		if lease==null or lease.released:retired.remove_at(at)
	return retired.size()

static func abandon(ticket:Dictionary,retired:Array=[])->void:
	if ticket.is_empty():return
	retired.append(weakref(ticket.lease))
	# Already registered at dispatch, so this is safe during node _exit_tree;
	# it never creates/reparents a sibling while the old map is leaving.
	if is_instance_valid(ticket.drainer):ticket.drainer.abandon(ticket.worker)
	else:Drainer.drain_shutdown(ticket.worker,ticket.token)
	ticket.clear()
