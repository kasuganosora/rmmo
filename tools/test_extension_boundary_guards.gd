extends SceneTree
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
const Cut=preload("res://scripts/world_editor/bridge_road_cut.gd")
var failed:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failed+=1
func terrain(id:String,x:float,count:int)->Dictionary:
	var heights:Array=[];heights.resize((count+1)*(count+1));heights.fill(0.)
	var holes:Array=[];holes.resize(count*count);holes.fill(false)
	return {"uuid":id,"kind":"box","position":[x,0,0],"rotation":[0,0,0],"size":[12,1,12],"terrain_mesh":{"version":1,"columns":count,"rows":count,"floor":-16.,"heights":heights,"holes":holes}}
func _initialize()->void:
	var a:=terrain("coarse",0,4);var b:=terrain("fine",12,6)
	var request:={"id":"coarse","mode":"raise","points":[[6,1]],"radius":4.,"strength":.3}
	var result:=Batch.prepare([a,b],a,request);check(result.ok,"nonmultiple 3m / 2m grid brush succeeds")
	if result.ok:
		var ra:Dictionary=result.entries.filter(func(e):return e.record.uuid=="coarse")[0].record
		var rb:Dictionary=result.entries.filter(func(e):return e.record.uuid=="fine")[0].record
		var continuous:=true
		for i in 49:
			var z:float=-6.+i*.25
			continuous=continuous and absf(T.sample(ra,Vector3(6,0,z))-T.sample(rb,Vector3(-6,0,z)))<.00001
		check(continuous,"nonmultiple grid edge continuous between all sample knots")
		var reverse:=Batch.prepare([b,a],a,request)
		check(reverse.ok and reverse.record==result.record,"mixed grid independent of document order")
	var road:={"uuid":"road","kind":"box","position":[0,0,0],"rotation":[0,0,0],"size":[32,.2,32],"road_mesh":{"polygons":[[[-.4,-.2],[.4,-.2],[.4,.2],[-.4,.2]]],"uv_origin":[0,0,0],"elevations":[[10.,10.,10.,10.]]}}
	var mask:Array=[Vector2(-5,-5),Vector2(5,-5),Vector2(5,5),Vector2(-5,5)]
	var clipped:=Cut.cut(road,mask,.1,[Vector3(-10,.1,0),Vector3(10,.1,0)])
	check(clipped.ok and not clipped.changed,"bridge conversion preserves elevated crossing road")
	road.road_mesh.elevations=[[.1,.1,.1,.1]]
	clipped=Cut.cut(road,mask,.1,[Vector3(-10,.1,0),Vector3(10,.1,0)])
	check(clipped.ok and clipped.changed and not clipped.removed,"matching elevation road clips and interpolates heights")
	var nodes:={"a":{"position":[0,0,0]},"b":{"position":[30,1,0]}}
	var edge:={"from":"a","to":"b","width_start":6.,"width_end":6.}
	var connected:Array=[edge,{"from":"c","to":"a","width_start":8.,"width_end":12.},{"from":"b","to":"d","width_start":10.,"width_end":8.}]
	var line:=preload("res://scripts/world3d/road_bridges.gd").deck_line(edge,nodes,connected)
	check(line[0].is_equal_approx(Vector3(6,0,0)) and line[1].is_equal_approx(Vector3(25,1,0)),"sloped bridge uses connected junction widths")
	print("BOUNDARY_GUARDS_FINISHED failures=",failed);quit(failed)
