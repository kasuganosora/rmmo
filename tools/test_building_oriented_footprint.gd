extends SceneTree
const F=preload("res://scripts/world_editor/building_footprint.gd")
const G=preload("res://scripts/world_editor/selection_geometry.gd")
var failures:=0
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func _initialize()->void:
	var shell:={"uuid":"house","kind":"box","size":[10,4,14],"position":[0,2,0],"rotation":[0,0,0],"building":{"part":"main/baked_1","role":"shell"}}
	for yaw in [0,15,45,75,135]:
		var rotated:=shell.duplicate(true);rotated.rotation[1]=yaw
		var basis:=Basis(Vector3.UP,deg_to_rad(float(yaw)))
		var occupied:=F.components([rotated],Vector3.ZERO,Basis.IDENTITY)
		var road:Dictionary=shell.duplicate(true);road.erase("building");road.size=[30,2,4];road.rotation[1]=yaw
		var at:=basis*Vector3(0,1,-10.0);road.position=[at.x,at.y,at.z]
		check(not F.batches_overlap(occupied,F.record_shapes(road)),"rotated road clearance "+str(yaw))
		at=basis*Vector3(0,1,-8.0);road.position=[at.x,at.y,at.z]
		check(F.batches_overlap(occupied,F.record_shapes(road)),"real intrusion rejected "+str(yaw))
		for point:Vector3 in G.corners(rotated):check(occupied[0].bounds.grow(.001).has_point(point),"all physical corners retained")
	var door:=shell.duplicate(true);door.size=[1.5,2.5,.12];door.position=[0,1.25,0]
	var fixture:={"id":"entry","kind":"door","pivot":[-.75,0,0],"angle":110.0,"open":0.0}
	door.fixture=fixture
	var reserved:Dictionary=F.components([door],Vector3.ZERO,Basis.IDENTITY)[0]
	var closed:=Transform3D(Basis.IDENTITY,Vector3(0,1.25,0));var local:=AABB(Vector3(-.75,-1.25,-.06),Vector3(1.5,2.5,.12))
	var covered:=true
	for step in 111:
		var pose:=preload("res://scripts/world3d/building_fixtures.gd").pose(closed,fixture,step/110.0)
		for i in 8:
			var p:Vector3=pose*local.get_endpoint(i)
			covered=covered and Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),reserved.polygon)
	check(covered,"entire moving door sweep remains protected")
	print("ORIENTED_FOOTPRINT failures=",failures);quit(1 if failures else 0)
