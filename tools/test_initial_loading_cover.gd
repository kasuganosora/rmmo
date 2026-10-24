extends SceneTree
## Contract: an opaque initial-load cover plus disabled 3D authorizes the
## bounded covered-loading publication budget, and hiding/clearing it revokes it.

const Cover=preload("res://scripts/world3d/initial_loading_cover.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")

class InputProbe extends Node:
	var unhandled:=0
	func _unhandled_input(_event:InputEvent)->void:unhandled+=1

var failures:=0
var checks:=0
var failure_returns:=0
var outer_returns:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,label:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map)
	var input_probe:=InputProbe.new();root.add_child(input_probe)
	var cover:=Cover.new();root.add_child(cover)
	await process_frame
	await process_frame
	check(cover.is_opaque_drawn(),"initial cover is opaque and drawn")
	root.get_viewport().disable_3d=true
	var queue:=Deferred.new();queue._map=map;queue._host=host;map.add_child(queue)
	check(queue.begin_loading_cover(host,cover),"covered initial load is accepted")
	check(queue._covered_loading_ready(),"drawn cover and disabled 3D authorize loading")
	check(queue._main_thread_budget_usec()==queue.covered_loading_budget_usec,"covered loading receives the covered budget")
	cover.hide()
	check(not queue._covered_loading_ready(),"hidden cover revokes loading authority")
	cover.show()
	check(queue._covered_loading_ready(),"shown cover restores authority")
	queue.end_loading_cover()
	check(not queue._covered_loading_ready(),"ending the cover revokes loading authority")
	root.get_viewport().disable_3d=false
	queue.free();host.free()
	var outer:=CanvasLayer.new();outer.layer=100;root.add_child(outer)
	var back:=Button.new();back.text="outer error return";back.position=Vector2(24,24);back.size=Vector2(240,44);outer.add_child(back)
	back.pressed.connect(func()->void:outer_returns+=1)
	cover.show_failure("test timeout",func()->void:failure_returns+=1)
	await process_frame
	await process_frame
	check(cover.is_opaque_drawn() and cover._label.text.contains("test timeout"),"failure displays its cause while retaining the opaque cover")
	click_button(cover._return_button)
	check(failure_returns==1,"real viewport mouse input reaches the direct-entry failure return button")
	check(outer_returns==0,"the failed inner cover prevents clicking the outer UI behind it")
	var key:=InputEventKey.new();key.keycode=KEY_W;key.pressed=true;root.push_input(key,true)
	check(input_probe.unhandled==0,"failure UI still consumes unhandled gameplay input")
	cover.retire()
	check(not cover.is_processing_input() and not cover.is_processing_unhandled_input(),"retiring the inner cover immediately disables its input handlers")
	click_button(back)
	check(outer_returns==1,"the outer return button receives real viewport input before the retired cover is freed")
	outer.free();input_probe.free()
	print("INITIAL_LOADING_COVER ",checks," checks / ",failures," failures; input routed through Viewport.push_input")
	quit(1 if failures else 0)

func click_button(button:Button)->void:
	var position:=button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=position;motion.global_position=position;root.push_input(motion,true)
	for pressed:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=position;event.global_position=position
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,true)
