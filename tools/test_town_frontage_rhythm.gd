extends SceneTree
const Rhythm=preload("res://tools/town_frontage_rhythm.gd")
var failures:=0
func check(value:bool,label_:String)->void:
	if not value:failures+=1;print("FAIL ",label_)
func _initialize()->void:
	for seed_ in range(20261000,20261032):
		for use_ in ["shop","house"]:
			var rows:=Rhythm.sequence(use_,seed_);var levels:Array=rows.map(func(r):return r.parameters.floors)
			check(rows.size()==(16 if use_=="shop" else 8),"complete solution")
			check(levels.count(3)==(3 if use_=="shop" else 1),"rare three storeys quota")
			check(Rhythm.valid_levels(levels),"no long equal runs or adjacent tall buildings")
			check(rows==Rhythm.sequence(use_,seed_),"seed reproducibility")
			var styles:Array=rows.map(func(r):return r.parameters.window_style)
			for style:String in preload("res://scripts/world3d/house_window_styles.gd").IDS:
				check(styles.count(style)==rows.size()/4,"balanced whole-house window families")
			for i in range(1,styles.size()):check(styles[i]!=styles[i-1],"adjacent houses vary window family")
			if use_=="shop":check(3 in levels.slice(0,8) and 3 in levels.slice(8,16),"tall shops on both street sides")
	for use_ in ["shop","house"]:
		var rows:=Rhythm.sequence(use_,20261005 if use_=="shop" else 20261006)
		print("FRONTAGE ",use_," ",JSON.stringify(rows.map(func(r):return {"id":r.id,"floors":r.parameters.floors,"setback":r.setback,"gap":r.gap})))
	print("TOWN_RHYTHM failures=",failures);quit(1 if failures else 0)
