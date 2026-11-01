extends SceneTree
const Timeline=preload("res://scripts/util/debug_timeline.gd")
var destination:=""
var events:={"released":0,"resumed":0,"cancelled_resumed":0}
var continuation_label:=0

class SlowPayload extends RefCounted:
	var counts:Dictionary
	func _init(value:Dictionary)->void:counts=value
	func _notification(what:int)->void:
		if what!=NOTIFICATION_PREDELETE:return
		var start:=Time.get_ticks_usec()
		while Time.get_ticks_usec()-start<3000:pass
		counts.released+=1

class Pending extends Node:
	signal gate
	func suspend(counts:Dictionary)->void:
		var payload:=SlowPayload.new(counts)
		await gate
		if payload!=null:counts.cancelled_resumed+=1

func _initialize()->void:run.call_deferred()

func leaf()->bool:
	var payload:=SlowPayload.new(events)
	await process_frame
	return payload!=null

func branch()->bool:
	var value:bool=await leaf()
	var span:=Timeline.begin(continuation_label)
	var start:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-start<4000:pass
	events.resumed+=1
	Timeline.end(span)
	return value

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):destination=arg.trim_prefix("--output-dir=")
	if destination.is_empty():quit(2);return
	continuation_label=Timeline.label("test49.continuation")
	var stable:=Timeline.label("script.state_signal_callback")==117 and Timeline.label("script.resume_stack_release")==125 and Timeline.label("lifetime.node_destructor_body")==116
	var started:=Timeline.start(262144,true)==OK
	var success:bool=await branch()
	var pending:=Pending.new();root.add_child(pending)
	pending.suspend(events)
	pending.free()
	await process_frame
	await process_frame
	var trace:=Timeline.stop()
	var exported:=Timeline.export_capture(destination.path_join("capture.rmtrace"))
	var result:={"stable_labels":stable,"started":started,"events":events,"trace":trace,"export_error":exported,"branch_success":success}
	FileAccess.open(destination.path_join("smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("SCRIPT49_SMOKE ",JSON.stringify(result))
	quit(0 if stable and started and success and events.released==2 and events.resumed==1 and events.cancelled_resumed==0 and trace.dropped==0 and exported==OK else 1)
