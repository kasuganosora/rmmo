extends "res://tools/test_world3d_mcp.gd"
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")

func terrain(id:String,center:Vector2,span:Vector2,cells:Vector2i,yaw:float=0.)->Dictionary:
	var heights:Array=[];heights.resize((cells.x+1)*(cells.y+1));heights.fill(0.)
	var holes:Array=[];holes.resize(cells.x*cells.y);holes.fill(false)
	var point:=Basis(Vector3.UP,deg_to_rad(yaw))*Vector3(center.x,0,center.y)
	return {"uuid":id,"kind":"box","surface_id":"ground","collision":"walk","color":[.3,.4,.2],"position":[point.x,0,point.z],"rotation":[0,yaw,0],"size":[span.x,1.,span.y],"terrain_mesh":{"version":1,"columns":cells.x,"rows":cells.y,"floor":-16.,"heights":heights,"holes":holes}}

func records_after(original:Array,result:Dictionary)->Array:
	return original.map(func(r):
		for entry:Dictionary in result.entries:
			if entry.record.uuid==r.uuid:return entry.record
		return r)

func aligned_edges()->void:
	for yaw:float in [0.,31.]:
		var sources:Array=[terrain("a",Vector2(-6,-6),Vector2(12,12),Vector2i(4,4),yaw),terrain("b",Vector2(6,-6),Vector2(12,12),Vector2i(6,6),yaw),terrain("c",Vector2(-6,6),Vector2(12,12),Vector2i(6,6),yaw),terrain("d",Vector2(6,6),Vector2(12,12),Vector2i(4,4),yaw)]
		var request:={"id":"a","mode":"raise","points":[[0.,0.]],"radius":5.,"strength":.3}
		var initial:Array=sources.duplicate(true)
		var result:=Batch.prepare(sources,sources[0],request)
		check(result.ok,"four mixed-resolution tiles at %.0f degrees accept corner stroke"%yaw)
		check(sources==initial,"batch preparation never mutates original terrain")
		if not result.ok:print(result);continue
		var next:=records_after(sources,result)
		var continuous:=true
		for i in sources.size():
			for j in range(i+1,sources.size()):
				if Batch.adjacent(sources[i],sources[j]):continuous=continuous and Batch.validate_edge_continuity(sources[i],sources[j],next[i],next[j]).ok
		check(continuous,"all four edges stay continuous including shared corner")
		var reverse:Array=[sources[0],sources[3],sources[2],sources[1]]
		var reversed:=Batch.prepare(reverse,sources[0],request)
		check(reversed.ok and equivalent(records_after(sources,reversed),next),"four-way seam independent of document order")

func partial_edge()->void:
	# The right tile ends midway through a coarse segment of the left tile.
	# Old code only joined common knots and silently left a crack below them.
	var a:=terrain("left",Vector2(-6,0),Vector2(12,12),Vector2i(4,4))
	var b:=terrain("right_top",Vector2(6,-2.5),Vector2(12,7),Vector2i(6,7))
	var c:=terrain("right_bottom",Vector2(6,3.5),Vector2(12,5),Vector2i(6,5))
	var sources:Array=[a,b,c];var initial:Array=sources.duplicate(true)
	var result:=Batch.prepare(sources,a,{"id":"left","mode":"raise","points":[[0.,1.]],"radius":1.5,"strength":.3})
	check(not result.ok and str(result.error).contains("公共格点"),"unrepresentable T junction rejects whole stroke instead of opening crack")
	check(sources==initial,"rejected T junction preserves every source sample")
	# A distant brush on this same layout must still be allowed.
	result=Batch.prepare(sources,a,{"id":"left","mode":"raise","points":[[-6.,0.]],"radius":2.,"strength":.3})
	check(result.ok,"partial edge does not block unrelated interior sculpt")
	var stepped:=terrain("rounding_neighbor",Vector2(6,0),Vector2(12,12),Vector2i(4,4));stepped.position[1]=.001
	result=Batch.prepare([a,stepped],a,{"id":"left","mode":"raise","points":[[-6.,0.]],"radius":2.,"strength":.3})
	check(result.ok,"unrelated sculpt preserves pre-existing millimetre seam offset")

func neighboring_hole()->void:
	var a:=terrain("seed",Vector2.ZERO,Vector2(12,12),Vector2i(4,4))
	var b:=terrain("neighbor",Vector2(12,0),Vector2(12,12),Vector2i(6,6))
	b.terrain_mesh.holes[21]=true
	var brush=preload("res://scripts/world_editor/terrain_brush.gd")
	var origin:=Vector3(13,10,1)
	var at:Vector3=brush.plane_pick(Batch.connected([a,b],a),origin,Vector3.DOWN,100.)
	check(at.is_equal_approx(Vector3(13,0,1)),"cross-tile brush can target a hole on its neighboring tile")
	var filled:=Batch.prepare([a,b],a,{"id":"seed","mode":"fill","points":[[at.x,at.z]],"radius":1.5})
	check(filled.ok and not records_after([a,b],filled)[1].terrain_mesh.holes[21],"neighbor hole fills while original seed stays selected")
	check(not brush.plane_pick([a],origin,Vector3.DOWN,100.).is_finite(),"disabled cross-tile option does not pick neighboring holes")
	check(not brush.plane_pick([a,b],origin,Vector3.DOWN,5.).is_finite(),"solid hit in front still occludes neighboring hole picking")

func water_crown_support()->void:
	var settings:=preload("res://scripts/world3d/fortification_data.gd").defaults().merged({"id":"review_water","shape":"ellipse","closed":true,"radius_x":40.,"radius_z":40.,"height":8.,"thickness":3.5,"corner_towers":false,"follow_terrain":true,"gates":[{"id":"water","angle":0.,"kind":"water","width":24.,"height":5.,"open":.4,"grille":true}]},true)
	var plan:=preload("res://scripts/world3d/fortification_plan.gd").new().build(settings)
	check(plan.ok,"water crown review ring builds")
	if not plan.ok:return
	var ground:=terrain("bed",Vector2.ZERO,Vector2(100,100),Vector2i(50,50))
	ground.terrain_mesh.heights.fill(-.1)
	var fitted:=preload("res://scripts/world3d/fortification_terrain.gd").fit(plan.records,[ground],0.,1.)
	check(fitted.ok,"water crown fit on lower bed succeeds")
	if not fitted.ok:print(fitted);return
	var footprints:Array=[]
	for record:Dictionary in plan.records:
		if str(record.fortification.part).begins_with("water_crown_"):
			footprints.append_array(preload("res://scripts/world_editor/building_footprint.gd").record_shapes(record).map(func(shape):return shape.polygon))
	var checked:=0;var stable:=true
	for i in plan.records.size():
		var source:Dictionary=plan.records[i]
		if source.fortification.role not in ["parapet","battlement"]:continue
		var p:=Vector2(source.position[0],source.position[2])
		if not footprints.any(func(poly):return Geometry2D.is_point_in_polygon(p,poly)):continue
		checked+=1
		stable=stable and fitted.records[i].position==source.position and not fitted.records[i].has("terrain_grade")
	check(checked>0 and stable,"battlements resting on curved water crown do not follow river bed")

func run()->void:
	aligned_edges();partial_edge();neighboring_hole();water_crown_support()
	print("TERRAIN_FOLLOW_REVIEW_FINISHED failures=",failed);quit(failed)
