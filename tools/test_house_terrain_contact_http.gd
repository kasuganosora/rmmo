extends "res://tools/test_house_foundation_support_http.gd"
## Reuse the real generator -> frozen library -> undo/save/reopen contract with
## a slope whose high cell corners sit outside the house, under upper fixtures.
func slope(id:String,x:float,base:float)->Dictionary:
	var heights:Array=[]
	for z in 10:
		for u in 9:heights.append(base+maxf((u-4)*2.-4.,0.)*.2)
	var holes:Array=[];holes.resize(8*9);holes.fill(false)
	return {"uuid":id,"kind":"box","surface_id":"ground","position":[x,0.,0.],"rotation":[0,0,0],"size":[16.,1.,18.],"color":[.3,.4,.2],"collision":"walk","terrain_mesh":{"version":1,"columns":8,"rows":9,"floor":-8.,"heights":heights,"holes":holes}}
func run()->void:
	var p:Dictionary=Blueprint.defaults().merged({"layout":"townhouse","template":"house","width":9.,"depth":11.,"floors":1,"floor_height":3.5,"base_height":.3,"foundation_depth":1.,"style":"plaster","roof_axis":"depth","roof_pitch":36.,"chimney":false,"front_canopy":false},true)
	var plan:=Blueprint.generate(p);check(plan.ok,"actual generated residence for cell-corner regression")
	var terrain:=slope("regression",0.,.12);var cap:float=Foot.foundation_support_height(p,0.,plan.records)
	var whole:=Foot.components(plan.records,Vector3.ZERO,Basis.IDENTITY);var former_failure:=false
	for cell:Dictionary in Foot.record_shapes(terrain):
		if not Foot.supporting_ground(terrain,cell.bounds.end.y,cap) and Foot.batches_overlap(whole,[cell]):former_failure=true
	check(former_failure,"fixture reproduces full-cell/full-house false rejection")
	check(Foot.terrain_conflict(terrain,Foot.terrain_components(plan.records),cap).is_empty(),"exact native components and clipped surface remain below the raised floor")
	var intrusion:=terrain.duplicate(true);intrusion.terrain_mesh.heights[4*9+4]=.8
	check(not Foot.terrain_conflict(intrusion,Foot.terrain_components(plan.records),cap).is_empty(),"interior terrain peak still intersects the real floor")
	# Rotate and translate both actual surfaces together; support uses world XZ.
	var basis:=Basis(Vector3.UP,deg_to_rad(37.));var origin:=Vector3(320.,8.,120.)
	var rotated:Array=plan.records.duplicate(true)
	for r:Dictionary in rotated:
		r.position=Blueprint.arr(origin+basis*Blueprint.vec(r.position));r.rotation=Blueprint.arr((basis*Basis.from_euler(Blueprint.vec(r.rotation)*PI/180)).get_euler()*180/PI);r.building.floor_y+=origin.y
	terrain.position=Blueprint.arr(origin);terrain.rotation=[0,37.,0]
	check(Foot.terrain_conflict(terrain,Foot.terrain_components(rotated),cap+8.).is_empty(),"translated rotated building and actual terrain preserve clear contact")
	intrusion.position=terrain.position;intrusion.rotation=terrain.rotation
	check(not Foot.terrain_conflict(intrusion,Foot.terrain_components(rotated),cap+8.).is_empty(),"translated rotated real floor intrusion remains protected")
	await super.run()
