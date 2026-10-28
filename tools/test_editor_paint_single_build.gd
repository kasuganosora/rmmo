extends "res://tools/test_editor_first_paint_preparation.gd"
## Real UI/HTTP operation must build the final painted material only once.
## Base fixture also proves first-use pixels, undo/redo and save/reopen.
func _check_paint_work(profile:Dictionary)->void:
	var material:Dictionary=profile.get("stages",{}).get("paint.material",{})
	check(int(material.get("calls",0))==1,"paint builds its material once without a discarded validation mesh")
