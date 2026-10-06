extends SceneTree
const Clean=preload("res://scripts/world3d/fortification_deck_cleanup.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
var failed:=0
func _initialize()->void:call_deferred("run")
func check(v:bool,label_:String)->void:
	print(("PASS " if v else "FAIL ")+label_)
	if not v:failed+=1
func triangle(points:Array)->PackedVector2Array:
	var p:=PackedVector2Array(points)
	if Clean.area(p)<0:p.reverse()
	return p
func run()->void:
	var p:=triangle([Vector2(0,0),Vector2(4,0),Vector2(0,4)])
	var cut:=triangle([Vector2(.5,.5),Vector2(1.5,.5),Vector2(.5,1.5)])
	var fragments:=Clean.subtract(p,cut);var area:=0.0
	for piece:PackedVector2Array in fragments:area+=absf(Clean.area(piece))
	check(absf(area-7.5)<.00001,"enclosed triangular cut preserves an actual hole")
	check(Clean.subtract(p,p).is_empty(),"identical triangle removed")
	var away:=triangle([Vector2(4,0),Vector2(8,0),Vector2(4,4)])
	check(Clean.subtract(p,away)==[p],"touching edge does not subdivide or remove geometry")
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(0,7.5,0),Vector3(0,7.5,4),Vector3(4,7.5,0)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2(0,4),Vector2(4,0)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var rebuilt:=Clean.rebuild(arrays,{0:{"pieces":fragments,"origin":Vector2.ZERO,"ids":[0,1,2]}},Vector3(-610,0,-38))
	var attributes_ok:=true
	for i in rebuilt[Mesh.ARRAY_VERTEX].size():
		var v:Vector3=rebuilt[Mesh.ARRAY_VERTEX][i]
		attributes_ok=attributes_ok and absf(v.y-7.5)<.000001 and rebuilt[Mesh.ARRAY_TEX_UV][i].distance_to(Vector2(v.x,v.z))<.00001 and rebuilt[Mesh.ARRAY_NORMAL][i]==Vector3.UP
	check(attributes_ok,"cut vertices preserve plane, interpolated UV and normal")
	var records:Array=[]
	for i in 2:
		records.append({"uuid":"wall%d"%i,"kind":"box","surface_id":"block","position":[-610.0+i*2,7.0,-38.0],"size":[4.0,1.0,4.0],"rotation":[0,0,0],"color":[.5,.5,.5],"collision":"block","fortification":{"id":"test","part":"wall%d"%i,"role":"wall"}})
	var result:=preload("res://scripts/world3d/structure_prefab.gd").fortification(records)
	check(result.ok,"synthetic frozen masonry built at town-scale coordinates")
	if not result.ok:quit(1);return
	var collisions:Array=[]
	for r:Dictionary in result.records:
		var d:=Frozen.decode(r.house_prefab);collisions.append(var_to_bytes(d.meshes[d.entries[0][1][1]]))
	var report:=Clean.apply(result.records,7.5)
	check(report.ok and absf(report.overlap_area-8)<.0001,"exact 8 square metres of overlap removed, no depth offset")
	for i in result.records.size():
		var d:=Frozen.decode(result.records[i].house_prefab)
		check(collisions[i]==var_to_bytes(d.meshes[d.entries[0][1][1]]),"collision byte identity retained")
	var second:=Clean.apply(result.records,7.5)
	check(second.ok and second.changed_records==0,"cleanup is idempotent")
	print("DECK_UNIT_FINISHED failures=",failed);quit(1 if failed else 0)
