extends SceneTree
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Old=preload("res://review_artifacts/terrain_incremental_20261017/terrain_surface_baseline.gd")
const B=preload("res://scripts/world3d/terrain_stroke_batch.gd")
const OB=preload("res://review_artifacts/terrain_incremental_20261017/terrain_stroke_batch_baseline.gd")
const N=preload("res://scripts/world3d/terrain_neighbors.gd")
const ON=preload("res://review_artifacts/terrain_incremental_20261017/terrain_neighbors_baseline.gd")
const Index=preload("res://scripts/world3d/terrain_spatial_index.gd")
var failures:=0
var comparisons:=0
func check(ok:bool,label:String)->void:
	comparisons+=1
	if not ok:failures+=1;push_error(label)
static func fixture(n:int=64)->Dictionary:
	var r:=preload("res://tools/test_terrain_surface.gd").fixture()
	r.size=[64.,1.,64.];r.terrain_mesh.columns=n;r.terrain_mesh.rows=n
	r.terrain_mesh.heights.resize((n+1)*(n+1));r.terrain_mesh.heights.fill(0.)
	r.terrain_mesh.holes.resize(n*n);r.terrain_mesh.holes.fill(false)
	return r
func contexts(a:Dictionary,b:Dictionary)->bool:
	if a.keys()!=b.keys():return false
	for id:String in a:
		for key in ["signature","normals","padding","neighbors"]:
			if a[id][key]!=b[id][key]:return false
		if a[id].image.get_data()!=b[id].image.get_data():return false
	return true
func _initialize()->void:
	var rng:=RandomNumberGenerator.new();rng.seed=171017
	for i in 120:
		var r:=fixture([4,16,64][i%3]);r.position=[rng.randf_range(-90,90),rng.randf_range(-3,3),rng.randf_range(-90,90)]
		r.rotation[1]=rng.randf_range(-180,180);r.size=[rng.randf_range(.01,200),rng.randf_range(.1,5),rng.randf_range(.01,200)]
		if i%10==0:r.position[0]=99999.
		if i%11==0:r.rotation[0]=.00001
		for j in r.terrain_mesh.heights.size():r.terrain_mesh.heights[j]=rng.randf_range(0.,1.)
		var p:=T.transform(r)*Vector3(rng.randf_range(-.6,.6)*r.size[0],0,rng.randf_range(-.6,.6)*r.size[2])
		for mode in T.MODES:
			var args:={"id":r.uuid,"mode":mode,"points":[[clampf(p.x,-100000,100000),clampf(p.z,-100000,100000)]],"radius":rng.randf_range(.25,12),"strength":.2,"target_height":2.,"iterations":1}
			check(T.stroke(r,args)==Old.stroke(r,args),"stroke differential %s %s"%[i,mode])
		var rectangle:={"id":r.uuid,"mode":"flatten","points":[[r.position[0],r.position[2]]],"shape":"rectangle","plot_width":12.,"plot_depth":4.,"plot_yaw":rng.randf_range(-180,180),"target_height":2.,"strength":.7,"plot_grade":[.02,.03]}
		check(T.stroke(r,rectangle)==Old.stroke(r,rectangle),"rectangle differential %s"%i)
	var records:Array=[]
	for z in 4:
		for x in 4:
			var r:=fixture(16);r.uuid="t_%d_%d"%[x,z];r.position=[x*64,0,z*64];records.append(r)
	var index:=Index.new();var neighbors:=N.new();var old_neighbors:=ON.new()
	for iteration in 8:
		if iteration==2:records[5].terrain_mesh.heights[144]=.7
		if iteration==3:records[5].terrain_mesh.heights[152]=.5
		if iteration==4:records[5].terrain_mesh.holes[0]=true
		if iteration==5:records[1].position[0]+=.1
		if iteration==6:records.remove_at(5)
		if iteration==7:records.reverse()
		check(neighbors.update(records)==old_neighbors.update(records),"neighbor invalidation %s"%iteration)
		check(contexts(neighbors.data,old_neighbors.data),"neighbor image/normal exact %s"%iteration)
		for r:Dictionary in records:check(index.connected(records,r)==B.connected(records,r),"spatial adjacency %s %s"%[iteration,r.uuid])
	var sources:Array=[fixture(16),fixture(32),fixture(16)]
	sources[1].uuid="b";sources[1].position[0]=64;sources[2].uuid="c";sources[2].position[2]=64
	for mode in T.MODES:
		var args:={"id":sources[0].uuid,"mode":mode,"points":[[32,0]],"radius":5.,"strength":.2,"target_height":2.,"iterations":1}
		check(B.prepare(sources,sources[0],args,index)==OB.prepare(sources,sources[0],args),"mixed resolution batch %s"%mode)
	for yaw:float in [0.,13.7,90.,-127.]:
		for resolution:int in [3,8,32]:
			var group:Array=[fixture(4),fixture(resolution),fixture(8)]
			var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
			for i in group.size():
				group[i].uuid="mixed_%d"%i;group[i].rotation=[0,yaw,0]
				var at:=basis*Vector3(64 if i==1 else 0,0,64 if i==2 else 0)
				group[i].position=[at.x,0,at.z]
			var at:=basis*Vector3(32,0,32)
			var request:={"id":group[0].uuid,"mode":"raise","points":[[at.x,at.z]],"radius":6.,"strength":.2}
			check(B.prepare(group,group[0],request,index)==OB.prepare(group,group[0],request),"yaw mixed corner %s/%s"%[yaw,resolution])
	var chain:Array=[]
	for i in 257:
		var small:=fixture(2);small.uuid="cap_%d"%i;small.size=[2,1,2];small.position=[i*2,0,0];chain.append(small)
	var cap:={"id":chain[0].uuid,"mode":"raise","points":[[0,0]],"radius":1.}
	check(B.prepare(chain,chain[0],cap,index)==OB.prepare(chain,chain[0],cap),"256 tile cap and error preserved")
	for position:float in [120.,16000.,99999.]:
		var tiny:=fixture();tiny.size=[.01,1,.01];tiny.position=[position,0,position]
		var request:={"id":tiny.uuid,"mode":"raise","points":[[position,position]],"radius":.25}
		check(T.stroke(tiny,request)==Old.stroke(tiny,request),"fine grid rounding %s"%position)
	var r:=fixture();var args:={"id":r.uuid,"mode":"raise","points":[[0,0],[6,6]],"radius":2.,"strength":.2}
	var times:={"brush_old_us":[],"brush_new_us":[]}
	for i in 6:
		for which in (["old","new"] if i%2==0 else ["new","old"]):
			var start:=Time.get_ticks_usec()
			for j in 3:
				if which=="old":Old.stroke(r,args)
				else:T.stroke(r,args)
			times["brush_"+which+"_us"].append((Time.get_ticks_usec()-start)/3.)
	var current_neighbors:=N.new();var baseline_neighbors:=ON.new();current_neighbors.update(records);baseline_neighbors.update(records)
	times["neighbors_old_us"]=[];times["neighbors_new_us"]=[]
	for i in 6:
		records[0].terrain_mesh.heights[144]+=.01
		for which in (["old","new"] if i%2==0 else ["new","old"]):
			var start:=Time.get_ticks_usec()
			if which=="old":baseline_neighbors.update(records)
			else:current_neighbors.update(records)
			times["neighbors_"+which+"_us"].append(Time.get_ticks_usec()-start)
		check(contexts(current_neighbors.data,baseline_neighbors.data),"warm halo differential %s"%i)
	var fresh_index:=Index.new();fresh_index.connected(records,records[0])
	times["connected_old_us"]=[];times["connected_new_us"]=[]
	for i in 6:
		for which in (["old","new"] if i%2==0 else ["new","old"]):
			var start:=Time.get_ticks_usec()
			for j in 5:
				if which=="old":B.connected(records,records[0])
				else:fresh_index.connected(records,records[0])
			times["connected_"+which+"_us"].append((Time.get_ticks_usec()-start)/5.)
	check(fresh_index.builds==1,"height-only warm graph is reused")
	var report:={"failures":failures,"comparisons":comparisons,"timings":times,"neighbor_last_work":current_neighbors.last_work,"index_builds":index.builds}
	FileAccess.open("D:/code/rmmo_runtime/review_artifacts/terrain_incremental_20261017/logic.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("TERRAIN_INCREMENTAL ",JSON.stringify(report));quit(1 if failures else 0)
