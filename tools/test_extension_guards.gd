extends SceneTree
func _initialize()->void:
	var route=preload("res://scripts/world3d/spline_route.gd")
	var failed:=0
	for pair:Array in [[route.sample([[0,0],[8,0],[8,8],[0,8]],2,true,0.).ok,"simple closed spline accepted"],[not route.sample([[0,0],[8,0],[0,8],[8,8]],2,true,0.).ok,"closing edge self intersection rejected"],[not route.sample([[0,0],[0,0]],2).ok,"degenerate spline rejected"]]:
		print("PASS " if pair[0] else "FAIL ",pair[1]);failed+=0 if pair[0] else 1
	print("EXTENSION_GUARDS_FINISHED failures=",failed);quit(failed)
