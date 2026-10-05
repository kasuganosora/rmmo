extends SceneTree
const B=preload("res://scripts/world3d/building_blueprint.gd")
const W=preload("res://scripts/world3d/house_window_styles.gd")
var failures:=0
func intersects(records:Array,axis:String,fixed:float,u:float,y:float)->bool:
	var a:=B.wall_position(axis,fixed-1,u,y);var b:=B.wall_position(axis,fixed+1,u,y)
	for r:Dictionary in records:
		var mesh:=preload("res://scripts/world3d/roof_mesh.gd").mesh(r,null)
		var points:=mesh.get_faces();var pose:=Transform3D(Basis.from_euler(B.vec(r.rotation)*PI/180),B.vec(r.position))
		for i in range(0,points.size(),3):
			if Geometry3D.segment_intersects_triangle(a,b,pose*points[i],pose*points[i+1],pose*points[i+2])!=null:return true
	return false
func check(value:bool,label_:String)->void:
	if not value:failures+=1;print("FAIL ",label_)
func _initialize()->void:
	for style:String in W.IDS:
		var p:Dictionary=B.town_presets()[9].parameters.duplicate(true);p.window_style=style;p.shutters=style=="tall_shutter"
		var plan:=B.generate(p);check(plan.ok,"generate "+style)
		if not plan.ok:print(plan);continue
		check(plan.openings.filter(func(o):return o.type=="window").all(func(o):return o.get("window_style")==style),"same family on every floor and dormer")
		for r:Dictionary in plan.records:
			r.building.id="test";check(B.valid_record(r),"valid mesh "+str(r.building.part))
		check(plan.records.size()<=B.MAX_PARTS,"bounded authoring parts")
		if style!="round_arch":
			for head:Dictionary in plan.records.filter(func(r):return r.building.part.ends_with("/stone_head")):
				var prefix:String=head.building.part.trim_suffix("stone_head")
				var jambs:Array=plan.records.filter(func(r):return r.building.part.begins_with(prefix+"stone_jamb"))
				for jamb:Dictionary in jambs:
					check(float(head.position[1])-float(head.size[1])/2<=float(jamb.position[1])+float(jamb.size[1])/2+.001,"stone lintel meets window jamb")
		if style=="round_arch":
			var caps:Array=plan.records.filter(func(r):return r.building.part.contains("arch_wall"))
			check(not caps.is_empty(),"solid arch corner infill exists")
			var o:Dictionary=plan.openings.filter(func(item):return item.type=="window")[0]
			var own:Array=caps.filter(func(r):return r.building.part.begins_with(o.wall+"/"+o.id+"/arch_wall"))
			var top:float=o.floor_y+o.bottom+o.height
			check(intersects(own,o.axis,o.fixed,o.u+o.width*.44,top-.06),"square corner has real wall triangles")
			check(not intersects(own,o.axis,o.fixed,o.u,top-.12),"arch crown remains a genuine aperture")
		print("WINDOW_FAMILY ",style," raw_parts=",plan.records.size()," failures=",failures)
	for seed_ in 12:
		var p:Dictionary=B.town_presets()[0].parameters.duplicate(true);p.window_style="random";p.seed=seed_
		var a:=B.generate(p);var b:=B.generate(p)
		check(a.ok and a.parameters.window_style in W.IDS and a.parameters==b.parameters,"random is resolved once and repeatable")
	print("WINDOW_STYLES failures=",failures);quit(1 if failures else 0)
