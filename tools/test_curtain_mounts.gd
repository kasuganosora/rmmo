extends "res://tools/test_ground_batching.gd"
const G=preload("res://scripts/world3d/building_geometry.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
func run()->void:
	for elevation in ["north","south","west","east"]:
		var axis:="x" if elevation in ["north","south"] else "z"
		var inside:=1.0 if elevation in ["north","west"] else -1.0
		var plan:Dictionary={"parameters":{"curtains":true},"records":[]}
		G.curtains(plan,"floor0/"+elevation+"/window",axis,0,{"u":0,"width":1.3,"height":1.6,"bottom":1},0,{"trim":[.2,.1,.05]},0)
		var pole:Dictionary=plan.records.filter(func(r):return r.building.role=="curtain_rod")[0]
		var pole_basis:=Basis.from_euler(G.vec(pole.rotation)*PI/180)
		check(absf((pole_basis*Vector3.UP).dot(Vector3.RIGHT if axis=="x" else Vector3.BACK))>.99,elevation+" pole is horizontal along window")
		for cloth:Dictionary in plan.records.filter(func(r):return r.get("building_shape")=="draped_cloth"):
			var front:=Vector3(0,0,.03) if axis=="x" else Vector3(.03,0,0)
			front=Basis.from_euler(G.vec(cloth.rotation)*PI/180)*front
			check((front.z if axis=="x" else front.x)*inside>0,elevation+" pocket front faces room")
			check(is_equal_approx(float(cloth.position[1])+float(cloth.size[1])/2,float(pole.position[1])),elevation+" sleeve aligned with pole")
		for end in [-1,1]:
			var parts:Array=plan.records.filter(func(r):return r.building.part.contains("/support%d/"%end))
			check(parts.size()==4,elevation+" wall plate, arm and two cradle lips exist")
			var plate:Dictionary=parts.filter(func(r):return r.building.part.ends_with("/plate"))[0]
			var arm:Dictionary=parts.filter(func(r):return r.building.part.ends_with("/arm"))[0]
			var normal_axis:=2 if axis=="x" else 0
			var plate_center:float=plate.position[normal_axis]*inside
			var arm_center:float=arm.position[normal_axis]*inside
			check(plate_center-plate.size[normal_axis]/2<G.WALL/2,elevation+" plate seats into wall")
			check(arm_center-arm.size[normal_axis]/2<=plate_center+plate.size[normal_axis]/2 and arm_center+arm.size[normal_axis]/2>=pole.position[normal_axis]*inside+.0225,elevation+" arm connects wall plate to pole")
	for preset in Blueprint.medieval_presets():
		var plan:=Blueprint.generate(preset.parameters)
		check(plan.ok,preset.id+" valid recipe")
		check(not plan.records.any(func(r):return r.building.part.contains("/wall_hand") or r.building.part.contains("/return_wall")),preset.id+" no residual wall handrails or brackets")
		if not plan.stairs.is_empty():check(plan.records.any(func(r):return r.building.role=="rail"),preset.id+" open stair edges still guarded")
	print("CURTAIN_MOUNTS_FINISHED failures=",failed);quit(1 if failed else 0)
