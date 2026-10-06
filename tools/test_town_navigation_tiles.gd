extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	var nav=preload("res://scripts/world3d/world_navigation.gd").new();root.add_child(nav)
	var ground:=BoxMesh.new();ground.size=Vector3(1400,.2,1400)
	var specs:Array=[{"mesh":ground,"transform":Transform3D(Basis.IDENTITY,Vector3(0,-.1,0)),"extras":{"rmmo_collision":"walk"}}]
	nav.build(specs,Vector3.ZERO)
	while not nav.fully_ready:await process_frame
	var okay:bool=nav.mesh.get_polygon_count()>0
	for x in [-nav.TILE_SIZE,0.,nav.TILE_SIZE]:
		var route:Dictionary=nav.find_path(Vector3(x-2,.05,-50),Vector3(x+2,.05,-50))
		print("NAV_TILE_SEAM ",x," ",route.ok);okay=okay and route.ok
	var across:Dictionary=nav.find_path(Vector3(-620,.05,-600),Vector3(620,.05,600))
	okay=okay and across.ok
	print("TOWN_NAVIGATION_TILES passed=",okay," polygons=",nav.mesh.get_polygon_count()," profile=",nav.loading_profile)
	nav.free();quit(0 if okay else 1)
