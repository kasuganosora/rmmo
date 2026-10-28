extends SceneTree
const Neighbors=preload("res://scripts/world3d/terrain_neighbors.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func records()->Array:
	var rows:Array=[]
	for z:int in 3:
		for x:int in 3:
			var heights:Array=[];var holes:Array=[];holes.resize(16*16);holes.fill(false)
			for v:int in 17:
				for u:int in 17:heights.append(sin(float(x*16+u)*.1)*cos(float(z*16+v)*.1))
			holes[119]=true
			rows.append({"uuid":"tile%d%d"%[x,z],"kind":"box","position":[x*32.,0.,z*32.],"rotation":[0.,0.,0.],"size":[32.,1.,32.],"terrain_mesh":{"version":1,"columns":16,"rows":16,"heights":heights,"holes":holes,"floor":-8.}})
	return rows
func run()->void:
	var source:=records();var original:=var_to_bytes(source);var reference:=Neighbors.new();reference.update(source)
	var trials:Array=[]
	for iteration:int in 4:
		var current:=Neighbors.new();var began:=Time.get_ticks_usec()
		if current.has_method("prepare_selected"):current.call("prepare_selected",source,{"tile11":true})
		else:current.update(source)
		var elapsed:=Time.get_ticks_usec()-began;var actual:Dictionary=current.data.tile11;var expected:Dictionary=reference.data.tile11
		check(actual.normals==expected.normals and actual.neighbors==expected.neighbors,"requested tile retains exact seam normals and neighbor order")
		check(var_to_bytes(Terrain.arrays(source[4],actual))==var_to_bytes(Terrain.arrays(source[4],expected)),"all terrain geometry channels remain byte-identical")
		var images:=0
		for row:Dictionary in current.data.values():
			if row.get("image") is Image:images+=1
		check(current.data.size()==1 and images==1,"only requested geometry context and needed material halo are produced")
		check(actual.image.get_data()==expected.image.get_data() and actual.padding==expected.padding,"ordinary height halo remains exact")
		trials.append({"iteration":iteration,"us":elapsed,"contexts":current.last_work.contexts,"images":images})
	check(var_to_bytes(source)==original,"authoring heights and holes remain untouched")
	print("SELECTED_TERRAIN_CONTEXT ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
