extends "res://tools/refine_axel_s1_layout.gd"
## Move the reviewed house inside its existing court, along with its entrance.
func before_placements(recipe:Dictionary)->void:
	await super.before_placements(recipe)
	if failed:return
	report.scope="S1 bridgehead and denser courtyard frontage; native entrance roads and reviewed independent stairs"
	for row:Dictionary in recipe.placements:
		if not row.has("stair_top"):continue
		var base:=Props.ground(editor._doc,City.vec(row.point))+.015
		var rise:float=float(row.stair_top)-base
		check(rise>=.32 and rise<=.8,"existing five-step asset fits actual entrance rise")
		row.point[1]=base;row.scale[1]=rise/.8
		report.stair_fit={"base":base,"top":row.stair_top,"rise":rise,"riser_height":rise/5.,"source_height_unchanged":.8,"placement_scale_y":row.scale[1]}
	report.foundation_samples=[]
	for x:float in [317.,324.,331.]:
		for z:float in [253.416667,257.666667,261.916667]:
			var y:=Props.ground(editor._doc,Vector3(x,0,z))
			report.foundation_samples.append([x,y,z])
			check(y>=5.05 and y<6.31,"house footprint witness remains between foundation bottom and finished floor")
func after_placements(recipe:Dictionary)->void:
	await super.after_placements(recipe)
	if failed:return
	var house:Dictionary=editor._doc._find("obj_1554")
	for row:Dictionary in editor._doc.map_meta.town_reference.house_layout.placements:
		if row.get("id","")!="s1_north_courtyard":continue
		row.position=house.position;row.rotation=house.rotation;row.yaw=house.rotation[1];row.entrance=recipe.entrance
		row.reference_stage="S1 courtyard frontage and gate aligned with bridgehead; full shot detail remains under review"
