extends SceneTree
func _initialize()->void:
	var plan=preload("res://scripts/world3d/fortification_plan.gd").new()
	var args:={"id":"ellipse","shape":"ellipse","center_x":200.,"center_z":0.,"radius_x":50.,"radius_z":30.,"style":"medieval_stone","tower_layout":"manual","tower_count":4,"height":7.5,"thickness":3.5,"gates":[{"id":"gate","angle":0.,"width":6.,"height":5.,"open":1.}]}
	var result:Dictionary=plan.build(args);var failed:=0 if result.ok else 1
	for r:Dictionary in plan.records:
		if not preload("res://scripts/world3d/channel_surface.gd").valid(r):failed+=1
	print("TRANSLATED_ELLIPSE_FINISHED failures=",failed);quit(failed)
