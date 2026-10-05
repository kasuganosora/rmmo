extends SceneTree
## A slightly raised Recast surface must not strand a grounded character.
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label_:String)->void:
	print("PASS " if value else "FAIL ",label_)
	if not value:failures+=1
func run()->void:
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new();root.add_child(nav)
	nav.map=NavigationServer3D.map_create();NavigationServer3D.map_set_active(nav.map,true)
	NavigationServer3D.map_set_use_async_iterations(nav.map,false)
	NavigationServer3D.map_set_cell_height(nav.map,.1)
	nav.region=NavigationServer3D.region_create();NavigationServer3D.region_set_map(nav.region,nav.map)
	nav.mesh.cell_height=.1;nav.mesh.agent_max_climb=.4
	nav.mesh.vertices=PackedVector3Array([Vector3(-2,.401,-2),Vector3(-2,.401,2),Vector3(2,.401,2),Vector3(2,.401,-2)])
	nav.mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	NavigationServer3D.region_set_navigation_mesh(nav.region,nav.mesh)
	NavigationServer3D.map_force_update(nav.map);nav.ready_for_queries=true
	for i in 3:await physics_frame
	check(nav.find_path(Vector3(-1,0,0),Vector3(1,.3,0)).ok,"ground to rotated doorstep tolerates one vertical voxel")
	check(nav.find_path(Vector3(-1,.3,0),Vector3(1,0,0)).ok,"doorstep to street remains reachable")
	check(not nav.find_path(Vector3(-1,-.3,0),Vector3(1,.3,0)).ok,"large vertical gap still rejected")
	check(not nav.find_path(Vector3(-1,0,0),Vector3(1,3.5,0)).ok,"other storey still rejected")
	check(not nav.find_path(Vector3(-1,0,0),Vector3(3,.401,0)).ok,"horizontal edge rejection retained")
	nav.free();print("NAV_HEIGHT_ROUNDING failures=",failures);quit(1 if failures else 0)
