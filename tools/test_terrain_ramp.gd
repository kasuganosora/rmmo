extends SceneTree
const Ramp=preload("res://scripts/world_editor/terrain_ramp_tools.gd")
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS: " if ok else "FAIL: ",label)
func terrain()->Dictionary:
	var heights:Array=[];var holes:Array=[]
	# Non-planar quad: its diagonal makes bilinear interpolation incorrect.
	for z in 3:
		for x in 3:heights.append(1. if x==1 and z==1 else 0.)
	for i in 4:holes.append(false)
	return {"uuid":"ground","kind":"box","position":[10.,3.,-6.],"rotation":[0.,90.,0.],"size":[4.,2.,4.],"collision":"walk","terrain_mesh":{"version":1,"columns":2,"rows":2,"floor":-8.,"heights":heights,"holes":holes}}
func _initialize()->void:
	var doc:=Doc.new();var ground:=terrain();doc.records=[ground]
	var result:=Ramp.height_at(doc,[8.5,-5.])
	check(result.ok and absf(result.height-3.5)<.00001,"sample uses native triangle on rotated, vertically scaled non-planar cell")
	check(absf(Vector3(result.normal[0],result.normal[1],result.normal[2]).length()-1)<.00001,"sample returns normalized actual face normal")
	check(not Ramp.height_at(doc,[100.,100.]).ok,"outside ground has no plane fallback")
	ground.terrain_mesh.holes[0]=true
	check(not Ramp.height_at(doc,[8.5,-5.]).ok,"hole has no height fallback")
	ground.terrain_mesh.holes[0]=false
	var duplicate:=ground.duplicate(true);duplicate.uuid="upper";duplicate.position[1]+=5.;doc.records.append(duplicate)
	check(not Ramp.height_at(doc,[8.5,-5.]).ok,"stacked heightfields cannot silently select one level")
	doc.records=[ground];ground.collision="none"
	check(not Ramp.height_at(doc,[8.5,-5.]).ok,"no-collision ground cannot be reported as real support")
	ground.collision="walk";ground.editor_hidden=true
	check(not Ramp.height_at(doc,[8.5,-5.]).ok,"hidden ground cannot be reported as visible support")
	ground.erase("editor_hidden")
	check(absf(Ramp.positive_volume([Vector3(0,1,0),Vector3(2,1,0),Vector3(0,1,2)])-2.)<.000001,"constant delta triangle integrates exact fill volume")
	check(absf(Ramp.positive_volume([Vector3(0,-1,0),Vector3(2,1,0),Vector3(0,1,2)])-5./6.)<.000001,"mixed cut/fill triangle integrates only positive clipped region")
	var original:=Doc.new();original.records=[terrain()];var raised:=Doc.new();var next:=terrain()
	for i in next.terrain_mesh.heights.size():next.terrain_mesh.heights[i]+=.5
	raised.records=[next]
	var earth:=Ramp.earthwork(original,raised,["ground"])
	check(absf(earth.fill_m3-16.)<.000001 and earth.cut_m3==0 and earth.max_fill_m==1.,"earthwork respects vertical scale and native cell area")
	var directory:="D:/code/rmmo_runtime/review_artifacts/terrain_ramp_20261017";DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory+"/logic.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("TERRAIN_RAMP_LOGIC checks=",checks," failures=",failures);quit(1 if failures else 0)
