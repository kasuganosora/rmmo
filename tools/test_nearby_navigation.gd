extends SceneTree
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func run()->void:
	create_timer(150).timeout.connect(func():quit(2))
	var nav=preload("res://scripts/world3d/world_navigation.gd").new();root.add_child(nav)
	var ground:=BoxMesh.new();ground.size=Vector3(520,.2,520)
	var wall:=BoxMesh.new();wall.size=Vector3(3,5,12)
	var specs:Array=[{"mesh":ground,"transform":Transform3D(Basis.IDENTITY,Vector3(0,-.1,0)),"extras":{"rmmo_collision":"walk"}}, {"mesh":wall,"transform":Transform3D(Basis.IDENTITY,Vector3(-90,2.5,0)),"extras":{"rmmo_collision":"solid"}}]
	nav.build(specs,Vector3.ZERO)
	while not nav.ready_for_queries:await process_frame
	var route:Dictionary=nav.find_path(Vector3(-40,.05,0),Vector3(-120,.05,0))
	check(route.get("reason")=="pending","outside initial clip requests foreground navigation instead of rejecting click")
	var previous:int=nav.version
	while nav.version==previous:await process_frame
	route=nav.find_path(Vector3(-40,.05,0),Vector3(-120,.05,0))
	check(route.ok,"foreground result covers both current position and pending destination")
	if route.ok:
		check((route.path as PackedVector3Array).size()>2,"new local route detours real wall instead of disabling safety")
	# Recast can retain an isolated floor under a closed solid. Reachability,
	# rather than proximity to any polygon, is what must reject that island.
	check(not nav.find_path(Vector3(-40,.05,0),Vector3(-90,.05,0)).ok,"solid-wall interior has no reachable route")
	var wall_clear:=true
	if route.ok:
		for i in route.path.size()-1:
			if AABB(Vector3(-91.4,-1,-5.9),Vector3(2.8,2,11.8)).intersects_segment(route.path[i],route.path[i+1])!=null:wall_clear=false
	check(wall_clear,"all local route segments stay outside the solid wall")
	check(not nav.find_path(Vector3(-40,.05,0),Vector3(-120,4,0)).ok,"different storey stays rejected")
	nav.follow(Vector3(-130,1,0));previous=nav.version
	while nav.version==previous:await process_frame
	check(nav.find_path(Vector3(-130,.05,0),Vector3(-180,.05,0)).ok,"walking focus extends coverage again")
	# Full-map completion must win over any unfinished nearby result.
	while not nav.fully_ready:await process_frame
	check(nav.find_path(Vector3(-220,.05,-200),Vector3(220,.05,200)).ok,"full tiled mesh publishes after local refreshes")
	check(not nav.find_path(Vector3(-220,.05,-200),Vector3(280,.05,0)).ok,"outside physical map remains unreachable")
	nav.follow(Vector3(600,1,0))
	check(nav._nearby==null,"full map disables redundant foreground bakes")
	nav.free()
	# Leaving while workers are active must not retain a callback to a freed scene.
	var leaving=preload("res://scripts/world3d/world_navigation.gd").new();root.add_child(leaving)
	leaving.build(specs,Vector3.ZERO)
	while not leaving.ready_for_queries:await process_frame
	leaving.follow(Vector3(-60,1,0))
	while leaving._nearby==null or not leaving._nearby.baking:await process_frame
	leaving.free()
	for i in 5:await process_frame
	print("NEARBY_NAVIGATION_FINISHED failures=",failures);quit(1 if failures else 0)
