extends SceneTree
## Compare indexed candidates against the previous exhaustive narrow phase.
const Snapshot=preload("res://scripts/world_editor/building_clearance_snapshot.gd")
const Footprint=preload("res://scripts/world_editor/building_footprint.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Regions=preload("res://scripts/world3d/terrain_regions.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
const Rock=preload("res://scripts/world3d/rock_bank_mesh.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
var failures:=0
var checks:=0
var comparisons:=0

func _init()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
	else:print("PASS ",label)

func xyz(v:Vector3)->Array:return [v.x,v.y,v.z]

func box(id:String,position:Vector3,size:Vector3,rotation:=Vector3.ZERO)->Dictionary:
	return {"uuid":id,"kind":"box","position":xyz(position),"rotation":xyz(rotation),"size":xyz(size),"surface_id":"block","collision":"block"}

func exhaustive(records:Array,excluded:Dictionary)->Array:
	var result:Array=[]
	for record:Dictionary in records:
		if excluded.has(record.uuid):continue
		for shape:Dictionary in Footprint.record_shapes(record):result.append({"id":record.uuid,"record":record,"shape":shape})
	return result

func hits(obstacles:Array,query:Dictionary)->Array:
	var result:Array=[]
	for row:Dictionary in obstacles:
		if Footprint.batches_overlap([query],[row.shape]):result.append(row.id)
	return result

func equivalent(snapshot:RefCounted,old:Array,position:Vector3,size:Vector3,rotation:=Vector3.ZERO)->bool:
	var shape:Dictionary=Footprint.record_shape(box("query",position,size,rotation))
	var expected:=hits(old,shape);var actual:=hits(snapshot.obstacles(shape.bounds),shape)
	comparisons+=1
	if actual!=expected:
		push_error("clearance difference at %s size=%s old=%s new=%s"%[position,size,expected,actual])
		return false
	return true

func bounds_of(rows:Array)->AABB:
	var result:AABB=rows[0].bounds
	for shape:Dictionary in rows.slice(1):result=result.merge(shape.bounds)
	return result

func run()->void:
	var rows:Array=[]
	# Deliberately reverse lexical UUID order for overlapping objects.
	rows.append(box("z_first",Vector3(-31.9,2,0),Vector3(6,4,8),Vector3(10,47,4)))
	rows.append(box("a_second",Vector3(-31.9,2,0),Vector3(4,4,5),Vector3(0,-20,0)))
	rows.append(box("upstairs",Vector3(-31.9,18,0),Vector3(8,2,8),Vector3(0,35,0)))
	var ground:=box("terrain_furrows",Vector3(32,0,0),Vector3(8,2,8),Vector3(7,28,3))
	ground.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-1.,"heights":[0.,.1,.2,.1,.2,.3,.2,.3,.4],"holes":[false,true,false,false]}
	ground.terrain_regions={"materials":[{}],"regions":[{"id":"raised_field","polygon":[[-4.,-4.],[4.,-4.],[4.,4.],[-4.,4.]],"feather":1.,"opacity":1.,"layer":0,"furrows":{"spacing":1.2,"height":.3,"angle":0.,"phase":0.,"margin":.5}}]}
	check(Terrain.valid(ground) and Regions.valid(ground),"terrain holes/heights/furrows fixture obeys current schemas");rows.append(ground)
	var road:=box("road_clearance",Vector3(96,4,0),Vector3(8,.2,8),Vector3(4,35,0))
	road.road_mesh={"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[0.,0.,0.],"grade":[.1,-.04]};road.road_clearance=8.
	check(Road.valid(road),"graded road fixture reserves vertical clearance beyond render mesh");rows.append(road)
	var channel:=box("channel_clearance",Vector3(160,0,0),Vector3(10,.4,8),Vector3(0,17,0))
	channel.channel_mesh={"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[0.,0.,0.]};channel.channel_clearance=5.
	check(Channel.valid(channel),"channel fixture uses independent positive clearance");rows.append(channel)
	var rock:=box("scaled_rock",Vector3(224,1,0),Vector3(2,1.5,.7),Vector3(9,63,4))
	rock.rock_bank=Rock.defaults().merged({"points":[[0.,0.,0.],[4.,.2,0.],[8.,.4,1.]],"inner_heights":[.3,.6,.8],"inner_widths":[3.,4.,3.]},true)
	rock.rock_bank_materials={"rock":{},"top":{}}
	check(Rock.valid(rock),"scaled/tilted variable-width rock bank fixture obeys current schema");rows.append(rock)
	var gate:=box("fort_gate",Vector3(288,2,0),Vector3(5,4,.3),Vector3(0,23,0))
	gate.fixture={"id":"gate","kind":"door","pivot":[-2.5,0.,0.],"angle":-130.,"open":.15}
	gate.fortification={"id":"wall","part":"gate_left","role":"door"}
	check(Fixtures.valid(gate) and preload("res://scripts/world3d/fortification_data.gd").valid_record(gate),"fort gate fixture keeps complete negative-angle opening sweep");rows.append(gate)
	var huge:=box("large_global",Vector3(0,-12,0),Vector3(1200,1,1200))
	rows.append(huge)
	var excluded:=box("excluded",Vector3(96,4,0),Vector3(5,30,5));rows.append(excluded)
	var far:=box("far_rotated",Vector3(8000,2,8000),Vector3(4,4,8),Vector3(0,49,0));rows.append(far)
	var far_terrain:=ground.duplicate(true);far_terrain.uuid="far_terrain";far_terrain.position=[9000.,0.,9000.];rows.append(far_terrain)
	var snapshot:=Snapshot.new();snapshot.capture(rows,{"excluded":true})
	var old:=exhaustive(rows,{"excluded":true})
	check(snapshot.shape_builds==4,"capture constructs only road/channel/rock/gate exact envelopes once")
	check(snapshot.global_entries.size()==1,"very large entry uses global fallback instead of unbounded spatial cells")
	var probe_shape:=Footprint.record_shape(box("q",Vector3(-31.9,2,0),Vector3(.5,.5,.5)))
	var ordered:=hits(snapshot.obstacles(probe_shape.bounds),probe_shape)
	check(ordered==["z_first","a_second"],"first conflict order follows document order, not UUID or cell order")
	var initial_builds:int=snapshot.shape_builds
	for i in 16:snapshot.obstacles(probe_shape.bounds)
	check(snapshot.shape_builds==initial_builds,"repeated duplicate candidates reuse nearby exact shapes")
	var all_equal:=true;var rng:=RandomNumberGenerator.new();rng.seed=20261011
	for record:Dictionary in rows.slice(0,9):
		var bounds:=bounds_of(Footprint.record_shapes(record))
		# All six faces: touch, just outside and slightly inside old SAT limits.
		for axis in 3:
			for side in [-1.,1.]:
				for epsilon in [-.06,-.01,0.,.01,.06]:
					var center:=bounds.get_center();center[axis]=(bounds.position[axis] if side<0 else bounds.end[axis])+side*epsilon
					all_equal=equivalent(snapshot,old,center,Vector3(.12,.12,.12)) and all_equal
		for i in 40:
			var point:=bounds.position+Vector3(rng.randf(),rng.randf(),rng.randf())*bounds.size
			all_equal=equivalent(snapshot,old,point,Vector3(.2,.5,.2),Vector3(0,rng.randf_range(-180,180),0)) and all_equal
	check(all_equal,"630 boundary/interior queries preserve exact overlaps, duplicate shape order and first conflict")
	# Explicitly assert cases a plain render AABB would incorrectly reject.
	var road_point:=Terrain.transform(road)*Vector3(0,6,0)
	var channel_point:=Terrain.transform(channel)*Vector3(0,4,0)
	for pair in [[road_point,"road_clearance"],[channel_point,"channel_clearance"]]:
		var q:=Footprint.record_shape(box("q",pair[0],Vector3(.2,.2,.2)))
		check(not Geometry.bounds([road if pair[1]=="road_clearance" else channel]).intersects(q.bounds) and hits(snapshot.obstacles(q.bounds),q).has(pair[1]),"above-render clearance remains blocked: "+pair[1])
	var furrow_point:=Terrain.transform(ground)*Vector3(-2,.7,2)
	var furrow_query:=Footprint.record_shape(box("q",furrow_point,Vector3(.05,.05,.05)))
	check(hits(snapshot.obstacles(furrow_query.bounds),furrow_query).has("terrain_furrows"),"raised furrow envelope is retained above ordinary terrain height")
	var arc_point:=Fixtures.pose(Terrain.transform(gate),gate.fixture,.75)*Vector3(1.,0.,0.)
	var arc_query:=Footprint.record_shape(box("q",arc_point,Vector3(.1,.1,.1)))
	check(not Geometry.bounds([gate]).intersects(arc_query.bounds) and hits(snapshot.obstacles(arc_query.bounds),arc_query).has("fort_gate"),"gate sweep stays blocked outside its current render pose")
	check(snapshot.entries.filter(func(entry):return entry.record.uuid in ["far_rotated","far_terrain"]).all(func(entry):return not entry.has("shapes")),"far ordinary objects and terrain never construct exact footprints")
	var before_repeat:int=snapshot.shape_builds
	for offset in [Vector3(0,2,0),Vector3(0,18,0),Vector3(32,0,0),Vector3(96,10,0),Vector3(160,4,0),Vector3(224,0,0),Vector3(288,2,0)]:
		all_equal=equivalent(snapshot,old,offset,Vector3(16,4,16)) and all_equal
	var after_first_pass:int=snapshot.shape_builds
	for offset in [Vector3(0,2,0),Vector3(0,18,0),Vector3(32,0,0),Vector3(96,10,0),Vector3(160,4,0),Vector3(224,0,0),Vector3(288,2,0)]:
		all_equal=equivalent(snapshot,old,offset,Vector3(16,4,16)) and all_equal
	check(all_equal and snapshot.shape_builds==after_first_pass,"multi-location duplicate retries reuse snapshot without rebuilding footprints")
	check(equivalent(snapshot,old,Vector3(0,2,0),Vector3(1300,40,1300)),"large query fallback matches exhaustive first-conflict order")
	print("CLEARANCE_SNAPSHOT_METRICS ",JSON.stringify({"records":rows.size(),"comparisons":comparisons,"exact_builds":snapshot.shape_builds,"before_retries":before_repeat,"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
