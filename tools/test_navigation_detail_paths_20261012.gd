extends SceneTree
const Nav=preload("res://scripts/world3d/world_navigation.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func box(size_:Vector3,at:Vector3)->Dictionary:
	var mesh:=BoxMesh.new();mesh.size=size_
	return {"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,at),"extras":{"rmmo_collision":"walk"}}
func run()->void:
	create_timer(60).timeout.connect(func():quit(2))
	var specs:Array=[box(Vector3(16,.2,20),Vector3(0,-.1,0))]
	for i in 20:specs.append(box(Vector3(2.4,(i+1)*.15,.28),Vector3(0,(i+1)*.075,i*.28)))
	specs.append(box(Vector3(4,.2,3),Vector3(0,2.9,6.9)))
	# A separate raised bridge deck must retain its upper surface and underpass.
	specs.append(box(Vector3(2,.2,10),Vector3(5,3,0)))
	var nav:=Nav.new();root.add_child(nav);nav.build(specs,Vector3(0,0,-2))
	while not nav.fully_ready:await process_frame
	for pair:Array in [[Vector3(0,0,-2),Vector3(0,3,6.8)],[Vector3(0,3,6.8),Vector3(0,0,-2)],[Vector3(5,3.1,-3),Vector3(5,3.1,3)],[Vector3(3,0,0),Vector3(7,0,0)]]:
		var route:=nav.find_path(pair[0],pair[1]);check(route.ok,"stairs / bridge / underpass "+str(pair))
	check(not nav.find_path(Vector3(5,0,0),Vector3(5,3.1,0)).ok,"separate bridge deck is not a direct vertical connection")
	nav.free();print("NAV_DETAIL_PATHS failures=",failures);quit(failures)
